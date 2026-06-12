extends Node
class_name GPUSimManager

var rd: RenderingDevice

var compute_physics: GPU.SimpleCompute
var agent_draw: GPU.SimpleDraw

var agent_buffer_rid: RID
var agent_buffer_rid_2: RID
var grid_counts_rid: RID
var grid_cells_rid: RID
var dummy_ff_rid: RID
var dummy_obs_rid: RID
var wall_sdf_rid: RID
var last_ff_rd: RID
var last_obs_rd: RID
var linear_sampler_rid: RID
var texture_rd_rid: RID
var agent_data_tex: Texture2DRD

var draw_framebuffer: RID
var draw_texture_rid: RID
var draw_texture: Texture2DRD
var dispatch_buffer: RID

var turrets_buffer_rid: RID
var damage_events_buffer_rid: RID
var swap_buffer_rid: RID

var dead_enemies_buffer: GPU.ReadbackBuffer
var turret_fire_events_buffer: GPU.ReadbackBuffer
var nexus_damage_buffer: GPU.ReadbackBufferInt32

const MAX_AGENTS = 150000
const AGENT_STRUCT_SIZE = 48
const HASH_WIDTH = 128
const HASH_HEIGHT = 128
const HASH_CELLS = HASH_WIDTH * HASH_HEIGHT
# Agent-agent separation is an iterative solver (like the studio reference's 6-pass
# impulse solver): each iteration re-bins the updated positions and relaxes overlaps,
# so crowd pressure dissipates smoothly instead of one capped nudge pinning lone
# agents against walls (the straggler cause). Lower this if narrow corridors block.
const SEPARATION_ITERATIONS = 6

var active_count: int = 0   # Highest used agent slot this wave (GPU buffer occupancy; never shrinks mid-wave).
var alive_count: int = 0    # Agents actually alive (decremented by the death readback).
var push_attributes: Array[GPU.PushAttribute] = []

# Per-type tables fed by EnemyConfig at battle start (index = enemy type index).
var _type_golds: PackedInt32Array = PackedInt32Array()
var _type_nexus_dmg: PackedInt32Array = PackedInt32Array()

# Death/nexus-damage readback cadence. The GPU records every death (and nexus hit)
# into ReadbackBuffer segments; we drain them on a timer and emit gameplay signals.
const READBACK_INTERVAL := 0.2
const DEAD_SEGMENT_CAP := 4095  # shader drops records past this (atomic count keeps rising)
var _readback_timer: float = 0.0
var _readback_inflight: bool = false
var _readback_inflight_ms: int = 0

func _ready():
	rd = RenderingServer.get_rendering_device()
	_init_buffers()
	_init_compute()

	GlobalEvents.aoe_damage_requested.connect(apply_aoe_damage)
	GlobalEvents.aoe_freeze_requested.connect(apply_aoe_freeze)
	GlobalEvents.aoe_slow_requested.connect(apply_aoe_slow)
	GlobalEvents.turret_update_requested.connect(update_turret)

func _process(delta: float) -> void:
	# Watchdog: a readback callback that never fired (e.g. device teardown) must not
	# block draining forever.
	if _readback_inflight and Time.get_ticks_msec() - _readback_inflight_ms > 2000:
		_readback_inflight = false
	_readback_timer += delta
	if _readback_timer < READBACK_INTERVAL:
		return
	_readback_timer = 0.0
	if active_count <= 0 or _readback_inflight:
		return
	if dead_enemies_buffer == null or nexus_damage_buffer == null:
		return
	_readback_inflight = true
	_readback_inflight_ms = Time.get_ticks_msec()
	RenderingServer.call_on_render_thread(func():
		if not dead_enemies_buffer.data_buffer.is_valid() or not nexus_damage_buffer.buffer.is_valid():
			call_deferred("_clear_readback_inflight")
			return
		# ORDER MATTERS: enqueue the async read FIRST, then rotate the write segment.
		# The snapshot then contains everything written so far (including the current
		# segment) and compute submitted after the header update writes the fresh
		# segment — no events lost, none double-read. Incrementing first would zero a
		# segment that was never read.
		dead_enemies_buffer.read_counted_async(func(count: int, bytes: PackedByteArray):
			call_deferred("_on_dead_events", count, bytes)
		)
		dead_enemies_buffer.increment_write()
		nexus_damage_buffer.read_accumulated_async(func(total: int):
			call_deferred("_on_nexus_damage_readback", total)
		)
		nexus_damage_buffer.increment_write()
	)

func _clear_readback_inflight() -> void:
	_readback_inflight = false

func _on_dead_events(count: int, bytes: PackedByteArray) -> void:
	# Record layout (16 bytes): [id | 0x80000000 if nexus arrival, type, pos.x bits, pos.y bits].
	# The atomic count can exceed the segment capacity when records were dropped — clamp.
	count = mini(count, mini(DEAD_SEGMENT_CAP, bytes.size() / 16))
	for i in range(count):
		var off := i * 16
		var id_field := bytes.decode_u32(off)
		var type := bytes.decode_u32(off + 4)
		var is_arrival := (id_field & 0x80000000) != 0
		if not is_arrival:
			var pos := Vector2(bytes.decode_float(off + 8), bytes.decode_float(off + 12))
			var gold: int = _type_golds[type] if type < _type_golds.size() else 0
			GlobalEvents.enemy_killed.emit(type, pos, gold)
	# Decrement AFTER the emits: a dying Splitter's children spawn synchronously in
	# the enemy_killed handler and must be counted before any wave-clear check runs.
	alive_count = maxi(0, alive_count - count)

func _on_nexus_damage_readback(total: int) -> void:
	# This callback always fires (even with 0 damage) and is enqueued after the dead
	# read, so it doubles as the end-of-drain marker.
	_readback_inflight = false
	if total > 0:
		GlobalEvents.nexus_damaged.emit(total)

func set_enemy_type_data(golds: Array, nexus_dmg: Array) -> void:
	_type_golds = PackedInt32Array(golds)
	_type_nexus_dmg = PackedInt32Array(nexus_dmg)

func reset_wave_slots() -> void:
	# Safe only when nothing is alive: dead slots are health-gated in every shader
	# pass and get overwritten by buffer_update on respawn.
	active_count = 0
	alive_count = 0

func _init_buffers():
	var agent_data_byte_array = PackedByteArray()
	agent_data_byte_array.resize(MAX_AGENTS * AGENT_STRUCT_SIZE)
	agent_data_byte_array.fill(0)
	agent_buffer_rid = GPU.create_storage_buffer(rd, agent_data_byte_array, "agents_1")
	agent_buffer_rid_2 = GPU.create_storage_buffer(rd, agent_data_byte_array, "agents_2")
	
	var turrets_byte_array = PackedByteArray()
	turrets_byte_array.resize(48 * 1024)
	turrets_byte_array.fill(0)
	turrets_buffer_rid = GPU.create_storage_buffer(rd, turrets_byte_array, "turrets")
	
	var swap_bytes = PackedByteArray()
	swap_bytes.resize(AGENT_STRUCT_SIZE)
	swap_buffer_rid = GPU.create_storage_buffer(rd, swap_bytes, "swap")

	var grid_counts_bytes = PackedByteArray()
	grid_counts_bytes.resize(HASH_CELLS * 4)
	grid_counts_bytes.fill(0)
	grid_counts_rid = GPU.create_storage_buffer(rd, grid_counts_bytes, "grid_counts")
	
	var grid_cells_bytes = PackedByteArray()
	grid_cells_bytes.resize(HASH_CELLS * 32 * 4)
	grid_cells_bytes.fill(0)
	grid_cells_rid = GPU.create_storage_buffer(rd, grid_cells_bytes, "grid_cells")
	
	linear_sampler_rid = rd.sampler_create(RDSamplerState.new())
	
	var dummy_ff_img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var dummy_ff_tf = RDTextureFormat.new()
	dummy_ff_tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	dummy_ff_tf.width = 1; dummy_ff_tf.height = 1
	dummy_ff_tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	dummy_ff_rid = GPU.texture_create(rd, "dummy_ff", dummy_ff_tf, RDTextureView.new(), [dummy_ff_img.get_data()])
	
	var dummy_obs_img = Image.create(1, 1, false, Image.FORMAT_L8)
	var dummy_obs_tf = RDTextureFormat.new()
	dummy_obs_tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	dummy_obs_tf.width = 1; dummy_obs_tf.height = 1
	dummy_obs_tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	dummy_obs_rid = GPU.texture_create(rd, "dummy_obs", dummy_obs_tf, RDTextureView.new(), [dummy_obs_img.get_data()])

	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = 512; tf.height = 512
	tf.depth = 1; tf.array_layers = 1; tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	texture_rd_rid = GPU.texture_create(rd, "agent_data_tex", tf, RDTextureView.new(), [])
	agent_data_tex = Texture2DRD.new()
	agent_data_tex.texture_rd_rid = texture_rd_rid
	
	var draw_tf = RDTextureFormat.new()
	draw_tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	draw_tf.width = 1920; draw_tf.height = 1080
	draw_tf.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	draw_texture_rid = GPU.texture_create(rd, "draw_output", draw_tf, RDTextureView.new(), [])
	draw_framebuffer = rd.framebuffer_create([draw_texture_rid])
	draw_texture = Texture2DRD.new()
	draw_texture.texture_rd_rid = draw_texture_rid
	
	var disp_bytes = PackedByteArray()
	disp_bytes.resize(16)
	disp_bytes.encode_u32(0, 6) # vertex count
	disp_bytes.encode_u32(4, 0) # instance count
	disp_bytes.encode_u32(8, 0) # first vertex
	disp_bytes.encode_u32(12, 0) # first instance
	var dispatch_usage = RenderingDevice.STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT
	dispatch_buffer = rd.storage_buffer_create(disp_bytes.size(), disp_bytes, dispatch_usage)
	GPU.set_resource_name(rd, dispatch_buffer, "draw_dispatch")
	
	dead_enemies_buffer = GPU.ReadbackBuffer.new(rd, "dead_enemies", 2, 4096, 16, 16)
	turret_fire_events_buffer = GPU.ReadbackBuffer.new(rd, "turret_fire_events", 2, 4096, 16, 16)
	nexus_damage_buffer = GPU.ReadbackBufferInt32.new(rd, "nexus_damage")
	
	var dmg_bytes = PackedByteArray()
	dmg_bytes.resize(16 + 1024 * 32)
	damage_events_buffer_rid = GPU.create_storage_buffer(rd, dmg_bytes, "damage_events")

func _init_compute():
	var shader_file = load("res://shaders/compute_physics.glsl")
	push_attributes.clear()
	push_attributes.append(GPU.PushAttribute.create_dynamic(func(_p_push: PackedByteArray, _offset: int): pass, 112))
	
	var uniforms = GPU.UniformsArray.new([
		GPU.create_storage_buffer_uniform(0, agent_buffer_rid),
		GPU.create_storage_buffer_uniform(1, grid_counts_rid),
		GPU.create_storage_buffer_uniform(2, grid_cells_rid),
		GPU.create_sampler_texture_uniform(3, linear_sampler_rid, dummy_ff_rid),
		GPU.create_sampler_texture_uniform(4, linear_sampler_rid, dummy_obs_rid),
		GPU.create_image_uniform(5, texture_rd_rid),
		GPU.create_storage_buffer_uniform(6, dead_enemies_buffer.data_buffer),
		GPU.create_storage_buffer_uniform(7, nexus_damage_buffer.buffer),
		GPU.create_storage_buffer_uniform(8, damage_events_buffer_rid),
		GPU.create_storage_buffer_uniform(9, turrets_buffer_rid),
		GPU.create_storage_buffer_uniform(10, turret_fire_events_buffer.data_buffer),
		GPU.create_storage_buffer_uniform(11, agent_buffer_rid_2),
		GPU.create_sampler_texture_uniform(12, linear_sampler_rid, dummy_obs_rid)
	])
	
	compute_physics = GPU.SimpleCompute.new(rd, "compute_physics", shader_file, {0: uniforms}, push_attributes)
	
	var draw_shader_file = load("res://shaders/agent_draw.glsl")
	var draw_uniforms = GPU.UniformsArray.new([
		GPU.create_sampler_texture_uniform(0, linear_sampler_rid, texture_rd_rid)
	])
	var draw_push = GPU.PushAttribute.create_dynamic(func(_p_push: PackedByteArray, _offset: int): pass, 24)
	agent_draw = GPU.SimpleDraw.new(rd, "agent_draw", draw_shader_file, draw_framebuffer, {0: draw_uniforms}, [draw_push])

func dispatch_physics(_delta: float, _current_ms: float, _flow_field_data: Dictionary, _nexus_data: Dictionary, _t_data: Dictionary):
	if active_count <= 0:
		pending_damages.clear()
		return

	var push = PackedByteArray()
	push.resize(112) # 104 bytes of data, padded to a 16-byte multiple for the push constant
	
	# Must match the allocated hash buffers (grid_counts/grid_cells sized for HASH_CELLS).
	# Hardcoding 256 here while buffers are 128² indexes out of bounds on taller/wider maps.
	var hw = HASH_WIDTH
	var hh = HASH_HEIGHT
	var hc = 32.0
	
	push.encode_u32(4, active_count)
	push.encode_float(8, _delta)
	push.encode_float(12, _current_ms)
	
	push.encode_float(16, _flow_field_data.get("offset_x", 0.0))
	push.encode_float(20, _flow_field_data.get("offset_y", 0.0))
	var c_size = _flow_field_data.get("cell_size", 32.0)
	push.encode_float(24, c_size)
	push.encode_float(28, 1.0 / max(0.001, c_size))
	
	push.encode_u32(32, hw)
	push.encode_u32(36, hh)
	push.encode_float(40, hc)
	push.encode_float(44, 1.0 / hc)
	
	push.encode_float(48, 12.0) # separation_multiplier (matches 12.0 radius)
	push.encode_float(52, 1.0)  # overlap_weight
	
	push.encode_float(56, _nexus_data.get("pos", Vector2.ZERO).x)
	push.encode_float(60, _nexus_data.get("pos", Vector2.ZERO).y)
	push.encode_float(64, _nexus_data.get("radius", 64.0))
	push.encode_u32(68, _nexus_data.get("valid", 1))
	
	# Per-type nexus damage (from EnemyDefinition.nexus_damage via set_enemy_type_data).
	for i in range(8):
		var dmg: int = _type_nexus_dmg[i] if i < _type_nexus_dmg.size() else 1
		push.encode_u32(72 + i * 4, dmg)

	# Nexus arrival box half-extents (world units) — agents arrive anywhere in the rect.
	var nex_ext: Vector2 = _nexus_data.get("extents", Vector2(10.0, 130.0))
	push.encode_float(104, nex_ext.x)
	push.encode_float(108, nex_ext.y)

	# Serialize pending AOE events into the damage_events buffer layout.
	# Header: event_count (u32) + 12 bytes pad. Each DamageEvent = 32 bytes.
	var event_count = min(pending_damages.size(), 1024)
	var dmg_bytes = PackedByteArray()
	dmg_bytes.resize(16 + event_count * 32)
	dmg_bytes.encode_u32(0, event_count)
	for i in range(event_count):
		var ev = pending_damages[i]
		var base = 16 + i * 32
		var ev_pos: Vector2 = ev.get("pos", Vector2.ZERO)
		dmg_bytes.encode_float(base + 0, ev_pos.x)
		dmg_bytes.encode_float(base + 4, ev_pos.y)
		dmg_bytes.encode_float(base + 8, ev.get("radius", 0.0))
		dmg_bytes.encode_float(base + 12, ev.get("damage", 0.0))
		dmg_bytes.encode_u32(base + 16, ev.get("effect_type", 0))
		dmg_bytes.encode_float(base + 20, ev.get("effect_value", 0.0))
		dmg_bytes.encode_u32(base + 24, 0)
		dmg_bytes.encode_u32(base + 28, 0)
	pending_damages.clear()

	RenderingServer.call_on_render_thread(func():
		if not compute_physics: return
		if damage_events_buffer_rid.is_valid():
			rd.buffer_update(damage_events_buffer_rid, 0, dmg_bytes.size(), dmg_bytes)
		var cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, compute_physics.pipeline)
		compute_physics.bind_uniform_sets(cl)
		
		# Passes: 0 clear-grid, 1 kinematics(move), 2 binning, 3 separation,
		# 4 apply-separation, 5 multimesh, 6 damage, 7 turret-targeting.
		var dispatch_pass := func(p: int):
			push.encode_u32(0, p)
			compute_physics.push_attributes[0].static_data = push
			compute_physics.update_push(cl)
			if p == 0:
				rd.compute_list_dispatch(cl, int(ceil(float(hw * hh) / 256.0)), 1, 1)
			elif p == 7:
				var t_count = turrets.size()
				if t_count > 0:
					rd.compute_list_dispatch(cl, int(ceil(float(t_count) / 256.0)), 1, 1)
			else:
				rd.compute_list_dispatch(cl, int(ceil(float(active_count) / 256.0)), 1, 1)
			rd.compute_list_add_barrier(cl)

		# Move once, then iterate {clear-grid, re-bin, separate, apply} so crowd
		# overlaps relax over several passes (orc-parity), then finalize.
		dispatch_pass.call(0) # clear grid
		dispatch_pass.call(1) # kinematics (move along flow)
		dispatch_pass.call(2) # binning
		dispatch_pass.call(3) # separation
		dispatch_pass.call(4) # apply separation
		for _it in range(SEPARATION_ITERATIONS - 1):
			dispatch_pass.call(0) # clear grid
			dispatch_pass.call(2) # re-bin updated positions
			dispatch_pass.call(3) # separation
			dispatch_pass.call(4) # apply separation
		dispatch_pass.call(5) # multimesh write
		dispatch_pass.call(6) # damage events
		dispatch_pass.call(7) # turret targeting
		
		rd.compute_list_end()
	)

func update_flow_field_textures(ff_tex: Texture2D, obs_tex: Texture2D, sdf_tex: Texture2D = null):
	if not ff_tex or not obs_tex: return

	# Extract image data outside render thread to avoid stalling
	var ff_img = ff_tex.get_image() if (ff_tex is ImageTexture) else null
	var obs_img = obs_tex.get_image() if (obs_tex is ImageTexture) else null
	var sdf_img = sdf_tex.get_image() if (sdf_tex is ImageTexture) else null

	RenderingServer.call_on_render_thread(func():
		if not compute_physics: return

		var ff_rd = RenderingServer.texture_get_rd_texture(ff_tex.get_rid())
		if not ff_rd.is_valid() and "texture_rd_rid" in ff_tex:
			ff_rd = ff_tex.texture_rd_rid

		var obs_rd = RenderingServer.texture_get_rd_texture(obs_tex.get_rid())
		if not obs_rd.is_valid() and "texture_rd_rid" in obs_tex:
			obs_rd = obs_tex.texture_rd_rid

		var sdf_rd = RID()
		if sdf_tex:
			sdf_rd = RenderingServer.texture_get_rd_texture(sdf_tex.get_rid())
			if not sdf_rd.is_valid() and "texture_rd_rid" in sdf_tex:
				sdf_rd = sdf_tex.texture_rd_rid

		if not ff_rd.is_valid() and ff_img != null:
			var tf = RDTextureFormat.new()
			# ff_img from CPU is FORMAT_RGBA8
			tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
			tf.width = ff_img.get_width()
			tf.height = ff_img.get_height()
			tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			if dummy_ff_rid.is_valid(): rd.free_rid(dummy_ff_rid)
			dummy_ff_rid = GPU.texture_create(rd, "ff_tex", tf, RDTextureView.new(), [ff_img.get_data()])
			ff_rd = dummy_ff_rid
			
		if not obs_rd.is_valid() and obs_img != null:
			var tf = RDTextureFormat.new()
			tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
			tf.width = obs_img.get_width()
			tf.height = obs_img.get_height()
			tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			if dummy_obs_rid.is_valid(): rd.free_rid(dummy_obs_rid)
			dummy_obs_rid = GPU.texture_create(rd, "obs_tex", tf, RDTextureView.new(), [obs_img.get_data()])
			obs_rd = dummy_obs_rid

		# Fine wall-SDF (FORMAT_RF → R32_SFLOAT). Build the RD texture once; the SDF
		# is static (map load), so reuse the cached rid on later frames.
		if not sdf_rd.is_valid() and sdf_img != null and not wall_sdf_rid.is_valid():
			var tf = RDTextureFormat.new()
			tf.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
			tf.width = sdf_img.get_width()
			tf.height = sdf_img.get_height()
			tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
			wall_sdf_rid = GPU.texture_create(rd, "wall_sdf_tex", tf, RDTextureView.new(), [sdf_img.get_data()])
		if not sdf_rd.is_valid() and wall_sdf_rid.is_valid():
			sdf_rd = wall_sdf_rid

		if ff_rd.is_valid() and obs_rd.is_valid():
			var sdf_rd_to_bind = sdf_rd if sdf_rd.is_valid() else obs_rd
			
			var new_uniforms = GPU.UniformsArray.new([
				GPU.create_storage_buffer_uniform(0, agent_buffer_rid),
				GPU.create_storage_buffer_uniform(1, grid_counts_rid),
				GPU.create_storage_buffer_uniform(2, grid_cells_rid),
				GPU.create_sampler_texture_uniform(3, linear_sampler_rid, ff_rd),
				GPU.create_sampler_texture_uniform(4, linear_sampler_rid, obs_rd),
				GPU.create_image_uniform(5, texture_rd_rid),
				GPU.create_storage_buffer_uniform(6, dead_enemies_buffer.data_buffer),
				GPU.create_storage_buffer_uniform(7, nexus_damage_buffer.buffer),
				GPU.create_storage_buffer_uniform(8, damage_events_buffer_rid),
				GPU.create_storage_buffer_uniform(9, turrets_buffer_rid),
				GPU.create_storage_buffer_uniform(10, turret_fire_events_buffer.data_buffer),
				GPU.create_storage_buffer_uniform(11, agent_buffer_rid_2),
				GPU.create_sampler_texture_uniform(12, linear_sampler_rid, sdf_rd_to_bind)
			])
			var old_set = compute_physics.uniform_sets.get(0, RID())
			if old_set.is_valid():
				rd.free_rid(old_set)
			compute_physics.uniform_sets[0] = rd.uniform_set_create(new_uniforms.array, compute_physics.shader, 0)
	)

# Free the physics uniform set, which binds the per-battle flow-field textures. battle.gd
# calls this from _exit_tree() on scene teardown, BEFORE the flow field frees those textures
# — otherwise freeing a bound texture auto-invalidates this set and the next free double-frees
# it ("Attempted to free invalid ID"). GPUSim is an autoload, so it must drop scene-scoped
# bindings itself; the next battle rebuilds the set on its first update_flow_field_textures.
func release_flow_bindings() -> void:
	if not rd or not compute_physics:
		return
	RenderingServer.call_on_render_thread(func():
		if not compute_physics:
			return
		var s = compute_physics.uniform_sets.get(0, RID())
		if s.is_valid():
			rd.free_rid(s)
		compute_physics.uniform_sets.erase(0)
	)

func draw_agents(camera_pos: Vector2, viewport_size: Vector2, zoom: float):
	RenderingServer.call_on_render_thread(func():
		var disp_bytes = PackedInt32Array([6, active_count, 0, 0]).to_byte_array()
		rd.buffer_update(dispatch_buffer, 0, 16, disp_bytes)
		
		var push = PackedByteArray()
		push.resize(24)
		push.encode_float(0, camera_pos.x)
		push.encode_float(4, camera_pos.y)
		push.encode_float(8, viewport_size.x)
		push.encode_float(12, viewport_size.y)
		push.encode_float(16, zoom)
		push.encode_u32(20, active_count)
		
		agent_draw.push_attributes[0].static_data = push
		agent_draw.draw_indirect(dispatch_buffer, 0)
	)
	
func spawn_enemy(pos: Vector2, type_index: int, type_speeds: Array, type_scales: Array, enemy_health: float, wave_scale: float = 1.0):
	if active_count >= MAX_AGENTS: return
	var idx = active_count
	var hp = int(enemy_health * wave_scale * 100.0)
	
	var bytes = PackedByteArray()
	bytes.resize(AGENT_STRUCT_SIZE)
	bytes.encode_float(0, pos.x)
	bytes.encode_float(4, pos.y)
	bytes.encode_float(8, 0.0)
	bytes.encode_float(12, 0.0)
	bytes.encode_s32(16, hp)
	bytes.encode_float(20, float(type_speeds[type_index]))
	bytes.encode_float(24, float(type_scales[type_index]))
	bytes.encode_u32(28, type_index)
	bytes.encode_float(32, 0.0)
	bytes.encode_s32(36, 0)
	bytes.encode_s32(40, 1000)
	
	RenderingServer.call_on_render_thread(func():
		if agent_buffer_rid.is_valid():
			rd.buffer_update(agent_buffer_rid, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
			rd.buffer_update(agent_buffer_rid_2, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
	)
	active_count += 1
	alive_count += 1

var turrets: Array = []
var turrets_by_id: Dictionary = {}
var next_turret_id: int = 1

func add_turret(t: Node2D):
	t.set_meta("internal_id", next_turret_id)
	turrets_by_id[next_turret_id] = t
	next_turret_id += 1
	t.set_meta("gpu_idx", turrets.size())
	turrets.append(t)
	_update_turret_count_on_gpu()
	update_turret(t, true)

func remove_turret(t: Node2D):
	var internal_id = t.get_meta("internal_id")
	if internal_id != null and turrets_by_id.has(internal_id):
		turrets_by_id.erase(internal_id)
	
	var gpu_idx = t.get_meta("gpu_idx")
	if gpu_idx != null and gpu_idx >= 0 and gpu_idx < turrets.size():
		var last_idx = turrets.size() - 1
		var last_t = turrets[last_idx]
		turrets[gpu_idx] = last_t
		last_t.set_meta("gpu_idx", gpu_idx)
		turrets.pop_back()
		t.set_meta("gpu_idx", -1)
		
		var new_size = turrets.size()
		RenderingServer.call_on_render_thread(func():
			if not turrets_buffer_rid.is_valid(): return
			if gpu_idx != last_idx:
				rd.buffer_copy(turrets_buffer_rid, turrets_buffer_rid, 16 + last_idx * 48, 16 + gpu_idx * 48, 48)
			rd.buffer_update(turrets_buffer_rid, 0, 4, PackedInt32Array([new_size]).to_byte_array())
		)

func _update_turret_count_on_gpu():
	var new_size = turrets.size()
	RenderingServer.call_on_render_thread(func():
		if turrets_buffer_rid.is_valid():
			rd.buffer_update(turrets_buffer_rid, 0, 4, PackedInt32Array([new_size]).to_byte_array())
	)

func update_turret(t: Node2D, is_new: bool = false):
	var gpu_idx = t.get_meta("gpu_idx")
	if gpu_idx == null or gpu_idx < 0: return
	
	var bytes = PackedByteArray()
	bytes.resize(48)
	bytes.encode_float(0, t.global_position.x)
	bytes.encode_float(4, t.global_position.y)
	bytes.encode_float(8, t.attack_range)
	bytes.encode_float(12, t.damage)
	bytes.encode_u32(16, t.target_mode)
	
	var t_type = 0
	if "turret_type" in t:
		if t.turret_type == "melee": t_type = 1
		elif t.turret_type == "slow": t_type = 2
	bytes.encode_u32(20, t_type)
	
	bytes.encode_float(24, t.fire_rate)
	bytes.encode_float(28, t.fire_rate)
	var internal_id = t.get_meta("internal_id") if t.has_meta("internal_id") else 0
	bytes.encode_u32(32, internal_id)
	
	RenderingServer.call_on_render_thread(func():
		if not turrets_buffer_rid.is_valid(): return
		if is_new:
			rd.buffer_update(turrets_buffer_rid, 16 + gpu_idx * 48, 48, bytes)
		else:
			rd.buffer_update(turrets_buffer_rid, 16 + gpu_idx * 48, 24, bytes.slice(0, 24))
			rd.buffer_update(turrets_buffer_rid, 16 + gpu_idx * 48 + 28, 20, bytes.slice(28, 48))
	)

var pending_damages: Array[Dictionary] = []

func apply_aoe_damage(pos: Vector2, radius: float, damage: float, bonus_if_slowed: bool = false):
	pending_damages.append({"pos": pos, "radius": radius, "damage": damage, "bonus_if_slowed": bonus_if_slowed})

func apply_aoe_slow(pos: Vector2, radius: float, slow_factor: float):
	pending_damages.append({
		"pos": pos,
		"radius": radius,
		"damage": 0.0,
		"effect_type": 1,
		"effect_value": slow_factor
	})

func apply_aoe_freeze(pos: Vector2, radius: float, duration: float):
	pending_damages.append({
		"pos": pos,
		"radius": radius,
		"damage": 0.0,
		"effect_type": 2,
		"effect_value": duration
	})

func get_agent_data_async(callback: Callable):
	RenderingServer.call_on_render_thread(func():
		if agent_buffer_rid.is_valid():
			var bytes = rd.buffer_get_data(agent_buffer_rid)
			var cur_active = active_count
			call_deferred("_parse_agent_data", bytes, cur_active, callback)
	)

func _parse_agent_data(bytes: PackedByteArray, count: int, callback: Callable):
	var positions_arr = PackedVector2Array()
	var healths_arr = PackedFloat32Array()
	positions_arr.resize(count)
	healths_arr.resize(count)
	for i in range(count):
		positions_arr[i] = Vector2(bytes.decode_float(i * AGENT_STRUCT_SIZE), bytes.decode_float(i * AGENT_STRUCT_SIZE + 4))
		healths_arr[i] = float(bytes.decode_s32(i * AGENT_STRUCT_SIZE + 16)) / 100.0
	callback.call(positions_arr, healths_arr)

func _exit_tree():
	GPU.sc_safe_free(compute_physics)
	GPU.sd_safe_free(agent_draw)
	# Free other manually managed RIDs
	GPU.rid_safe_free(rd, agent_buffer_rid)
	GPU.rid_safe_free(rd, agent_buffer_rid_2)
	GPU.rid_safe_free(rd, grid_counts_rid)
	GPU.rid_safe_free(rd, grid_cells_rid)
	GPU.rid_safe_free(rd, turrets_buffer_rid)
	GPU.rid_safe_free(rd, swap_buffer_rid)
	GPU.rid_safe_free(rd, damage_events_buffer_rid)
	GPU.rid_safe_free(rd, dummy_ff_rid)
	GPU.rid_safe_free(rd, dummy_obs_rid)
	GPU.rid_safe_free(rd, wall_sdf_rid)
	GPU.rid_safe_free(rd, texture_rd_rid)
	GPU.rid_safe_free(rd, draw_texture_rid)
	GPU.rid_safe_free(rd, dispatch_buffer)
	GPU.rid_safe_free(rd, draw_framebuffer)
	GPU.rid_safe_free(rd, linear_sampler_rid)
	if dead_enemies_buffer: dead_enemies_buffer.free_rids()
	if turret_fire_events_buffer: turret_fire_events_buffer.free_rids()
	
	# Clean up Int32 buffer manually if not handled
	if nexus_damage_buffer and nexus_damage_buffer.buffer.is_valid():
		GPU.rid_safe_free(rd, nexus_damage_buffer.buffer)
