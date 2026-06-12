extends Node2D
class_name FlowFieldManager

@export var grid_size: Vector2i = Vector2i(100, 60) # Expand to fit 1920x1080
@export var cell_size: int = 32
@export var grid_offset: Vector2i = Vector2i(-10, -10)
@export var use_density_penalty: bool = true
# Congestion penalty (flow cost per density unit, and per-cell cap). The extend
# pass accumulates BOTH detour cost (10/fine cell) and this penalty per FINE cell,
# so a packed lane must price high enough per cell that long clear detours win:
# d≈2-3 agents/coarse cell × scale 15 ≈ 30-45/cell vs base 10. Cap 100 keeps a
# jammed cell from pricing unboundedly like a wall.
@export var density_penalty_scale: float = 15.0
@export var density_penalty_cap: float = 100.0
# Amortized flow-rebuild budget: extend passes submitted per frame while a
# congestion repath is converging (agents keep the old field until finalize).
@export var rebuild_passes_per_frame: int = 250
# Per-agent route-split bias (vertical). Two variants built per field: variant 0
# prefers upper routes, variant 1 prefers lower routes. Agents are assigned by
# id & 1. Value ~6–10; 0 disables the split (falls back to density-penalty only).
@export var route_split_bias: float = 8.0

var grid = [] # 2D array of Vector2 directions
var static_grid = [] # Saved 2D array of Vector2 directions
var cost_field = [] # 2D array of integers
var obstacle_field = [] # 2D array of bools (true = blocked)
var density_field = [] # 2D array of integers
var wall_penalty_field = [] # 2D array of integers

var ff_image: Image
var obs_image: Image
var density_image: Image
var ff_texture: Texture2D
var obs_texture: ImageTexture
var density_texture: ImageTexture

var obs_sub: int = 8  # sub-tile pixels per tile edge — hi_res_obs_image is grid_size * obs_sub

var hi_res_obs_image: Image        # 4× resolution obstacle image for GPU physics collision
var hi_res_obs_texture: ImageTexture  # GPU texture wrapping hi_res_obs_image

# Fine signed-distance field (free-space distance to nearest wall, world units),
# same resolution as hi_res_obs. Built once at map load; used by the physics
# compute for continuous wall-avoidance steering so agents ride path centers
# instead of pinning on path-edge cells.
var wall_sdf_image: Image            # FORMAT_RF distance image
var wall_sdf_texture: ImageTexture   # GPU texture wrapping wall_sdf_image

# GPU properties
var use_gpu: bool = true
var rd: RenderingDevice
var flow_shader: RID
var flow_pipeline: RID
var sdf_ping: RID
var sdf_pong: RID
var final_sdf_tex: RID
var flow_ping: RID
var flow_pong: RID
var flow_result_tex: RID
var linear_sampler: RID
var uniform_set_sdf_ping: RID
var uniform_set_sdf_pong: RID
var uniform_set_flow_ping: RID
var uniform_set_flow_pong: RID
var _bindings_dirty: bool = true
var _last_obs_rd_rid: RID
var _last_density_rd_rid: RID

var _last_target_pos: Vector2 = Vector2.ZERO
var _last_target_extents: Vector2 = Vector2.ZERO
var _has_target: bool = false

# Amortized congestion-repath state (see start_flow_rebuild / tick_flow_rebuild).
# _sdf_set_for_flow is the SDF uniform set the load build ended on — obstacles are
# static during play, so rebuilds skip the JFA and rebind this set directly.
# _rebuild_variant tracks which of the two route-split variants is currently being
# rebuilt (0 then 1); _rebuild_active stays true until variant 1 finalizes.
var _sdf_set_for_flow: RID
var _rebuild_active: bool = false
var _rebuild_seeded: bool = false
var _rebuild_remaining: int = 0
var _rebuild_flow_set_is_ping: bool = true
var _rebuild_variant: int = 0

@export var build_layer: TileMapLayer

func _ready():
	_init_fields()
	if use_gpu:
		_init_gpu_resources()
	scan_layers()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if rd:
			# Free uniform sets BEFORE the textures/samplers they bind. Freeing a bound
			# texture auto-invalidates its uniform set, so freeing the set afterwards
			# double-frees it ("Attempted to free invalid ID").
			var rids = [
				uniform_set_sdf_ping, uniform_set_sdf_pong,
				uniform_set_flow_ping, uniform_set_flow_pong,
				flow_pipeline, flow_shader,
				sdf_ping, sdf_pong,
				flow_ping, flow_pong,
				flow_result_tex, linear_sampler
			]
			# Marshal the frees onto the render thread: this PREDELETE fires on the
			# main thread mid scene-change while in-flight compute/draw still uses
			# these textures — a direct free_rid here races the render thread and
			# hard-crashes the process (no log). On the render thread the frees are
			# ordered after all already-enqueued GPU work. (Lambda must not capture
			# self: it grabs locals only, since the node is being destructed.)
			var device := rd
			RenderingServer.call_on_render_thread(func():
				for r in rids:
					if r and r.is_valid():
						device.free_rid(r)
			)

func _init_gpu_resources():
	rd = RenderingServer.get_rendering_device()
	var shader_file = load("res://shaders/compute_flow_field.glsl")
	var spirv = shader_file.get_spirv()
	flow_shader = rd.shader_create_from_spirv(spirv)
	flow_pipeline = rd.compute_pipeline_create(flow_shader)

	# Flow field is built at the FINE collision resolution (grid_size * obs_sub),
	# matching the hi-res obstacle mask, so every collision pixel has a valid flow
	# vector — no coarse/fine mismatch that strands agents on path-edge cells.
	var fine = grid_size * obs_sub

	var tf_sdf = RDTextureFormat.new()
	tf_sdf.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	tf_sdf.width = fine.x
	tf_sdf.height = fine.y
	tf_sdf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	sdf_ping = rd.texture_create(tf_sdf, RDTextureView.new(), [])
	sdf_pong = rd.texture_create(tf_sdf, RDTextureView.new(), [])
	final_sdf_tex = sdf_ping

	var tf_flow = RDTextureFormat.new()
	tf_flow.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf_flow.width = fine.x
	tf_flow.height = fine.y
	tf_flow.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT

	flow_ping = rd.texture_create(tf_flow, RDTextureView.new(), [])
	flow_pong = rd.texture_create(tf_flow, RDTextureView.new(), [])

	var tf_result = RDTextureFormat.new()
	tf_result.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf_result.width = fine.x
	tf_result.height = fine.y
	tf_result.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	flow_result_tex = rd.texture_create(tf_result, RDTextureView.new(), [])

	linear_sampler = rd.sampler_create(RDSamplerState.new())

	var trd = Texture2DRD.new()
	trd.texture_rd_rid = flow_result_tex
	ff_texture = trd

func _free_gpu_resources():
	if not rd:
		return
	var rids = [
		flow_pipeline, flow_shader,
		sdf_ping, sdf_pong,
		flow_ping, flow_pong,
		flow_result_tex, linear_sampler,
		uniform_set_sdf_ping, uniform_set_sdf_pong,
		uniform_set_flow_ping, uniform_set_flow_pong
	]
	for r in rids:
		if r and r.is_valid():
			rd.free_rid(r)
	uniform_set_sdf_ping = RID()
	uniform_set_sdf_pong = RID()
	uniform_set_flow_ping = RID()
	uniform_set_flow_pong = RID()

# Re-size the flow grid to cover a larger world (called by battle.gd per map before
# the obstacle/SDF/flow pipeline runs). Reallocates the CPU images and the GPU
# textures (sized from grid_size*obs_sub). cell_size/obs_sub are left untouched so
# the world↔fine-pixel ratio — and the straggler tuning that depends on it — is
# preserved; only the cell count grows.
func resize_grid(new_size: Vector2i, new_offset: Vector2i):
	if new_size == grid_size and new_offset == grid_offset:
		return
	grid_size = new_size
	grid_offset = new_offset
	if use_gpu and rd:
		_free_gpu_resources()
	_init_fields()
	if use_gpu:
		_init_gpu_resources()
	_bindings_dirty = true
	_last_obs_rd_rid = RID()
	_last_density_rd_rid = RID()
	_rebuild_active = false
	_sdf_set_for_flow = RID()
	_density_prev = PackedFloat32Array()

func _update_gpu_bindings():
	# Feed the FINE hi-res obstacle mask (grid_size * obs_sub) so the flow compute
	# runs at collision resolution. Falls back to the coarse mask if hi-res is missing.
	var flow_obs_texture: ImageTexture = hi_res_obs_texture if hi_res_obs_texture else obs_texture
	var obs_rd = RenderingServer.texture_get_rd_texture(flow_obs_texture.get_rid())
	var density_rd = RenderingServer.texture_get_rd_texture(density_texture.get_rid())
	if not obs_rd.is_valid() or not density_rd.is_valid():
		_bindings_dirty = true
		return

	if uniform_set_sdf_ping.is_valid(): rd.free_rid(uniform_set_sdf_ping)
	if uniform_set_sdf_pong.is_valid(): rd.free_rid(uniform_set_sdf_pong)
	if uniform_set_flow_ping.is_valid(): rd.free_rid(uniform_set_flow_ping)
	if uniform_set_flow_pong.is_valid(): rd.free_rid(uniform_set_flow_pong)

	var make_sdf = func(sdf1, sdf2):
		var b = []
		var u_obs = RDUniform.new()
		u_obs.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_obs.binding = 0
		u_obs.add_id(linear_sampler)
		u_obs.add_id(obs_rd)
		b.append(u_obs)

		var u_density = RDUniform.new()
		u_density.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_density.binding = 1
		u_density.add_id(linear_sampler)
		u_density.add_id(density_rd)
		b.append(u_density)

		var u_sdf1 = RDUniform.new()
		u_sdf1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_sdf1.binding = 2
		u_sdf1.add_id(sdf1)
		b.append(u_sdf1)

		var u_sdf2 = RDUniform.new()
		u_sdf2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_sdf2.binding = 3
		u_sdf2.add_id(sdf2)
		b.append(u_sdf2)
		return b

	var make_flow = func(flow1, flow2):
		var b = []
		var u_flow1 = RDUniform.new()
		u_flow1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_flow1.binding = 0
		u_flow1.add_id(flow1)
		b.append(u_flow1)

		var u_flow2 = RDUniform.new()
		u_flow2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_flow2.binding = 1
		u_flow2.add_id(flow2)
		b.append(u_flow2)

		var u_res = RDUniform.new()
		u_res.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_res.binding = 2
		u_res.add_id(flow_result_tex)
		b.append(u_res)
		return b

	uniform_set_sdf_ping = rd.uniform_set_create(make_sdf.call(sdf_ping, sdf_pong), flow_shader, 0)
	uniform_set_sdf_pong = rd.uniform_set_create(make_sdf.call(sdf_pong, sdf_ping), flow_shader, 0)
	uniform_set_flow_ping = rd.uniform_set_create(make_flow.call(flow_ping, flow_pong), flow_shader, 1)
	uniform_set_flow_pong = rd.uniform_set_create(make_flow.call(flow_pong, flow_ping), flow_shader, 1)
	_bindings_dirty = false

func _init_fields():
	grid.clear()
	static_grid.clear()
	cost_field.clear()
	obstacle_field.clear()
	density_field.clear()
	wall_penalty_field.clear()
	# CPU Dijkstra arrays are only used by the CPU flow path. At the fine grid
	# (800×480) they would be 384k-entry Variant arrays — skip them on the GPU path.
	if not use_gpu:
		for x in range(grid_size.x):
			grid.append([])
			static_grid.append([])
			cost_field.append([])
			obstacle_field.append([])
			density_field.append([])
			wall_penalty_field.append([])
			for y in range(grid_size.y):
				grid[x].append(Vector2.ZERO)
				static_grid[x].append(Vector2.ZERO)
				cost_field[x].append(65535) # Max value for Dijkstra
				obstacle_field[x].append(false)
				density_field[x].append(0)
				wall_penalty_field[x].append(0)

	ff_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_RGBA8)
	# obs_image stays at tile resolution for the flow field GPU compute
	obs_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_L8)
	# hi_res_obs_image is 4× larger for accurate physics wall collision
	hi_res_obs_image = Image.create(grid_size.x * obs_sub, grid_size.y * obs_sub, false, Image.FORMAT_L8)
	density_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_L8)
	ff_texture = ImageTexture.create_from_image(ff_image)
	obs_texture = ImageTexture.create_from_image(obs_image)
	hi_res_obs_texture = ImageTexture.create_from_image(hi_res_obs_image)
	density_texture = ImageTexture.create_from_image(density_image)

func scan_layers():
	if not build_layer:
		return

	for x in range(grid_offset.x, grid_offset.x + grid_size.x):
		for y in range(grid_offset.y, grid_offset.y + grid_size.y):
			if build_layer.get_cell_source_id(Vector2i(x, y)) != -1:
				set_obstacle(Vector2i(x, y), true)
	commit_obstacles()

func set_obstacle(grid_pos: Vector2i, is_obstacle: bool):
	var gp = grid_pos - grid_offset
	if gp.x >= 0 and gp.x < grid_size.x and gp.y >= 0 and gp.y < grid_size.y:
		if not use_gpu:
			obstacle_field[gp.x][gp.y] = is_obstacle
		if obs_image:
			obs_image.set_pixel(gp.x, gp.y, Color.WHITE if is_obstacle else Color.BLACK)

func commit_obstacles():
	if obs_texture and obs_image:
		obs_texture.update(obs_image)
	if not use_gpu:
		update_wall_penalties()  # CPU Dijkstra penalty; GPU path bakes penalties from the SDF
	if _has_target:
		generate_field_for_rect(_last_target_pos, _last_target_extents)

func update_wall_penalties():
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			wall_penalty_field[x][y] = 0
			if obstacle_field[x][y]:
				continue
			var penalty = 0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx = x + dx
					var ny = y + dy
					if nx >= 0 and nx < grid_size.x and ny >= 0 and ny < grid_size.y:
						if obstacle_field[nx][ny]:
							if dx == 0 or dy == 0:
								penalty += 15
							else:
								penalty += 8
			wall_penalty_field[x][y] = penalty

func generate_field_for_rect(target_pos: Vector2, extents: Vector2):
	_last_target_pos = target_pos
	_last_target_extents = extents
	_has_target = true

	if use_gpu:
		generate_field_gpu(target_pos)
		return

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid[x][y] = Vector2.ZERO
			cost_field[x][y] = 65535

	var rect = Rect2(target_pos - extents, extents * 2)
	var queue = []

	var start_world = rect.position
	var end_world = rect.position + rect.size

	var start_grid = Vector2i((start_world / float(cell_size)).floor()) - grid_offset
	var end_grid = Vector2i((end_world / float(cell_size)).floor()) - grid_offset

	for x in range(start_grid.x, end_grid.x + 1):
		for y in range(start_grid.y, end_grid.y + 1):
			if x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y:
				if not obstacle_field[x][y]:
					cost_field[x][y] = 0
					queue.push_back(Vector2i(x, y))

	# Fallback if the rect is too small to cover any cell centers or everything was blocked
	if queue.is_empty():
		var target_grid_pos = Vector2i((target_pos / float(cell_size)).floor()) - grid_offset
		target_grid_pos.x = clamp(target_grid_pos.x, 0, grid_size.x - 1)
		target_grid_pos.y = clamp(target_grid_pos.y, 0, grid_size.y - 1)
		cost_field[target_grid_pos.x][target_grid_pos.y] = 0
		queue.push_back(target_grid_pos)

	_run_flow_field_passes(queue)
	_update_flow_field_texture()

func generate_field(target_pos: Vector2):
	_last_target_pos = target_pos
	_last_target_extents = Vector2.ZERO
	_has_target = true

	if use_gpu:
		generate_field_gpu(target_pos)
		return

	# Don't re-init obstacle field, just cost and grid
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid[x][y] = Vector2.ZERO
			cost_field[x][y] = 65535

	var target_grid_pos = Vector2i((target_pos / float(cell_size)).floor()) - grid_offset
	target_grid_pos.x = clamp(target_grid_pos.x, 0, grid_size.x - 1)
	target_grid_pos.y = clamp(target_grid_pos.y, 0, grid_size.y - 1)

	var queue = [target_grid_pos]
	cost_field[target_grid_pos.x][target_grid_pos.y] = 0

	_run_flow_field_passes(queue)
	_update_flow_field_texture()

func generate_field_gpu(target_pos: Vector2):
	if not rd or not flow_pipeline.is_valid():
		return
	_rebuild_active = false  # full build supersedes any in-flight repath

	# Flow runs at the fine resolution (grid_size * obs_sub); world↔cell mapping uses
	# the fine cell size (cell_size / obs_sub) and the offset scaled into fine cells.
	var fine := grid_size * obs_sub
	var fine_cell := float(cell_size) / float(obs_sub)
	var fine_offset := grid_offset * obs_sub
	var groups_x = max(1, int(ceil(float(fine.x) / 16.0)))
	var groups_y = max(1, int(ceil(float(fine.y) / 16.0)))
	var flow_obs_texture: ImageTexture = hi_res_obs_texture if hi_res_obs_texture else obs_texture
	var bias := route_split_bias

	RenderingServer.call_on_render_thread(func():
		var obs_rd = RenderingServer.texture_get_rd_texture(flow_obs_texture.get_rid())
		var density_rd = RenderingServer.texture_get_rd_texture(density_texture.get_rid())
		if obs_rd != _last_obs_rd_rid or density_rd != _last_density_rd_rid:
			_bindings_dirty = true
			_last_obs_rd_rid = obs_rd
			_last_density_rd_rid = density_rd

		if _bindings_dirty:
			_update_gpu_bindings()
		if not uniform_set_sdf_ping.is_valid() or not uniform_set_flow_ping.is_valid():
			return

		# Push constant: fields end at offset 68 (uint variant at 60 + float route_bias at 64),
		# but the driver rounds the push_constant block to a 16-byte multiple → must supply 80.
		var push = PackedByteArray()
		push.resize(80)
		push.fill(0)
		push.encode_float(8, target_pos.x)
		push.encode_float(12, target_pos.y)
		push.encode_float(16, float(fine_offset.x))
		push.encode_float(20, float(fine_offset.y))
		push.encode_float(24, fine_cell)
		push.encode_u32(28, fine.x)
		push.encode_u32(32, fine.y)
		push.encode_u32(36, 0) # padding
		push.encode_float(40, _last_target_extents.x)
		push.encode_float(44, _last_target_extents.y)
		push.encode_u32(48, 1 if use_density_penalty else 0)
		push.encode_float(52, density_penalty_scale)
		push.encode_float(56, density_penalty_cap)
		push.encode_float(64, bias)  # route_bias at offset 64 (same for both variants)

		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, flow_pipeline)

		# Pass 0: Seed SDF (variant-agnostic)
		rd.compute_list_bind_uniform_set(cl, uniform_set_sdf_ping, 0)
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping, 1)
		push.encode_u32(0, 0)
		push.encode_u32(60, 0)  # variant field unused for SDF passes
		rd.compute_list_set_push_constant(cl, push, 80)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)

		# Pass 1: JFA SDF
		var max_dim = max(fine.x, fine.y)
		var step = 1 << int(ceil(log(max_dim) / log(2)))
		step /= 2

		var current_sdf_set = uniform_set_sdf_ping
		var last_sdf_tex_is_ping = true
		while step >= 1:
			push.encode_u32(0, 1)
			push.encode_u32(4, step)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)
			step /= 2
			if current_sdf_set == uniform_set_sdf_ping:
				current_sdf_set = uniform_set_sdf_pong
				last_sdf_tex_is_ping = false
			else:
				current_sdf_set = uniform_set_sdf_ping
				last_sdf_tex_is_ping = true
			rd.compute_list_bind_uniform_set(cl, current_sdf_set, 0)
		final_sdf_tex = sdf_ping if last_sdf_tex_is_ping else sdf_pong
		_sdf_set_for_flow = current_sdf_set  # rebinds set 0 on congestion rebuilds

		var total_passes = fine.x * fine.y

		# === Variant 0: seed → extend → finalize (writes RG channels) ===
		push.encode_u32(60, 0)  # variant 0

		rd.compute_list_bind_uniform_set(cl, current_sdf_set, 0)
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping, 1)
		push.encode_u32(0, 2)
		rd.compute_list_set_push_constant(cl, push, 80)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)

		var current_flow_set = uniform_set_flow_ping
		for i in range(min(total_passes, 6000)):
			push.encode_u32(0, 3)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)
			current_flow_set = uniform_set_flow_pong if current_flow_set == uniform_set_flow_ping else uniform_set_flow_ping
			rd.compute_list_bind_uniform_set(cl, current_flow_set, 1)

		push.encode_u32(0, 4)
		rd.compute_list_set_push_constant(cl, push, 80)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)

		# === Variant 1: re-seed → extend → finalize (writes BA channels) ===
		push.encode_u32(60, 1)  # variant 1

		rd.compute_list_bind_uniform_set(cl, current_sdf_set, 0)
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping, 1)  # explicit reset to ping
		push.encode_u32(0, 2)
		rd.compute_list_set_push_constant(cl, push, 80)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)

		current_flow_set = uniform_set_flow_ping
		for i in range(min(total_passes, 6000)):
			push.encode_u32(0, 3)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)
			current_flow_set = uniform_set_flow_pong if current_flow_set == uniform_set_flow_ping else uniform_set_flow_ping
			rd.compute_list_bind_uniform_set(cl, current_flow_set, 1)

		push.encode_u32(0, 4)
		rd.compute_list_set_push_constant(cl, push, 80)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)

		rd.compute_list_end()
	)

# --- Amortized congestion repath ------------------------------------------------
# Re-runs the flow generation with the CURRENT density texture so the min-cost
# field routes around congested cells. Spread across frames (the full extend is
# the few-second map-load cost): each tick submits up to rebuild_passes_per_frame
# extend passes; only the final tick runs the finalize pass that writes
# flow_result_tex, so agents keep steering by the old field until the new one is
# fully converged. The SDF JFA is skipped — obstacles are static during play, so
# the load build's SDF set (_sdf_set_for_flow) is rebound as-is.
#
# Both route-split variants are rebuilt sequentially: variant 0 completes
# (seed+extend+finalize), then variant 1 converges. _rebuild_active stays true
# until variant 1 finalizes. Only each variant's finalize writes its channel pair
# (RG for variant 0, BA for variant 1), so agents keep the old field throughout.

func start_flow_rebuild() -> void:
	if not use_gpu or not rd or not _sdf_set_for_flow.is_valid() or not _has_target:
		return
	var fine := grid_size * obs_sub
	_rebuild_remaining = min(fine.x * fine.y, 6000)
	_rebuild_seeded = false
	_rebuild_flow_set_is_ping = true
	_rebuild_variant = 0
	_rebuild_active = true

func tick_flow_rebuild() -> void:
	if not _rebuild_active or not rd or not flow_pipeline.is_valid():
		return
	var fine := grid_size * obs_sub
	var fine_cell := float(cell_size) / float(obs_sub)
	var fine_offset := grid_offset * obs_sub
	var groups_x = max(1, int(ceil(float(fine.x) / 16.0)))
	var groups_y = max(1, int(ceil(float(fine.y) / 16.0)))
	var batch: int = min(rebuild_passes_per_frame, _rebuild_remaining)
	var do_seed: bool = not _rebuild_seeded
	var finalize: bool = (_rebuild_remaining - batch) <= 0
	var start_is_ping := _rebuild_flow_set_is_ping
	var current_variant := _rebuild_variant
	var bias := route_split_bias

	RenderingServer.call_on_render_thread(func():
		if not _sdf_set_for_flow.is_valid() or not uniform_set_flow_ping.is_valid():
			_rebuild_active = false
			return

		var push = PackedByteArray()
		push.resize(80)
		push.fill(0)
		push.encode_float(8, _last_target_pos.x)
		push.encode_float(12, _last_target_pos.y)
		push.encode_float(16, float(fine_offset.x))
		push.encode_float(20, float(fine_offset.y))
		push.encode_float(24, fine_cell)
		push.encode_u32(28, fine.x)
		push.encode_u32(32, fine.y)
		push.encode_float(40, _last_target_extents.x)
		push.encode_float(44, _last_target_extents.y)
		push.encode_u32(48, 1 if use_density_penalty else 0)
		push.encode_float(52, density_penalty_scale)
		push.encode_float(56, density_penalty_cap)
		push.encode_u32(60, current_variant)
		push.encode_float(64, bias)

		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, flow_pipeline)
		rd.compute_list_bind_uniform_set(cl, _sdf_set_for_flow, 0)
		var flow_is_ping := start_is_ping
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping if flow_is_ping else uniform_set_flow_pong, 1)

		if do_seed:
			push.encode_u32(0, 2)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)

		for i in range(batch):
			push.encode_u32(0, 3)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)
			flow_is_ping = not flow_is_ping
			rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping if flow_is_ping else uniform_set_flow_pong, 1)

		if finalize:
			push.encode_u32(0, 4)
			rd.compute_list_set_push_constant(cl, push, 80)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)

		rd.compute_list_end()

		# State transition: after variant 0 finalizes, start variant 1 next tick.
		# After variant 1 finalizes, deactivate the rebuild.
		if finalize and current_variant == 0:
			_rebuild_variant = 1
			_rebuild_remaining = min(fine.x * fine.y, 6000)
			_rebuild_seeded = false
			_rebuild_flow_set_is_ping = true  # reset to ping for variant 1's seed
			# _rebuild_active stays true — variant 1 still needs to run
		else:
			_rebuild_seeded = true
			_rebuild_flow_set_is_ping = flow_is_ping
			_rebuild_remaining -= batch
			if finalize:  # finalize && current_variant == 1 → both variants done
				_rebuild_active = false
	)

func is_flow_rebuilding() -> bool:
	return _rebuild_active

func are_textures_ready() -> bool:
	if not obs_texture or not density_texture: return false
	var obs_rd = RenderingServer.texture_get_rd_texture(obs_texture.get_rid())
	var density_rd = RenderingServer.texture_get_rd_texture(density_texture.get_rid())
	return obs_rd.is_valid() and density_rd.is_valid()


# Decayed density memory: congested cells stay "hot" across repath cycles
# (hysteresis) so the field doesn't flip-flop routes every rebuild; cooling is
# gradual when a lane really empties. Retention per ~2s update.
const DENSITY_RETENTION := 0.65
var _density_prev := PackedFloat32Array()

# Rebuild the coarse density texture from live agent positions. Self-contained
# (no CPU-path member arrays — those are skipped on the GPU path). Dead agents
# stay in the GPU buffer inside active_count, so filter by health > 0.
func update_density(positions: PackedVector2Array, healths: PackedFloat32Array):
	var gw := grid_size.x
	var gh := grid_size.y
	var raw := PackedInt32Array()
	raw.resize(gw * gh)
	if _density_prev.size() != gw * gh:
		_density_prev.resize(gw * gh)
		_density_prev.fill(0.0)

	for i in range(positions.size()):
		if i < healths.size() and healths[i] <= 0.0:
			continue
		var pos := positions[i]
		var gx := int(floor(pos.x / float(cell_size))) - grid_offset.x
		var gy := int(floor(pos.y / float(cell_size))) - grid_offset.y
		if gx >= 0 and gx < gw and gy >= 0 and gy < gh:
			raw[gy * gw + gx] += 1

	# Blur so the cost gradient is smooth (no side-to-side zig-zagging), then
	# combine with the decayed previous value (decay-max EMA).
	for y in range(gh):
		for x in range(gw):
			var sum := raw[y * gw + x] * 4
			if x > 0: sum += raw[y * gw + x - 1] * 2
			if x < gw - 1: sum += raw[y * gw + x + 1] * 2
			if y > 0: sum += raw[(y - 1) * gw + x] * 2
			if y < gh - 1: sum += raw[(y + 1) * gw + x] * 2
			if x > 0 and y > 0: sum += raw[(y - 1) * gw + x - 1]
			if x < gw - 1 and y > 0: sum += raw[(y - 1) * gw + x + 1]
			if x > 0 and y < gh - 1: sum += raw[(y + 1) * gw + x - 1]
			if x < gw - 1 and y < gh - 1: sum += raw[(y + 1) * gw + x + 1]
			var d: float = max(float(sum) / 16.0, _density_prev[y * gw + x] * DENSITY_RETENTION)
			_density_prev[y * gw + x] = d
			density_image.set_pixel(x, y, Color(minf(d, 255.0) / 255.0, 0, 0, 1))
	density_texture.update(density_image)

class MinHeap:
	var heap = []

	func push(item: Vector2i, cost: int):
		heap.append({"item": item, "cost": cost})
		_upheap(heap.size() - 1)

	func pop() -> Dictionary:
		if heap.is_empty():
			return {}
		if heap.size() == 1:
			return heap.pop_back()
		var root = heap[0]
		heap[0] = heap.pop_back()
		_downheap(0)
		return root

	func is_empty() -> bool:
		return heap.is_empty()

	@warning_ignore("integer_division")
	func _upheap(idx: int):
		var parent = int((idx - 1) * 0.5)
		while idx > 0 and heap[idx].cost < heap[parent].cost:
			var temp = heap[idx]
			heap[idx] = heap[parent]
			heap[parent] = temp
			idx = parent
			parent = int((idx - 1) * 0.5)

	@warning_ignore("integer_division")
	func _downheap(idx: int):
		var size = heap.size()
		while true:
			var smallest = idx
			var left = 2 * idx + 1
			var right = 2 * idx + 2
			if left < size and heap[left].cost < heap[smallest].cost:
				smallest = left
			if right < size and heap[right].cost < heap[smallest].cost:
				smallest = right
			if smallest == idx:
				break
			var temp = heap[idx]
			heap[idx] = heap[smallest]
			heap[smallest] = temp
			idx = smallest

func _run_flow_field_passes(initial_queue: Array):
	# 1. Dijkstra Pass (Optimized with MinHeap)
	var pq = MinHeap.new()
	for item in initial_queue:
		pq.push(item, cost_field[item.x][item.y])

	var safety_counter = 0
	while not pq.is_empty():
		safety_counter += 1
		if safety_counter > 200000:
			printerr("ERROR: FlowFieldManager Dijkstra loop exceeded safety limit!")
			break

		var popped = pq.pop()
		if popped.is_empty():
			break

		var current = popped.item
		var pop_cost = popped.cost

		# Skip if we already found a shorter path to this cell before we popped it
		if pop_cost > cost_field[current.x][current.y]:
			continue

		var current_cost = cost_field[current.x][current.y]

		# 1.1 Cardinals
		# Up
		if current.y + 1 < grid_size.y:
			var n = Vector2i(current.x, current.y + 1)
			if not obstacle_field[n.x][n.y]:
				var penalty = wall_penalty_field[n.x][n.y]
				if use_density_penalty:
					penalty += mini(density_field[n.x][n.y] * 2, 25)
				var new_cost = current_cost + 10 + penalty
				if cost_field[n.x][n.y] > new_cost:
					cost_field[n.x][n.y] = new_cost
					pq.push(n, new_cost)
		# Down
		if current.y - 1 >= 0:
			var n = Vector2i(current.x, current.y - 1)
			if not obstacle_field[n.x][n.y]:
				var penalty = wall_penalty_field[n.x][n.y]
				if use_density_penalty:
					penalty += mini(density_field[n.x][n.y] * 2, 25)
				var new_cost = current_cost + 10 + penalty
				if cost_field[n.x][n.y] > new_cost:
					cost_field[n.x][n.y] = new_cost
					pq.push(n, new_cost)
		# Right
		if current.x + 1 < grid_size.x:
			var n = Vector2i(current.x + 1, current.y)
			if not obstacle_field[n.x][n.y]:
				var penalty = wall_penalty_field[n.x][n.y]
				if use_density_penalty:
					penalty += mini(density_field[n.x][n.y] * 2, 25)
				var new_cost = current_cost + 10 + penalty
				if cost_field[n.x][n.y] > new_cost:
					cost_field[n.x][n.y] = new_cost
					pq.push(n, new_cost)
		# Left
		if current.x - 1 >= 0:
			var n = Vector2i(current.x - 1, current.y)
			if not obstacle_field[n.x][n.y]:
				var penalty = wall_penalty_field[n.x][n.y]
				if use_density_penalty:
					penalty += mini(density_field[n.x][n.y] * 2, 25)
				var new_cost = current_cost + 10 + penalty
				if cost_field[n.x][n.y] > new_cost:
					cost_field[n.x][n.y] = new_cost
					pq.push(n, new_cost)

		# 1.2 Diagonals (allow if both cardinals are not obstacles to prevent corner scraping)
		# (1, 1)
		if current.x + 1 < grid_size.x and current.y + 1 < grid_size.y:
			if not obstacle_field[current.x + 1][current.y] and not obstacle_field[current.x][current.y + 1]:
				var n = Vector2i(current.x + 1, current.y + 1)
				if not obstacle_field[n.x][n.y]:
					var penalty = wall_penalty_field[n.x][n.y]
					if use_density_penalty:
						penalty += mini(density_field[n.x][n.y] * 2, 25)
					var new_cost = current_cost + 14 + penalty
					if cost_field[n.x][n.y] > new_cost:
						cost_field[n.x][n.y] = new_cost
						pq.push(n, new_cost)
		# (1, -1)
		if current.x + 1 < grid_size.x and current.y - 1 >= 0:
			if not obstacle_field[current.x + 1][current.y] and not obstacle_field[current.x][current.y - 1]:
				var n = Vector2i(current.x + 1, current.y - 1)
				if not obstacle_field[n.x][n.y]:
					var penalty = wall_penalty_field[n.x][n.y]
					if use_density_penalty:
						penalty += mini(density_field[n.x][n.y] * 2, 25)
					var new_cost = current_cost + 14 + penalty
					if cost_field[n.x][n.y] > new_cost:
						cost_field[n.x][n.y] = new_cost
						pq.push(n, new_cost)
		# (-1, 1)
		if current.x - 1 >= 0 and current.y + 1 < grid_size.y:
			if not obstacle_field[current.x - 1][current.y] and not obstacle_field[current.x][current.y + 1]:
				var n = Vector2i(current.x - 1, current.y + 1)
				if not obstacle_field[n.x][n.y]:
					var penalty = wall_penalty_field[n.x][n.y]
					if use_density_penalty:
						penalty += mini(density_field[n.x][n.y] * 2, 25)
					var new_cost = current_cost + 14 + penalty
					if cost_field[n.x][n.y] > new_cost:
						cost_field[n.x][n.y] = new_cost
						pq.push(n, new_cost)
		# (-1, -1)
		if current.x - 1 >= 0 and current.y - 1 >= 0:
			if not obstacle_field[current.x - 1][current.y] and not obstacle_field[current.x][current.y - 1]:
				var n = Vector2i(current.x - 1, current.y - 1)
				if not obstacle_field[n.x][n.y]:
					var penalty = wall_penalty_field[n.x][n.y]
					if use_density_penalty:
						penalty += mini(density_field[n.x][n.y] * 2, 25)
					var new_cost = current_cost + 14 + penalty
					if cost_field[n.x][n.y] > new_cost:
						cost_field[n.x][n.y] = new_cost
						pq.push(n, new_cost)

	# 2. Vector Field Pass
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			if obstacle_field[x][y]: continue # No direction in walls

			var min_cost = cost_field[x][y]
			var best_neighbor = Vector2i(x, y)

			# Check cardinals
			# Up
			if y + 1 < grid_size.y and not obstacle_field[x][y + 1]:
				var c = cost_field[x][y + 1]
				if c < min_cost:
					min_cost = c
					best_neighbor = Vector2i(x, y + 1)
			# Down
			if y - 1 >= 0 and not obstacle_field[x][y - 1]:
				var c = cost_field[x][y - 1]
				if c < min_cost:
					min_cost = c
					best_neighbor = Vector2i(x, y - 1)
			# Right
			if x + 1 < grid_size.x and not obstacle_field[x + 1][y]:
				var c = cost_field[x + 1][y]
				if c < min_cost:
					min_cost = c
					best_neighbor = Vector2i(x + 1, y)
			# Left
			if x - 1 >= 0 and not obstacle_field[x - 1][y]:
				var c = cost_field[x - 1][y]
				if c < min_cost:
					min_cost = c
					best_neighbor = Vector2i(x - 1, y)

			# Check diagonals
			# (1, 1)
			if x + 1 < grid_size.x and y + 1 < grid_size.y:
				if not obstacle_field[x + 1][y] and not obstacle_field[x][y + 1] and not obstacle_field[x + 1][y + 1]:
					var c = cost_field[x + 1][y + 1]
					if c < min_cost:
						min_cost = c
						best_neighbor = Vector2i(x + 1, y + 1)
			# (1, -1)
			if x + 1 < grid_size.x and y - 1 >= 0:
				if not obstacle_field[x + 1][y] and not obstacle_field[x][y - 1] and not obstacle_field[x + 1][y - 1]:
					var c = cost_field[x + 1][y - 1]
					if c < min_cost:
						min_cost = c
						best_neighbor = Vector2i(x + 1, y - 1)
			# (-1, 1)
			if x - 1 >= 0 and y + 1 < grid_size.y:
				if not obstacle_field[x - 1][y] and not obstacle_field[x][y + 1] and not obstacle_field[x - 1][y + 1]:
					var c = cost_field[x - 1][y + 1]
					if c < min_cost:
						min_cost = c
						best_neighbor = Vector2i(x - 1, y + 1)
			# (-1, -1)
			if x - 1 >= 0 and y - 1 >= 0:
				if not obstacle_field[x - 1][y] and not obstacle_field[x][y - 1] and not obstacle_field[x - 1][y - 1]:
					var c = cost_field[x - 1][y - 1]
					if c < min_cost:
						min_cost = c
						best_neighbor = Vector2i(x - 1, y - 1)

			if best_neighbor != Vector2i(x, y):
				grid[x][y] = (Vector2(best_neighbor) - Vector2(x, y)).normalized()

func _update_flow_field_texture():
	if not ff_image or not ff_texture: return
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var v = grid[x][y]
			# Map -1..1 to 0..1
			var r = (v.x + 1.0) * 0.5
			var g = (v.y + 1.0) * 0.5
			ff_image.set_pixel(x, y, Color(r, g, 0.0, 1.0))
	ff_texture.update(ff_image)

func get_direction(world_pos: Vector2) -> Vector2:
	# CPU grid only exists on the CPU path; GPU path reads flow from the texture.
	if use_gpu or grid.is_empty():
		return Vector2.ZERO
	var grid_pos = Vector2i((world_pos / float(cell_size)).floor()) - grid_offset
	if grid_pos.x >= 0 and grid_pos.x < grid_size.x and grid_pos.y >= 0 and grid_pos.y < grid_size.y:
		return grid[grid_pos.x][grid_pos.y]
	return Vector2.ZERO

func save_static_grid():
	if use_gpu or grid.is_empty():
		return  # CPU grid unused on the GPU path
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			static_grid[x][y] = grid[x][y]
