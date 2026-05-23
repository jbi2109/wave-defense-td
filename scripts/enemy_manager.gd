extends Node2D
class_name EnemyManager

const EnemyDef = preload("res://scripts/enemy_definition.gd")

# --- Exports ---
@export var separation_radius_multiplier: float = 20.0
@export var overlap_weight: float = 0.4
@export var grid_cell_size: int = 72
@export var regenerate_flow_field_periodically: bool = true
@export var use_top_down_rotation: bool = false

var enemy_types: Array[Node] = []

@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var nexus: Node2D = get_node("../Nexus")

# CPU Buffers for UI & Targeting (Synced from GPU)
var active_count: int = 0
var active_boss_count: int = 0
var positions = PackedVector2Array()
var healths = PackedFloat32Array()
var max_healths = PackedFloat32Array()
var types = PackedInt32Array()
var gold_yields = PackedInt32Array()
var speed_modifiers = PackedFloat32Array()
var flash_amounts = PackedFloat32Array()

# Per-type caching
var type_scales = PackedFloat32Array()
var type_speeds = PackedFloat32Array()
var type_armors = PackedFloat32Array()
var type_nexus_dmg = PackedInt32Array()
var type_gold = PackedInt32Array()
var type_names = PackedStringArray()
var type_is_boss: Array[bool] = []
var type_is_flying: Array[bool] = []
var type_split_count = PackedInt32Array()
var type_split_type = PackedInt32Array()
var type_hframes = PackedInt32Array()

var multimeshes: Array[MultiMeshInstance2D] = []

# --- Rendering Device GPU State ---
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var agent_buffer_rid: RID
var grid_counts_rid: RID
var grid_cells_rid: RID
var speed_modifier_rid: RID
var linear_sampler_rid: RID
var dummy_ff_rid: RID
var dummy_obs_rid: RID
var bindings: Array[RDUniform] = []
var uniform_set: RID

# 50k max enemies
const MAX_AGENTS = 50000
const AGENT_STRUCT_SIZE = 32 # 8 floats

# Spatial Hash Params
const HASH_WIDTH = 128
const HASH_HEIGHT = 128
const HASH_CELLS = HASH_WIDTH * HASH_HEIGHT

var _nexus_valid: bool = false
var _nexus_rect: Rect2 = Rect2()
var last_flow_field_update: int = -99999

var agent_data_byte_array: PackedByteArray
var readback_mutex: Mutex = Mutex.new()
var gpu_readback_data: PackedByteArray = PackedByteArray()

# To handle damage events
var pending_damages: Array[Dictionary] = []

func _ready():
	# Collect EnemyDefinition children
	for child in get_children():
		if child.get_script() != null and "enemy_definition" in child.get_script().resource_path:
			enemy_types.append(child)

	if enemy_types.is_empty():
		var swarmer = EnemyDef.new()
		swarmer.enemy_name = "Swarmer"
		swarmer.texture_path = "res://assets/enemies/dino1.png"
		swarmer.hframes = 24
		swarmer.scale = 1.0
		swarmer.speed = 120.0
		swarmer.health = 10.0
		enemy_types.append(swarmer)
		add_child(swarmer)

	# Build per-type cache arrays
	var num_types = enemy_types.size()
	type_scales.resize(num_types)
	type_speeds.resize(num_types)
	type_armors.resize(num_types)
	type_nexus_dmg.resize(num_types)
	type_gold.resize(num_types)
	type_names.resize(num_types)
	type_is_boss.resize(num_types)
	type_is_flying.resize(num_types)
	type_split_count.resize(num_types)
	type_split_type.resize(num_types)
	type_hframes.resize(num_types)

	for i in range(num_types):
		var t = enemy_types[i]
		type_scales[i]    = t.scale
		type_speeds[i]    = t.speed
		type_armors[i]    = t.armor if "armor" in t else 0.0
		type_nexus_dmg[i] = t.nexus_damage if "nexus_damage" in t else 1
		type_gold[i]      = t.gold_yield if "gold_yield" in t else 5
		type_names[i]     = t.enemy_name if "enemy_name" in t else "Enemy"
		type_is_boss[i]   = t.is_boss if "is_boss" in t else false
		type_is_flying[i] = t.is_flying if "is_flying" in t else false
		type_split_count[i] = t.split_count if "split_count" in t else 0
		type_split_type[i]  = t.split_type_index if "split_type_index" in t else 0
		type_hframes[i]     = t.hframes if "hframes" in t else 1

		# Build MultiMesh per type
		var mmi = MultiMeshInstance2D.new()
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		mmi.multimesh.use_colors = true
		mmi.multimesh.use_custom_data = true
		mmi.multimesh.instance_count = 0
		mmi.multimesh.visible_instance_count = 0
		mmi.multimesh.mesh = QuadMesh.new()
		mmi.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		var raw_tex = load(t.texture_path)
		if raw_tex:
			mmi.texture = raw_tex
			var t_hframes = max(1, t.hframes)
			var frame_w = raw_tex.get_width() / t_hframes
			var frame_h = raw_tex.get_height()
			mmi.multimesh.mesh.size = Vector2(frame_w, frame_h)
			
			var shader = Shader.new()
			shader.code = "shader_type canvas_item;
uniform int hframes = 24;
varying vec4 custom_data;
void vertex() {
	int frame = int(floor(INSTANCE_CUSTOM.x)) % hframes;
	if (frame < 0) {
		frame += hframes;
	}
	UV.x = (UV.x + float(frame)) / float(hframes);
	custom_data = INSTANCE_CUSTOM;
}
void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	vec3 flash_color = vec3(1.0, 1.0, 1.0);
	COLOR = vec4(mix(tex_color.rgb, flash_color, custom_data.y * 0.6), tex_color.a) * COLOR;
}
"
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("hframes", t_hframes)
			mmi.material = mat
		else:
			mmi.multimesh.mesh.size = Vector2(24, 24)

		add_child(mmi)
		multimeshes.append(mmi)


	positions.resize(MAX_AGENTS)
	healths.resize(MAX_AGENTS)
	max_healths.resize(MAX_AGENTS)
	types.resize(MAX_AGENTS)
	gold_yields.resize(MAX_AGENTS)
	speed_modifiers.resize(MAX_AGENTS)
	flash_amounts.resize(MAX_AGENTS)
	flash_amounts.fill(0.0)

	_init_gpu()

func _init_gpu():
	rd = RenderingServer.get_rendering_device()
	
	# Load shader
	var shader_file = load("res://scripts/compute_physics.glsl")
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)
	
	# Create buffers
	agent_data_byte_array = PackedByteArray()
	agent_data_byte_array.resize(MAX_AGENTS * AGENT_STRUCT_SIZE)
	agent_data_byte_array.fill(0)
	agent_buffer_rid = rd.storage_buffer_create(agent_data_byte_array.size(), agent_data_byte_array)
	
	var grid_counts_bytes = PackedByteArray()
	grid_counts_bytes.resize(HASH_CELLS * 4) # uint
	grid_counts_bytes.fill(0)
	grid_counts_rid = rd.storage_buffer_create(grid_counts_bytes.size(), grid_counts_bytes)
	
	var grid_cells_bytes = PackedByteArray()
	grid_cells_bytes.resize(HASH_CELLS * 32 * 4) # uint * 32 per cell
	grid_cells_bytes.fill(0)
	grid_cells_rid = rd.storage_buffer_create(grid_cells_bytes.size(), grid_cells_bytes)
	
	var speed_modifier_bytes = PackedByteArray()
	speed_modifier_bytes.resize(MAX_AGENTS * 4) # 4 bytes per float
	speed_modifier_bytes.fill(0)
	speed_modifier_rid = rd.storage_buffer_create(speed_modifier_bytes.size(), speed_modifier_bytes)
	
	linear_sampler_rid = rd.sampler_create(RDSamplerState.new())
	
	var dummy_ff = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	dummy_ff_rid = RenderingServer.texture_get_rd_texture(dummy_ff.get_rid())
	
	var dummy_obs = ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_L8))
	dummy_obs_rid = RenderingServer.texture_get_rd_texture(dummy_obs.get_rid())

func _update_bindings():
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		
	bindings.clear()
	
	var u_agent = RDUniform.new()
	u_agent.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_agent.binding = 0
	u_agent.add_id(agent_buffer_rid)
	bindings.append(u_agent)
	
	var u_counts = RDUniform.new()
	u_counts.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_counts.binding = 1
	u_counts.add_id(grid_counts_rid)
	bindings.append(u_counts)
	
	var u_cells = RDUniform.new()
	u_cells.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_cells.binding = 2
	u_cells.add_id(grid_cells_rid)
	bindings.append(u_cells)
	
	var u_ff = RDUniform.new()
	u_ff.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_ff.binding = 3
	u_ff.add_id(linear_sampler_rid) # Sampler first
	if flow_field.ff_texture and flow_field.ff_texture.get_rid().is_valid():
		u_ff.add_id(RenderingServer.texture_get_rd_texture(flow_field.ff_texture.get_rid())) # Texture second
	else:
		u_ff.add_id(dummy_ff_rid)
	bindings.append(u_ff)
	
	var u_obs = RDUniform.new()
	u_obs.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_obs.binding = 4
	u_obs.add_id(linear_sampler_rid) # Sampler first
	if flow_field.obs_texture and flow_field.obs_texture.get_rid().is_valid():
		u_obs.add_id(RenderingServer.texture_get_rd_texture(flow_field.obs_texture.get_rid())) # Texture second
	else:
		u_obs.add_id(dummy_obs_rid)
	bindings.append(u_obs)
	
	var u_speed = RDUniform.new()
	u_speed.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_speed.binding = 5
	u_speed.add_id(speed_modifier_rid)
	bindings.append(u_speed)
	
	uniform_set = rd.uniform_set_create(bindings, shader_rid, 0)

func spawn_enemy(pos: Vector2, type_index: int = 0):
	if active_count >= MAX_AGENTS: return
	
	var idx = active_count
	positions[idx] = pos
	var starting_hp = enemy_types[type_index].health
	healths[idx] = starting_hp
	max_healths[idx] = starting_hp
	types[idx] = type_index
	gold_yields[idx] = type_gold[type_index]
	speed_modifiers[idx] = 1.0
	flash_amounts[idx] = 0.0
	
	var bytes = PackedByteArray()
	bytes.resize(AGENT_STRUCT_SIZE)
	bytes.encode_float(0, pos.x)
	bytes.encode_float(4, pos.y)
	bytes.encode_float(8, 0.0) # vel.x
	bytes.encode_float(12, 0.0) # vel.y
	bytes.encode_float(16, enemy_types[type_index].health) # health
	bytes.encode_float(20, type_speeds[type_index]) # max_speed
	bytes.encode_float(24, type_scales[type_index]) # scale
	bytes.encode_u32(28, type_index) # type
	
	rd.buffer_update(agent_buffer_rid, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
	
	# Instantly sync CPU shadow buffer so next frame's _tick_cpu_logic doesn't read garbage/0.0
	if agent_data_byte_array.size() < (idx + 1) * AGENT_STRUCT_SIZE:
		agent_data_byte_array.resize((idx + 1) * AGENT_STRUCT_SIZE)
	for i in range(AGENT_STRUCT_SIZE):
		agent_data_byte_array[idx * AGENT_STRUCT_SIZE + i] = bytes[i]
	
	if type_is_boss[type_index]:
		active_boss_count += 1
	
	active_count += 1

func _physics_process(delta):
	if not flow_field: return

	var current_ms = Time.get_ticks_msec()
	
	_cache_nexus()
	_maybe_regen_flow_field(current_ms)
	
	if active_count == 0: return

	# 1. Thread-safe readback copy from the render thread's previous frame execution
	readback_mutex.lock()
	var temp_data = gpu_readback_data
	readback_mutex.unlock()
	
	var target_size = active_count * AGENT_STRUCT_SIZE
	if temp_data.size() >= target_size:
		agent_data_byte_array = temp_data.slice(0, target_size)
	elif temp_data.size() > 0:
		var spawns_data = agent_data_byte_array.slice(temp_data.size(), target_size)
		agent_data_byte_array = temp_data + spawns_data
	
	# 2. Run CPU logic (detect deaths, move, update arrays)
	_tick_cpu_logic(delta)
	
	if active_count == 0: return

	# 3. Setup push constants for compute shader
	var push_bytes = PackedByteArray()
	push_bytes.resize(80) # Match GLSL std430 struct exactly (80 bytes total for push constant)
	push_bytes.fill(0)
	
	# offset 4: active_count
	push_bytes.encode_u32(4, active_count)
	# offset 8: delta
	push_bytes.encode_float(8, delta)
	# offset 12: time_msec
	push_bytes.encode_float(12, float(current_ms))
	
	# offset 16: grid_offset (vec2)
	push_bytes.encode_float(16, float(flow_field.grid_offset.x))
	push_bytes.encode_float(20, float(flow_field.grid_offset.y))
	# offset 24: cell_size
	push_bytes.encode_float(24, float(flow_field.cell_size))
	push_bytes.encode_float(28, 1.0 / float(flow_field.cell_size))
	
	# offset 32: hash grid
	push_bytes.encode_u32(32, HASH_WIDTH)
	push_bytes.encode_u32(36, HASH_HEIGHT)
	push_bytes.encode_float(40, float(grid_cell_size))
	push_bytes.encode_float(44, 1.0 / float(grid_cell_size))
	
	# offset 48: separation params
	push_bytes.encode_float(48, separation_radius_multiplier)
	push_bytes.encode_float(52, overlap_weight)
	
	# 4. Dispatch compute shader on the render thread and bind active_count for safe readback
	RenderingServer.call_on_render_thread(self._dispatch_compute.bind(push_bytes, active_count))

func _dispatch_compute(push_bytes: PackedByteArray, current_active_count: int):
	if not flow_field.ff_texture or not flow_field.ff_texture.get_rid().is_valid(): return
	
	_update_bindings()
	if not uniform_set.is_valid(): return
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var groups = max(1, int(ceil(float(current_active_count) / 256.0)))
	var grid_groups = max(1, int(ceil(float(HASH_CELLS) / 256.0)))
	
	# Pass 0: Clear Grid
	push_bytes.encode_u32(0, 0) # pass_idx
	rd.compute_list_set_push_constant(compute_list, push_bytes, 80)
	rd.compute_list_dispatch(compute_list, grid_groups, 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 1: Binning
	push_bytes.encode_u32(0, 1)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 80)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 2: Separation & MultiMesh
	push_bytes.encode_u32(0, 2)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 80)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	
	# Handle Damage Events
	for dmg in pending_damages:
		rd.compute_list_add_barrier(compute_list)
		push_bytes.encode_u32(0, 3) # pass_idx = 3
		push_bytes.encode_float(56, dmg.pos.x)
		push_bytes.encode_float(60, dmg.pos.y)
		push_bytes.encode_float(64, dmg.radius)
		push_bytes.encode_float(68, dmg.damage)
		rd.compute_list_set_push_constant(compute_list, push_bytes, 80)
		rd.compute_list_dispatch(compute_list, groups, 1, 1)
		
	pending_damages.clear()
	
	rd.compute_list_end()

	# Safe readback on the render thread, synced via mutex
	if current_active_count > 0:
		var fetched_data = rd.buffer_get_data(agent_buffer_rid, 0, current_active_count * AGENT_STRUCT_SIZE)
		readback_mutex.lock()
		gpu_readback_data = fetched_data
		readback_mutex.unlock()
	
func _tick_cpu_logic(delta: float):
	var to_remove = []
	for i in range(active_count):
		# Apply decay to speed modifiers and flash amounts
		speed_modifiers[i] = move_toward(speed_modifiers[i], 1.0, delta * 0.4)
		if flash_amounts[i] > 0.0:
			flash_amounts[i] -= delta * 16.0
			if flash_amounts[i] < 0.0:
				flash_amounts[i] = 0.0
		
		var px = agent_data_byte_array.decode_float(i * AGENT_STRUCT_SIZE + 0)
		var py = agent_data_byte_array.decode_float(i * AGENT_STRUCT_SIZE + 4)
		var hp = agent_data_byte_array.decode_float(i * AGENT_STRUCT_SIZE + 16)
		
		if is_nan(px) or is_inf(px) or is_nan(py) or is_inf(py):
			px = 0.0
			py = 0.0
		if is_nan(hp) or is_inf(hp):
			hp = 0.0
		
		positions[i] = Vector2(px, py)
		healths[i] = hp
		
		if hp <= 0.0:
			to_remove.append(i)
		elif _nexus_valid and _nexus_rect.has_point(positions[i]):
			GlobalEvents.nexus_damaged.emit(type_nexus_dmg[types[i]])
			to_remove.append(i)
			
	if not to_remove.is_empty():
		to_remove.sort()
		to_remove.reverse()
		for idx in to_remove:
			_remove_enemy(idx)
			
	if active_count > 0:
		rd.buffer_update(speed_modifier_rid, 0, active_count * 4, speed_modifiers.slice(0, active_count).to_byte_array())
		
	# Update multimesh buffers on CPU
	var num_types = enemy_types.size()
	var type_counts = PackedInt32Array()
	type_counts.resize(num_types)
	type_counts.fill(0)
	
	for i in range(active_count):
		var type = types[i]
		if type >= 0 and type < num_types:
			type_counts[type] += 1
			
	var type_buffers = []
	type_buffers.resize(num_types)
	var write_indices = PackedInt32Array()
	write_indices.resize(num_types)
	write_indices.fill(0)
	for t in range(num_types):
		var arr = PackedFloat32Array()
		arr.resize(type_counts[t] * 16)
		type_buffers[t] = arr
		
	var time_ms = Time.get_ticks_msec()
	for i in range(active_count):
		var px = positions[i].x
		var py = positions[i].y
		
		var vx = agent_data_byte_array.decode_float(i * AGENT_STRUCT_SIZE + 8)
		var vy = agent_data_byte_array.decode_float(i * AGENT_STRUCT_SIZE + 12)
		if is_nan(vx) or is_inf(vx) or is_nan(vy) or is_inf(vy):
			vx = 0.0
			vy = 0.0
		var base_scale = type_scales[types[i]]
		var type = types[i]
		
		if type < 0 or type >= num_types:
			continue
			
		var w_idx = write_indices[type]
		var offset = w_idx * 16
		write_indices[type] += 1
		
		var arr = type_buffers[type]
		
		# Flip horizontal based on vel.x
		var sx = base_scale
		if vx < 0.0:
			sx = -base_scale
		var sy = -base_scale
		
		# Row 0: x.x, y.x, pad, pos.x
		arr[offset + 0] = sx
		arr[offset + 1] = 0.0
		arr[offset + 2] = 0.0
		arr[offset + 3] = px
		
		# Row 1: x.y, y.y, pad, pos.y
		arr[offset + 4] = 0.0
		arr[offset + 5] = sy
		arr[offset + 6] = 0.0
		arr[offset + 7] = py
		
		# Color: R, G, B, A
		arr[offset + 8] = 1.0
		arr[offset + 9] = 1.0
		arr[offset + 10] = 1.0
		arr[offset + 11] = 1.0
		
		# Custom: frame_idx, flash_amount, 0, 0
		var frame_idx = 0.0
		var speed_sq = vx*vx + vy*vy
		if speed_sq > 22500.0: # speed > 150.0 (e.g. Runners)
			# Sprint/Dash animation: frames 10 to 14 (5 frames total)
			var cycle_time = time_ms * 0.015 + float(i) * 3.0
			frame_idx = 10.0 + fmod(cycle_time, 5.0)
		elif speed_sq > 100.0: # speed > 10.0
			# Walk animation: frames 4 to 9 (6 frames total)
			var cycle_time = time_ms * 0.012 + float(i) * 3.0
			frame_idx = 4.0 + fmod(cycle_time, 6.0)
		else:
			# Idle animation: frames 0 to 3 (4 frames total)
			var cycle_time = time_ms * 0.006 + float(i) * 2.0
			frame_idx = fmod(cycle_time, 4.0)
		arr[offset + 12] = frame_idx
		arr[offset + 13] = flash_amounts[i]
		arr[offset + 14] = 0.0
		arr[offset + 15] = 0.0

	for t in range(num_types):
		var mmi = multimeshes[t]
		mmi.multimesh.instance_count = type_counts[t]
		if type_counts[t] > 0:
			mmi.multimesh.set_buffer(type_buffers[t])
		mmi.multimesh.visible_instance_count = type_counts[t]

func damage_enemy(index: int, amount: float):
	if index >= 0 and index < active_count:
		var armor = type_armors[types[index]]
		var net_damage = maxf(0.0, amount * (1.0 - armor))
		var current_hp = healths[index] - net_damage
		healths[index] = current_hp
		
		var bytes = PackedByteArray()
		bytes.resize(4)
		bytes.encode_float(0, current_hp)
		rd.buffer_update(agent_buffer_rid, index * AGENT_STRUCT_SIZE + 16, 4, bytes)
		
		if net_damage > 0.0:
			flash_amounts[index] = 1.0
			SoundManager.play_sfx("hit")
			if DamageTextManager.instance:
				DamageTextManager.instance.spawn_damage_text(positions[index], net_damage, false)

func apply_aoe_damage(pos: Vector2, radius: float, damage: float):
	pending_damages.append({"pos": pos, "radius": radius, "damage": damage})

func get_nearby_enemies(world_pos: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var rsq = radius * radius
	for i in range(active_count):
		if positions[i].distance_squared_to(world_pos) <= rsq:
			results.append(i)
	return results

func _remove_enemy(index: int):
	active_count -= 1
	var old_last_idx = active_count
	
	var turrets = get_tree().get_nodes_in_group("turret")
	for t in turrets:
		if t.target_idx == index:
			t.target_idx = -1
		elif t.target_idx == old_last_idx:
			t.target_idx = index
			
	if type_is_boss[types[index]]:
		active_boss_count -= 1
			
	if index < active_count:
		var start_byte = active_count * AGENT_STRUCT_SIZE
		var dest_byte = index * AGENT_STRUCT_SIZE
		var last_bytes = agent_data_byte_array.slice(start_byte, start_byte + AGENT_STRUCT_SIZE)
		
		for i in range(AGENT_STRUCT_SIZE):
			agent_data_byte_array[dest_byte + i] = last_bytes[i]
			
		rd.buffer_update(agent_buffer_rid, dest_byte, AGENT_STRUCT_SIZE, last_bytes)
		
		positions[index] = positions[active_count]
		healths[index] = healths[active_count]
		max_healths[index] = max_healths[active_count]
		types[index] = types[active_count]
		gold_yields[index] = gold_yields[active_count]
		speed_modifiers[index] = speed_modifiers[active_count]
		flash_amounts[index] = flash_amounts[active_count]
		
	var dead_bytes = PackedByteArray()
	dead_bytes.resize(4)
	dead_bytes.encode_float(0, -1.0)
	rd.buffer_update(agent_buffer_rid, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)

func _cache_nexus():
	_nexus_valid = is_instance_valid(nexus)
	if _nexus_valid and "extents" in nexus:
		_nexus_rect = Rect2(nexus.global_position - nexus.extents, nexus.extents * 2.0)
	elif _nexus_valid:
		_nexus_rect = Rect2(nexus.global_position - Vector2(32, 32), Vector2(64, 64))

func _maybe_regen_flow_field(current_ms: int):
	if not regenerate_flow_field_periodically: return
	if active_count == 0: return
	
	var interval = 1500
	if current_ms - last_flow_field_update < interval: return
	if not _nexus_valid: return
	last_flow_field_update = current_ms
	
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
