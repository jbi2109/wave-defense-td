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
@onready var wave_manager: WaveManager = get_node("../WaveManager")

# CPU Buffers for UI & Targeting (Synced from GPU)
var active_count: int = 0
var active_boss_count: int = 0
var positions = PackedVector2Array()
var healths = PackedInt32Array()
var max_healths = PackedInt32Array()
var types = PackedInt32Array()
var gold_yields = PackedInt32Array()
var speed_modifiers = PackedInt32Array()
var flash_amounts = PackedInt32Array()
var freeze_timers = PackedFloat32Array()

const CPU_CELL_SIZE = 128.0
var grid_cells_cpu: Dictionary = {}

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
var linear_sampler_rid: RID
var dummy_ff_rid: RID
var dummy_obs_rid: RID
var dummy_ff_tex: ImageTexture
var dummy_obs_tex: ImageTexture
var bindings: Array[RDUniform] = []
var uniform_set: RID
var uniform_set_b: RID
var agent_buffer_rid_2: RID
var texture_rd_rid: RID
var agent_data_tex: Texture2DRD
var _bindings_dirty: bool = true
var _last_ff_rid: RID

var dead_enemies_buffer: GPUHelpers.ReadbackBuffer
var nexus_damage_buffer: GPUHelpers.ReadbackBufferInt32
var damage_events_buffer_rid: RID

# 150k max enemies
const MAX_AGENTS = 150000
const AGENT_STRUCT_SIZE = 48 # 12 floats = 48 bytes

# Spatial Hash Params
const HASH_WIDTH = 128
const HASH_HEIGHT = 128
const HASH_CELLS = HASH_WIDTH * HASH_HEIGHT

var _nexus_valid: bool = false
var _nexus_rect: Rect2 = Rect2()
var last_flow_field_update: int = -99999

var turrets: Array[Turret] = []
var turrets_by_id: Dictionary = {}
var next_turret_id: int = 1
var agent_data_byte_array: PackedByteArray

var turrets_buffer_rid: RID
var turrets_byte_array: PackedByteArray
var swap_buffer_rid: RID

var turret_fire_events_buffer: GPUHelpers.ReadbackBuffer


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
		mmi.multimesh.use_colors = false
		mmi.multimesh.use_custom_data = false
		mmi.multimesh.instance_count = MAX_AGENTS
		
		var init_transforms = PackedFloat32Array()
		init_transforms.resize(MAX_AGENTS * 8)
		for idx in range(MAX_AGENTS):
			var base = idx * 8
			init_transforms[base + 0] = 1.0
			init_transforms[base + 5] = 1.0
		mmi.multimesh.buffer = init_transforms
		
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
uniform int target_type = 0;
uniform sampler2D agent_data_tex;
varying float v_flash;

void vertex() {
	int tex_x = INSTANCE_ID % 512;
	int tex_y = INSTANCE_ID / 512;
	vec4 data = texelFetch(agent_data_tex, ivec2(tex_x, tex_y), 0);
	
	vec2 pos = data.xy;
	float scale = data.z;
	float type_and_frame = data.w;
	
	float val = type_and_frame + 0.00001;
	int type = int(floor(val));
	float remainder = (val - float(type)) * 100.0;
	int frame = int(floor(remainder + 0.001));
	float flash = (remainder - float(frame)) * 100.0;
	if (flash < 0.15) {
		flash = 0.0;
	}
	
	if (type != target_type) {
		VERTEX = vec2(0.0, 0.0);
	} else {
		VERTEX.y = -VERTEX.y;
		VERTEX = VERTEX * abs(scale);
		if (scale < 0.0) {
			VERTEX.x = -VERTEX.x;
		}
		VERTEX += pos;
		
		if (frame < 0) {
			frame += hframes;
		}
		UV.x = (UV.x + float(frame)) / float(hframes);
	}
	v_flash = flash;
}
void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(mix(tex_color.rgb, vec3(1.0), v_flash * 0.6), tex_color.a);
}
"
			var mat = ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("hframes", t_hframes)
			mat.set_shader_parameter("target_type", i)
			mmi.material = mat
		else:
			mmi.multimesh.mesh.size = Vector2(24, 24)

		add_child(mmi)
		RenderingServer.canvas_item_set_custom_rect(mmi.get_canvas_item(), true, Rect2(-10000, -10000, 20000, 20000))
		multimeshes.append(mmi)


	positions.resize(MAX_AGENTS)
	healths.resize(MAX_AGENTS)
	max_healths.resize(MAX_AGENTS)
	types.resize(MAX_AGENTS)
	gold_yields.resize(MAX_AGENTS)
	speed_modifiers.resize(MAX_AGENTS)
	flash_amounts.resize(MAX_AGENTS)
	flash_amounts.fill(0)
	freeze_timers.resize(MAX_AGENTS)
	freeze_timers.fill(0.0)

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
	agent_buffer_rid_2 = rd.storage_buffer_create(agent_data_byte_array.size(), agent_data_byte_array)
	
	turrets_byte_array = PackedByteArray()
	turrets_byte_array.resize(48 * 1024) # Up to 1024 turrets (48 bytes each for alignment)
	turrets_byte_array.fill(0)
	turrets_buffer_rid = rd.storage_buffer_create(turrets_byte_array.size(), turrets_byte_array)
	
	var swap_bytes = PackedByteArray()
	swap_bytes.resize(AGENT_STRUCT_SIZE)
	swap_buffer_rid = rd.storage_buffer_create(swap_bytes.size(), swap_bytes)

	
	var grid_counts_bytes = PackedByteArray()
	grid_counts_bytes.resize(HASH_CELLS * 4) # uint
	grid_counts_bytes.fill(0)
	grid_counts_rid = rd.storage_buffer_create(grid_counts_bytes.size(), grid_counts_bytes)
	
	var grid_cells_bytes = PackedByteArray()
	grid_cells_bytes.resize(HASH_CELLS * 32 * 4) # uint * 32 per cell
	grid_cells_bytes.fill(0)
	grid_cells_rid = rd.storage_buffer_create(grid_cells_bytes.size(), grid_cells_bytes)
	
	linear_sampler_rid = rd.sampler_create(RDSamplerState.new())
	
	var dummy_ff_img = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var dummy_ff_tf = RDTextureFormat.new()
	dummy_ff_tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	dummy_ff_tf.width = 1
	dummy_ff_tf.height = 1
	dummy_ff_tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	dummy_ff_rid = rd.texture_create(dummy_ff_tf, RDTextureView.new(), [dummy_ff_img.get_data()])
	
	var dummy_obs_img = Image.create(1, 1, false, Image.FORMAT_L8)
	var dummy_obs_tf = RDTextureFormat.new()
	dummy_obs_tf.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	dummy_obs_tf.width = 1
	dummy_obs_tf.height = 1
	dummy_obs_tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	dummy_obs_rid = rd.texture_create(dummy_obs_tf, RDTextureView.new(), [dummy_obs_img.get_data()])

	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = 512
	tf.height = 512
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	texture_rd_rid = rd.texture_create(tf, RDTextureView.new(), [])
	agent_data_tex = Texture2DRD.new()
	agent_data_tex.texture_rd_rid = texture_rd_rid
	
	for mmi in multimeshes:
		if mmi.material:
			mmi.material.set_shader_parameter("agent_data_tex", agent_data_tex)

	dead_enemies_buffer = GPUHelpers.ReadbackBuffer.new(rd, "dead_enemies", 2, 4096, 16, 16)
	turret_fire_events_buffer = GPUHelpers.ReadbackBuffer.new(rd, "turret_fire_events", 2, 4096, 16, 16)
	nexus_damage_buffer = GPUHelpers.ReadbackBufferInt32.new(rd, "nexus_damage")
	
	var dmg_bytes = PackedByteArray()
	dmg_bytes.resize(16 + 1024 * 32)
	damage_events_buffer_rid = rd.storage_buffer_create(dmg_bytes.size(), dmg_bytes)

func _update_bindings():
	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
	if uniform_set_b.is_valid():
		rd.free_rid(uniform_set_b)
		
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
	if flow_field.flow_result_tex.is_valid():
		u_ff.add_id(flow_field.flow_result_tex) # Texture second
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
	
	var u_agent_tex = RDUniform.new()
	u_agent_tex.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_agent_tex.binding = 5
	u_agent_tex.add_id(texture_rd_rid)
	bindings.append(u_agent_tex)
	
	var u_dead = RDUniform.new()
	u_dead.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_dead.binding = 6
	u_dead.add_id(dead_enemies_buffer.data_buffer)
	bindings.append(u_dead)
	
	var u_nexus_dmg = RDUniform.new()
	u_nexus_dmg.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_nexus_dmg.binding = 7
	u_nexus_dmg.add_id(nexus_damage_buffer.buffer)
	bindings.append(u_nexus_dmg)
	
	var u_dmg = RDUniform.new()
	u_dmg.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_dmg.binding = 8
	u_dmg.add_id(damage_events_buffer_rid)
	bindings.append(u_dmg)
	
	var u_turrets = RDUniform.new()
	u_turrets.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_turrets.binding = 9
	u_turrets.add_id(turrets_buffer_rid)
	bindings.append(u_turrets)
 
	var u_fires = RDUniform.new()
	u_fires.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_fires.binding = 10
	u_fires.add_id(turret_fire_events_buffer.data_buffer)
	bindings.append(u_fires)
	
	var u_agent2 = RDUniform.new()
	u_agent2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_agent2.binding = 11
	u_agent2.add_id(agent_buffer_rid_2)
	bindings.append(u_agent2)
	uniform_set = rd.uniform_set_create(bindings, shader_rid, 0)
	
	var bindings_b = bindings.duplicate()
	bindings_b[0] = RDUniform.new()
	bindings_b[0].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	bindings_b[0].binding = 0
	bindings_b[0].add_id(agent_buffer_rid_2)
	bindings_b[11] = RDUniform.new()
	bindings_b[11].uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	bindings_b[11].binding = 11
	bindings_b[11].add_id(agent_buffer_rid)
	uniform_set_b = rd.uniform_set_create(bindings_b, shader_rid, 0)

func spawn_enemy(pos: Vector2, type_index: int = 0):
	if active_count >= MAX_AGENTS: return
	
	var idx = active_count
	positions[idx] = pos
	
	# Dynamic size/scale using power-law random factor matching Studio Game
	var rf = randf()
	var scale_mult = 1.0 + 1.0 * pow(rf, 10.0)
	var dynamic_scale = type_scales[type_index] * scale_mult
	
	# Relative wave spawning progress
	var relative_time = 0.0
	if is_instance_valid(wave_manager):
		relative_time = float(wave_manager.enemies_spawned) / float(max(1, wave_manager.enemies_to_spawn))
		
	# Exponential level difficulty scaling
	var level_idx = 2 if Globals.selected_map == "map2" else 1
	var level_factor = pow(2.5, level_idx - 1)
	
	# Health scales quadratically with scale factor, linearly with wave progress, exponentially with level
	var size_factor = scale_mult * scale_mult
	var time_factor = 1.0 + relative_time * 1.0
	var starting_hp = enemy_types[type_index].health * size_factor * time_factor * level_factor
	
	healths[idx] = starting_hp
	max_healths[idx] = starting_hp
	types[idx] = type_index
	gold_yields[idx] = type_gold[type_index]
	speed_modifiers[idx] = 1000
	flash_amounts[idx] = 0
	
	var bytes = PackedByteArray()
	bytes.resize(AGENT_STRUCT_SIZE)
	bytes.encode_float(0, pos.x)
	bytes.encode_float(4, pos.y)
	bytes.encode_float(8, 0.0) # vel.x
	bytes.encode_float(12, 0.0) # vel.y
	bytes.encode_s32(16, int(starting_hp * 100.0)) # health
	bytes.encode_float(20, type_speeds[type_index]) # max_speed
	bytes.encode_float(24, dynamic_scale) # scale
	bytes.encode_u32(28, type_index) # type
	bytes.encode_float(32, 0.0) # freeze_timer
	bytes.encode_s32(36, 0) # flash_amount
	bytes.encode_s32(40, 1000) # speed_modifier
	
	RenderingServer.call_on_render_thread(func():
		if agent_buffer_rid.is_valid():
			rd.buffer_update(agent_buffer_rid, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
			rd.buffer_update(agent_buffer_rid_2, idx * AGENT_STRUCT_SIZE, AGENT_STRUCT_SIZE, bytes)
	)
	
	if type_is_boss[type_index]:
		active_boss_count += 1
	
	active_count += 1

func _process(delta):
	if not flow_field: return

	var current_ms = Time.get_ticks_msec()
	
	_cache_nexus()
	_ensure_flow_field_initialized()
	
	if flow_field.flow_result_tex.is_valid() and flow_field.flow_result_tex != _last_ff_rid:
		_bindings_dirty = true
		_last_ff_rid = flow_field.flow_result_tex
	
	if active_count == 0: return
	
	# 1. Run CPU logic (detect deaths, move, update arrays)
	_tick_cpu_logic(delta)
	

	if active_count == 0: return

	# 3. Setup push constants for compute shader
	var push_bytes = PackedByteArray()
	push_bytes.resize(112) # 80 + 32 for nexus
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
	
	# offset 72: nexus
	if _nexus_valid:
		push_bytes.encode_float(72, nexus.global_position.x)
		push_bytes.encode_float(76, nexus.global_position.y)
		var n_rad = 32.0
		if "extents" in nexus:
			n_rad = maxf(nexus.extents.x, nexus.extents.y)
		push_bytes.encode_float(80, n_rad)
		push_bytes.encode_u32(84, 1)
	
	for i in range(min(6, enemy_types.size())):
		push_bytes.encode_u32(88 + i * 4, type_nexus_dmg[i])
		
	# Batch damage events
	var dmg_bytes = PackedByteArray()
	if not pending_damages.is_empty():
		var event_count = min(pending_damages.size(), 1024)
		dmg_bytes.resize(16 + event_count * 32)
		dmg_bytes.encode_u32(0, event_count)
		for i in range(event_count):
			var ev = pending_damages[i]
			var offset = 16 + i * 32
			dmg_bytes.encode_float(offset, ev.pos.x)
			dmg_bytes.encode_float(offset + 4, ev.pos.y)
			dmg_bytes.encode_float(offset + 8, ev.radius)
			dmg_bytes.encode_float(offset + 12, ev.damage)
			dmg_bytes.encode_u32(offset + 16, ev.get("effect_type", 0))
			dmg_bytes.encode_float(offset + 20, ev.get("effect_value", 0.0))
			dmg_bytes.encode_u32(offset + 24, 0)
			dmg_bytes.encode_u32(offset + 28, 0)
		pending_damages.clear()
	else:
		dmg_bytes.resize(16)
		dmg_bytes.encode_u32(0, 0)
	var turret_rotations = PackedFloat32Array()
	turret_rotations.resize(turrets.size())
	for i in range(turrets.size()):
		var t = turrets[i]
		var rot_val = 0.0
		if is_instance_valid(t):
			if t.has_node("GunSprite"):
				rot_val = t.get_node("GunSprite").rotation
			else:
				rot_val = t.rotation
		turret_rotations[i] = rot_val

	RenderingServer.call_on_render_thread(func():
		if turrets_buffer_rid.is_valid():
			for i in range(turret_rotations.size()):
				var angle_offset = 16 + i * 48 + 36 # offset of padding0 in bytes
				var angle_bytes = PackedFloat32Array([turret_rotations[i]]).to_byte_array()
				rd.buffer_update(turrets_buffer_rid, angle_offset, 4, angle_bytes)

		if damage_events_buffer_rid.is_valid():
			rd.buffer_update(damage_events_buffer_rid, 0, dmg_bytes.size(), dmg_bytes)
		_dispatch_compute(push_bytes, active_count)
	)

func _update_agent_data(data: PackedByteArray, dispatched_count: int):
	var count = min(dispatched_count, active_count)
	grid_cells_cpu.clear()
	for i in range(count):
		var offset = i * AGENT_STRUCT_SIZE
		var px = data.decode_float(offset + 0)
		var py = data.decode_float(offset + 4)
		var hp = data.decode_s32(offset + 16) / 100.0
		positions[i] = Vector2(px, py)
		healths[i] = hp
		
		var cell_coord = Vector2i(int(floor(px / CPU_CELL_SIZE)), int(floor(py / CPU_CELL_SIZE)))
		if grid_cells_cpu.has(cell_coord):
			grid_cells_cpu[cell_coord].append(i)
		else:
			grid_cells_cpu[cell_coord] = [i]

func damage_enemy(index: int, amount: float, bonus_if_slowed: bool = false):
	if index >= 0 and index < active_count:
		var armor = type_armors[types[index]]
		var bonus_mult = 1.5 if (bonus_if_slowed and speed_modifiers[index] < 900) else 1.0
		var net_damage = maxf(0.0, (amount * bonus_mult) * (1.0 - armor))
		healths[index] -= net_damage
		flash_amounts[index] = 1.0
		var bytes = PackedByteArray()
		bytes.resize(4)
		bytes.encode_s32(0, int(healths[index] * 100.0))
		if rd:
			RenderingServer.call_on_render_thread(func():
				if agent_buffer_rid.is_valid():
					rd.buffer_update(agent_buffer_rid, index * AGENT_STRUCT_SIZE + 16, 4, bytes)
			)

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

func get_nearby_enemies(world_pos: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var rsq = radius * radius
	
	var min_cell_x = int(floor((world_pos.x - radius) / CPU_CELL_SIZE))
	var max_cell_x = int(floor((world_pos.x + radius) / CPU_CELL_SIZE))
	var min_cell_y = int(floor((world_pos.y - radius) / CPU_CELL_SIZE))
	var max_cell_y = int(floor((world_pos.y + radius) / CPU_CELL_SIZE))
	
	for cx in range(min_cell_x, max_cell_x + 1):
		for cy in range(min_cell_y, max_cell_y + 1):
			var cell = Vector2i(cx, cy)
			if grid_cells_cpu.has(cell):
				for i in grid_cells_cpu[cell]:
					if positions[i].distance_squared_to(world_pos) <= rsq:
						results.append(i)
	return results

func _dispatch_compute(push_bytes: PackedByteArray, current_active_count: int):
	if not flow_field.flow_result_tex.is_valid(): return
	
	if current_active_count > 0:
		rd.buffer_get_data_async(agent_buffer_rid, func(data: PackedByteArray):
			call_deferred("_update_agent_data", data, current_active_count)
		)
		
	if _bindings_dirty or not uniform_set.is_valid():
		_update_bindings()
		_bindings_dirty = false
	if not uniform_set.is_valid(): return
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	
	var groups = max(1, int(ceil(float(current_active_count) / 256.0)))
	var grid_groups = max(1, int(ceil(float(HASH_CELLS) / 256.0)))
	
	var current_set = uniform_set
	
	# Pass 0: Clear Grid
	push_bytes.encode_u32(0, 0)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, grid_groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 1: Kinematics
	push_bytes.encode_u32(0, 1)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Loop for binning + separation
	for i in range(4):
		# Pass 2: Binning
		push_bytes.encode_u32(0, 2)
		rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
		rd.compute_list_dispatch(compute_list, groups, 1, 1)
		rd.compute_list_add_barrier(compute_list)
		
		# Pass 3: Separation
		push_bytes.encode_u32(0, 3)
		rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
		rd.compute_list_dispatch(compute_list, groups, 1, 1)
		rd.compute_list_add_barrier(compute_list)
		
		# Swap bindings
		current_set = uniform_set_b if current_set == uniform_set else uniform_set
		rd.compute_list_bind_uniform_set(compute_list, current_set, 0)
		
		# Clear grid for next binning
		if i < 3:
			push_bytes.encode_u32(0, 0)
			rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
			rd.compute_list_dispatch(compute_list, grid_groups, 1, 1)
			rd.compute_list_add_barrier(compute_list)
			
	# If current_set != uniform_set, we need to bind uniform_set back for the rest of passes
	# so they read from buf1 (which holds the final data).
	if current_set != uniform_set:
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		
	# Pass 4: MultiMesh
	push_bytes.encode_u32(0, 4)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 5: Damage
	push_bytes.encode_u32(0, 5)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	rd.compute_list_dispatch(compute_list, groups, 1, 1)
	rd.compute_list_add_barrier(compute_list)
	
	# Pass 6: Turrets
	push_bytes.encode_u32(0, 6)
	rd.compute_list_set_push_constant(compute_list, push_bytes, 112)
	var turret_groups = max(1, int(ceil(float(turrets.size()) / 256.0)))
	rd.compute_list_dispatch(compute_list, turret_groups, 1, 1)
	rd.compute_list_end()
	dead_enemies_buffer.increment_write()
	turret_fire_events_buffer.increment_write()
	nexus_damage_buffer.increment_write()
	
	dead_enemies_buffer.read_counted_async(_on_dead_enemies_readback)
	nexus_damage_buffer.read_accumulated_async(_on_nexus_damage_readback)

func _on_dead_enemies_readback(count: int, data: PackedByteArray):
	var to_remove = []
	for i in range(count):
		var val = data.decode_u32(i * 16)
		var t = data.decode_u32(i * 16 + 4)
		var px = data.decode_float(i * 16 + 8)
		var py = data.decode_float(i * 16 + 12)
		var id = val & 0x7FFFFFFF
		var is_nexus = (val & 0x80000000) != 0
		
		var already_exists = false
		for item in to_remove:
			if item.id == id:
				already_exists = true
				break
		if not already_exists:
			to_remove.append({"id": id, "is_nexus": is_nexus, "pos": Vector2(px, py), "type": t})
	
	to_remove.sort_custom(func(a, b): return a.id > b.id)
	for item in to_remove:
		var idx = item.id
		if idx < active_count:
			if not item.is_nexus:
				GlobalEvents.enemy_killed.emit(item.type, item.pos, type_gold[item.type])
			_remove_enemy(idx)

func _on_nexus_damage_readback(amount: int):
	if amount > 0:
		GlobalEvents.nexus_damaged.emit(amount)
	
func _tick_cpu_logic(delta: float):
	var num_types = enemy_types.size()
	for t in range(num_types):
		var mmi = multimeshes[t]
		mmi.multimesh.visible_instance_count = active_count
	
	# Decay freeze timers and speed modifiers
	for i in range(active_count):
		if freeze_timers[i] > 0.0:
			freeze_timers[i] -= delta
			if freeze_timers[i] <= 0.0:
				freeze_timers[i] = 0.0
			else:
				speed_modifiers[i] = 0
		elif speed_modifiers[i] < 1000:
			speed_modifiers[i] = mini(speed_modifiers[i] + int(delta * 400.0), 1000)
	
	# Poll turret fire events
	turret_fire_events_buffer.read_counted_async(_on_turret_fire_events_readback)

func _on_turret_fire_events_readback(count: int, data: PackedByteArray):
	for i in range(count):
		var t_internal_id = data.decode_u32(i * 16)
		# var target_id = data.decode_u32(i * 16 + 4)
		var px = data.decode_float(i * 16 + 8)
		var py = data.decode_float(i * 16 + 12)
		
		var turret = turrets_by_id.get(t_internal_id)
		if is_instance_valid(turret) and turret is Turret:
			turret.on_gpu_fire(Vector2(px, py))

func _update_single_turret_on_gpu(t: Turret, is_new: bool):
	var bytes = PackedByteArray()
	bytes.resize(48)
	bytes.encode_float(0, t.global_position.x)
	bytes.encode_float(4, t.global_position.y)
	bytes.encode_float(8, t.attack_range)
	bytes.encode_float(12, t.damage)
	bytes.encode_u32(16, t.target_mode)
	
	var t_type = 0
	if t.turret_type == "melee": t_type = 1
	elif t.turret_type == "slow": t_type = 2
	bytes.encode_u32(20, t_type)
	
	bytes.encode_float(24, t.fire_rate) # Used for initial cooldown if new
	bytes.encode_float(28, t.fire_rate)
	var internal_id = t.get_meta("internal_id") if t.has_meta("internal_id") else 0
	bytes.encode_u32(32, internal_id)
	
	RenderingServer.call_on_render_thread(func():
		if not turrets_buffer_rid.is_valid(): return
		if is_new:
			rd.buffer_update(turrets_buffer_rid, 16 + t.gpu_idx * 48, 48, bytes)
		else:
			# Update basic stats without touching cooldown (offset 24)
			rd.buffer_update(turrets_buffer_rid, 16 + t.gpu_idx * 48, 24, bytes.slice(0, 24))
			rd.buffer_update(turrets_buffer_rid, 16 + t.gpu_idx * 48 + 28, 20, bytes.slice(28, 48))
	)

func add_turret(turret: Turret):
	turret.set_meta("internal_id", next_turret_id)
	turrets_by_id[next_turret_id] = turret
	next_turret_id += 1
	if 16 + (turrets.size() + 1) * 48 > turrets_byte_array.size():
		var old_size = turrets_byte_array.size()
		turrets_byte_array.resize(old_size * 2)
		var old_buf = turrets_buffer_rid
		turrets_buffer_rid = rd.storage_buffer_create(turrets_byte_array.size(), turrets_byte_array)
		RenderingServer.call_on_render_thread(func():
			if old_buf.is_valid():
				rd.buffer_copy(old_buf, turrets_buffer_rid, 0, 0, old_size)
				rd.free_rid(old_buf)
			_bindings_dirty = true
		)
		
	turret.gpu_idx = turrets.size()
	turrets.append(turret)
	
	RenderingServer.call_on_render_thread(func():
		if turrets_buffer_rid.is_valid():
			rd.buffer_update(turrets_buffer_rid, 0, 4, PackedInt32Array([turrets.size()]).to_byte_array())
	)
	_update_single_turret_on_gpu(turret, true)

func remove_turret(turret: Turret):
	var internal_id = turret.get_meta("internal_id") if turret.has_meta("internal_id") else 0
	if internal_id > 0:
		turrets_by_id.erase(internal_id)
	if turret.gpu_idx >= 0 and turret.gpu_idx < turrets.size():
		var old_idx = turret.gpu_idx
		var last_idx = turrets.size() - 1
		var last_turret = turrets[last_idx]
		
		turrets[old_idx] = last_turret
		last_turret.gpu_idx = old_idx
		turrets.pop_back()
		turret.gpu_idx = -1
		
		var new_size = turrets.size()
		RenderingServer.call_on_render_thread(func():
			if not turrets_buffer_rid.is_valid(): return
			if old_idx != last_idx:
				rd.buffer_copy(turrets_buffer_rid, turrets_buffer_rid, 16 + last_idx * 48, 16 + old_idx * 48, 48)
			rd.buffer_update(turrets_buffer_rid, 0, 4, PackedInt32Array([new_size]).to_byte_array())
		)

func update_turret(turret: Turret):
	if turret.gpu_idx >= 0:
		_update_single_turret_on_gpu(turret, false)

func _sync_turrets_to_gpu():
	pass


func _remove_enemy(index: int):
	active_count -= 1
			
	if type_is_boss[types[index]]:
		active_boss_count -= 1
			
	if index < active_count:
		var start_byte = active_count * AGENT_STRUCT_SIZE
		var dest_byte = index * AGENT_STRUCT_SIZE
		
		RenderingServer.call_on_render_thread(func():
			if agent_buffer_rid.is_valid():
				rd.buffer_copy(agent_buffer_rid, swap_buffer_rid, start_byte, 0, AGENT_STRUCT_SIZE)
				rd.buffer_copy(swap_buffer_rid, agent_buffer_rid, 0, dest_byte, AGENT_STRUCT_SIZE)
				
				rd.buffer_copy(agent_buffer_rid_2, swap_buffer_rid, start_byte, 0, AGENT_STRUCT_SIZE)
				rd.buffer_copy(swap_buffer_rid, agent_buffer_rid_2, 0, dest_byte, AGENT_STRUCT_SIZE)
		)
		
		positions[index] = positions[active_count]
		healths[index] = healths[active_count]
		max_healths[index] = max_healths[active_count]
		types[index] = types[active_count]
		gold_yields[index] = gold_yields[active_count]
		speed_modifiers[index] = speed_modifiers[active_count]
		flash_amounts[index] = flash_amounts[active_count]
		freeze_timers[index] = freeze_timers[active_count]
		freeze_timers[active_count] = 0.0
		
	var dead_bytes = PackedByteArray()
	dead_bytes.resize(4)
	dead_bytes.encode_s32(0, -10000000)
	
	RenderingServer.call_on_render_thread(func():
		if agent_buffer_rid.is_valid():
			rd.buffer_update(agent_buffer_rid, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)
			rd.buffer_update(agent_buffer_rid_2, active_count * AGENT_STRUCT_SIZE + 16, 4, dead_bytes)
	)

func _cache_nexus():
	_nexus_valid = is_instance_valid(nexus)
	if _nexus_valid and "extents" in nexus:
		_nexus_rect = Rect2(nexus.global_position - nexus.extents, nexus.extents * 2.0)
	elif _nexus_valid:
		_nexus_rect = Rect2(nexus.global_position - Vector2(32, 32), Vector2(64, 64))

var _flow_field_initialized: bool = false
func _ensure_flow_field_initialized():
	if _flow_field_initialized: return
	if not _nexus_valid: return
	if not flow_field.are_textures_ready(): return
	
	_flow_field_initialized = true
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)

func _notification(what):
	if what == NOTIFICATION_PREDELETE and rd:
		if uniform_set.is_valid() and rd.uniform_set_is_valid(uniform_set):
			rd.free_rid(uniform_set)
		if uniform_set_b.is_valid() and rd.uniform_set_is_valid(uniform_set_b):
			rd.free_rid(uniform_set_b)
		if dead_enemies_buffer:
			dead_enemies_buffer.free_rids()
		if turret_fire_events_buffer:
			turret_fire_events_buffer.free_rids()
		if nexus_damage_buffer:
			nexus_damage_buffer.free_rids()
		var rids = [pipeline_rid, shader_rid, agent_buffer_rid, agent_buffer_rid_2, grid_counts_rid, grid_cells_rid, linear_sampler_rid, texture_rd_rid, damage_events_buffer_rid, turrets_buffer_rid, dummy_ff_rid, dummy_obs_rid, swap_buffer_rid]
		for r in rids:
			if r and r.is_valid():
				rd.free_rid(r)
