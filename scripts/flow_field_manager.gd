extends Node2D
class_name FlowFieldManager

@export var grid_size: Vector2i = Vector2i(100, 60) # Expand to fit 1920x1080
@export var cell_size: int = 32
@export var grid_offset: Vector2i = Vector2i(-10, -10)
@export var use_density_penalty: bool = true

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

@export var build_layer: TileMapLayer

func _ready():
	_init_fields()
	if use_gpu:
		_init_gpu_resources()
	scan_layers()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if rd:
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

func _init_gpu_resources():
	rd = RenderingServer.get_rendering_device()
	var shader_file = load("res://scripts/compute_flow_field.glsl")
	var spirv = shader_file.get_spirv()
	flow_shader = rd.shader_create_from_spirv(spirv)
	flow_pipeline = rd.compute_pipeline_create(flow_shader)
	
	var tf_sdf = RDTextureFormat.new()
	tf_sdf.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	tf_sdf.width = grid_size.x
	tf_sdf.height = grid_size.y
	tf_sdf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	sdf_ping = rd.texture_create(tf_sdf, RDTextureView.new(), [])
	sdf_pong = rd.texture_create(tf_sdf, RDTextureView.new(), [])
	final_sdf_tex = sdf_ping
	
	var tf_flow = RDTextureFormat.new()
	tf_flow.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	tf_flow.width = grid_size.x
	tf_flow.height = grid_size.y
	tf_flow.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	
	flow_ping = rd.texture_create(tf_flow, RDTextureView.new(), [])
	flow_pong = rd.texture_create(tf_flow, RDTextureView.new(), [])
	
	var tf_result = RDTextureFormat.new()
	tf_result.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf_result.width = grid_size.x
	tf_result.height = grid_size.y
	tf_result.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	flow_result_tex = rd.texture_create(tf_result, RDTextureView.new(), [])
	
	linear_sampler = rd.sampler_create(RDSamplerState.new())
	
	var trd = Texture2DRD.new()
	trd.texture_rd_rid = flow_result_tex
	ff_texture = trd

func _update_gpu_bindings():
	var obs_rd = RenderingServer.texture_get_rd_texture(obs_texture.get_rid())
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
	obs_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_L8)
	density_image = Image.create(grid_size.x, grid_size.y, false, Image.FORMAT_L8)
	ff_texture = ImageTexture.create_from_image(ff_image)
	obs_texture = ImageTexture.create_from_image(obs_image)
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
		obstacle_field[gp.x][gp.y] = is_obstacle
		if obs_image:
			obs_image.set_pixel(gp.x, gp.y, Color.WHITE if is_obstacle else Color.BLACK)
			
func commit_obstacles():
	if obs_texture and obs_image:
		obs_texture.update(obs_image)
	update_wall_penalties()
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
	
	var active_cells = 0
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			if grid[x][y] != Vector2.ZERO:
				active_cells += 1
	print("[FlowField] Generated field: ", active_cells, " active cells out of ", grid_size.x * grid_size.y)

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
	
	var active_cells = 0
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			if grid[x][y] != Vector2.ZERO:
				active_cells += 1
	print("[FlowField] Generated field (point): ", active_cells, " active cells out of ", grid_size.x * grid_size.y)

func generate_field_gpu(target_pos: Vector2):
	if not rd or not flow_pipeline.is_valid():
		return
		
	var groups_x = max(1, int(ceil(float(grid_size.x) / 16.0)))
	var groups_y = max(1, int(ceil(float(grid_size.y) / 16.0)))
	
	RenderingServer.call_on_render_thread(func():
		var obs_rd = RenderingServer.texture_get_rd_texture(obs_texture.get_rid())
		var density_rd = RenderingServer.texture_get_rd_texture(density_texture.get_rid())
		if obs_rd != _last_obs_rd_rid or density_rd != _last_density_rd_rid:
			_bindings_dirty = true
			_last_obs_rd_rid = obs_rd
			_last_density_rd_rid = density_rd
			
		if _bindings_dirty:
			_update_gpu_bindings()
		if not uniform_set_sdf_ping.is_valid() or not uniform_set_flow_ping.is_valid():
			return
			
		var push = PackedByteArray()
		push.resize(64) # Increased to 64 for alignment and new properties
		push.fill(0)
		push.encode_float(8, target_pos.x)
		push.encode_float(12, target_pos.y)
		push.encode_float(16, float(grid_offset.x))
		push.encode_float(20, float(grid_offset.y))
		push.encode_float(24, float(cell_size))
		push.encode_u32(28, grid_size.x)
		push.encode_u32(32, grid_size.y)
		push.encode_u32(36, 0) # padding
		push.encode_float(40, _last_target_extents.x)
		push.encode_float(44, _last_target_extents.y)
		push.encode_u32(48, 1 if use_density_penalty else 0)
		
		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, flow_pipeline)
		
		# Pass 0: Seed SDF
		rd.compute_list_bind_uniform_set(cl, uniform_set_sdf_ping, 0)
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping, 1)
		push.encode_u32(0, 0)
		rd.compute_list_set_push_constant(cl, push, 64)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)
		
		# Pass 1: JFA SDF
		var max_dim = max(grid_size.x, grid_size.y)
		var step = 1 << int(ceil(log(max_dim) / log(2)))
		step /= 2
		
		var current_sdf_set = uniform_set_sdf_ping
		var last_sdf_tex_is_ping = true
		while step >= 1:
			push.encode_u32(0, 1)
			push.encode_u32(4, step)
			rd.compute_list_set_push_constant(cl, push, 64)
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
			
		# Pass 2: Seed Flow
		# We must rebind the uniform sets for flow (set 1) and keep SDF on set 0
		rd.compute_list_bind_uniform_set(cl, current_sdf_set, 0)
		rd.compute_list_bind_uniform_set(cl, uniform_set_flow_ping, 1)
		
		push.encode_u32(0, 2)
		rd.compute_list_set_push_constant(cl, push, 64)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)
		
		# Pass 3: Extend Flow
		var current_flow_set = uniform_set_flow_ping
		var total_passes = grid_size.x * grid_size.y
		for i in range(min(total_passes, 500)):
			push.encode_u32(0, 3)
			rd.compute_list_set_push_constant(cl, push, 64)
			rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
			rd.compute_list_add_barrier(cl)
			current_flow_set = uniform_set_flow_pong if current_flow_set == uniform_set_flow_ping else uniform_set_flow_ping
			rd.compute_list_bind_uniform_set(cl, current_flow_set, 1)
			
		# Pass 4: Finalize Flow
		push.encode_u32(0, 4)
		rd.compute_list_set_push_constant(cl, push, 64)
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_add_barrier(cl)
		
		rd.compute_list_end()
	)

func are_textures_ready() -> bool:
	if not obs_texture or not density_texture: return false
	var obs_rd = RenderingServer.texture_get_rd_texture(obs_texture.get_rid())
	var density_rd = RenderingServer.texture_get_rd_texture(density_texture.get_rid())
	return obs_rd.is_valid() and density_rd.is_valid()


func update_density(positions: PackedVector2Array, active_count: int):
	var raw_density = []
	for x in range(grid_size.x):
		raw_density.append([])
		for y in range(grid_size.y):
			raw_density[x].append(0)
			density_field[x][y] = 0
			
	for i in range(active_count):
		var pos = positions[i]
		var gx = int(floor(pos.x / float(cell_size))) - grid_offset.x
		var gy = int(floor(pos.y / float(cell_size))) - grid_offset.y
		if gx >= 0 and gx < grid_size.x and gy >= 0 and gy < grid_size.y:
			raw_density[gx][gy] += 1
			
	# Blur the density to prevent sharp bumpy gradients that cause side-to-side zig-zagging
	for x in range(1, grid_size.x - 1):
		for y in range(1, grid_size.y - 1):
			if not obstacle_field[x][y]:
				var sum = raw_density[x][y] * 4
				sum += raw_density[x-1][y] * 2
				sum += raw_density[x+1][y] * 2
				sum += raw_density[x][y-1] * 2
				sum += raw_density[x][y+1] * 2
				sum += raw_density[x-1][y-1]
				sum += raw_density[x+1][y-1]
				sum += raw_density[x-1][y+1]
				sum += raw_density[x+1][y+1]
				density_field[x][y] = sum / 16
				
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var d = density_field[x][y]
			density_image.set_pixel(x, y, Color(min(d, 255) / 255.0, 0, 0, 1))
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
	var grid_pos = Vector2i((world_pos / float(cell_size)).floor()) - grid_offset
	if grid_pos.x >= 0 and grid_pos.x < grid_size.x and grid_pos.y >= 0 and grid_pos.y < grid_size.y:
		return grid[grid_pos.x][grid_pos.y]
	return Vector2.ZERO

func save_static_grid():
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			static_grid[x][y] = grid[x][y]