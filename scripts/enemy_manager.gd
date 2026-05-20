extends Node2D
class_name EnemyManager

const EnemyDef = preload("res://scripts/enemy_definition.gd")

# --- Exports ---
@export var separation_radius_multiplier: float = 8.0  ## Per-scale separation radius
@export var overlap_weight: float = 0.05               ## How hard enemies push each other
@export var grid_cell_size: int = 32

# --- Enemy type registry ---
var enemy_types: Array[Node] = []

# --- Node refs ---
@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var nexus: Node2D = get_node("../Nexus")

# --- Per-enemy SoA buffers (grow dynamically) ---
var active_count: int = 0
var current_capacity: int = 0
var positions      = PackedVector2Array()
var velocities     = PackedVector2Array()
var healths        = PackedFloat32Array()
var max_healths    = PackedFloat32Array()  ## For health bar rendering
var types          = PackedInt32Array()
var gold_yields    = PackedInt32Array()   ## Gold dropped on kill

# --- Spatial grid ---
const GRID_WIDTH:  int = 128
const GRID_HEIGHT: int = 128
var grid_heads = PackedInt32Array()
var grid_next  = PackedInt32Array()
var inv_grid_cell_size: float = 0.0

# --- Per-type cached arrays (avoids dict lookup in hot loop) ---
var type_scales    = PackedFloat32Array()
var type_speeds    = PackedFloat32Array()
var type_armors    = PackedFloat32Array()
var type_nexus_dmg = PackedInt32Array()
var type_gold      = PackedInt32Array()

# --- Rendering ---
var multimeshes: Array[MultiMeshInstance2D] = []

# --- Cached flow field references (refreshed each physics frame) ---
var ff_grid: Array = []
var ff_obstacle: Array = []
var ff_grid_size: Vector2i
var ff_grid_offset: Vector2i
var ff_cell_size: float = 32.0

# --- Flow field regen timer ---
var last_flow_field_update: int = -99999  ## Negative so first regen is immediate

# ─────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────
func _ready():
	# Collect EnemyDefinition children
	for child in get_children():
		if child.get_script() != null and "enemy_definition" in child.get_script().resource_path:
			enemy_types.append(child)

	# Fallback defaults if no definitions in scene
	if enemy_types.is_empty():
		var swarmer = EnemyDef.new()
		swarmer.enemy_name   = "Swarmer"
		swarmer.texture_path = "res://assets/enemies/dino1.png"
		swarmer.hframes      = 24
		swarmer.scale        = 1.0
		swarmer.speed        = 120.0
		swarmer.health       = 10.0
		swarmer.spawn_weight = 10.0
		enemy_types.append(swarmer)
		add_child(swarmer)

		var tank = EnemyDef.new()
		tank.enemy_name   = "Tank"
		tank.texture_path = "res://assets/enemies/dino2.png"
		if not ResourceLoader.exists(tank.texture_path):
			tank.texture_path = "res://assets/enemies/dino1.png"
		tank.hframes      = 24
		tank.scale        = 1.8
		tank.speed        = 60.0
		tank.health       = 50.0
		tank.spawn_weight = 2.0
		enemy_types.append(tank)
		add_child(tank)

	# Build per-type cache arrays
	type_scales.resize(enemy_types.size())
	type_speeds.resize(enemy_types.size())
	type_armors.resize(enemy_types.size())
	type_nexus_dmg.resize(enemy_types.size())
	type_gold.resize(enemy_types.size())

	for i in range(enemy_types.size()):
		var t = enemy_types[i]
		type_scales[i]    = t.scale
		type_speeds[i]    = t.speed
		type_armors[i]    = t.armor if "armor" in t else 0.0
		type_nexus_dmg[i] = t.nexus_damage if "nexus_damage" in t else 1
		type_gold[i]      = t.gold_yield if "gold_yield" in t else 5

		# Build MultiMesh per type
		var mmi = MultiMeshInstance2D.new()
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		mmi.multimesh.mesh = QuadMesh.new()
		mmi.multimesh.mesh.size = Vector2(24, 24)

		var raw_tex = load(t.texture_path)
		if raw_tex:
			var raw_img    = raw_tex.get_image()
			var frame_w    = raw_img.get_width() / t.hframes
			var frame_img  = raw_img.get_region(Rect2i(0, 0, frame_w, raw_img.get_height()))
			frame_img.convert(Image.FORMAT_RGBA8)
			mmi.texture = ImageTexture.create_from_image(frame_img)

		add_child(mmi)
		multimeshes.append(mmi)

	grid_heads.resize(GRID_WIDTH * GRID_HEIGHT)
	inv_grid_cell_size = 1.0 / float(grid_cell_size)
	last_flow_field_update = Time.get_ticks_msec()
	_ensure_capacity(256)

# ─────────────────────────────────────────────────────────────
#  CAPACITY MANAGEMENT
# ─────────────────────────────────────────────────────────────
func _ensure_capacity(required: int):
	if required <= current_capacity:
		return
	var new_cap = max(256, current_capacity)
	while new_cap < required:
		new_cap *= 2
	current_capacity = new_cap

	positions.resize(new_cap)
	velocities.resize(new_cap)
	healths.resize(new_cap)
	max_healths.resize(new_cap)
	types.resize(new_cap)
	gold_yields.resize(new_cap)
	grid_next.resize(new_cap)

	for mmi in multimeshes:
		var old = mmi.multimesh.instance_count
		mmi.multimesh.instance_count = new_cap
		for j in range(old, new_cap):
			mmi.multimesh.set_instance_transform_2d(j, Transform2D(0, Vector2(-5000, -5000)))

# ─────────────────────────────────────────────────────────────
#  SPAWN
# ─────────────────────────────────────────────────────────────
func spawn_enemy(pos: Vector2, type_index: int = 0):
	_ensure_capacity(active_count + 1)
	var t = enemy_types[type_index]
	positions[active_count]   = pos
	velocities[active_count]  = Vector2.ZERO
	healths[active_count]     = t.health
	max_healths[active_count] = t.health
	types[active_count]       = type_index
	gold_yields[active_count] = type_gold[type_index]
	active_count += 1

# ─────────────────────────────────────────────────────────────
#  PHYSICS UPDATE — split into helpers for readability
# ─────────────────────────────────────────────────────────────
var _current_delta: float = 0.0
var _nexus_valid: bool = false
var _nexus_rect: Rect2 = Rect2()

func _physics_process(delta):
	if not flow_field: return

	_current_delta = delta
	var current_ms = Time.get_ticks_msec()

	_update_spatial_grid()
	_cache_nexus()
	_maybe_regen_flow_field(current_ms)
	_cache_flow_field()

	if active_count == 0:
		return

	_tick_movement(delta)
	_tick_render()
	_tick_deaths()

# ─────────────────────────────────────────────────────────────
#  HELPER — nexus cache
# ─────────────────────────────────────────────────────────────
func _cache_nexus():
	_nexus_valid = is_instance_valid(nexus)
	if _nexus_valid and "extents" in nexus:
		_nexus_rect = Rect2(nexus.global_position - nexus.extents, nexus.extents * 2.0)
	elif _nexus_valid:
		_nexus_rect = Rect2(nexus.global_position - Vector2(32, 32), Vector2(64, 64))

# ─────────────────────────────────────────────────────────────
#  HELPER — flow field regen (expensive BFS, 3s timer)
# ─────────────────────────────────────────────────────────────
func _maybe_regen_flow_field(current_ms: int):
	if active_count == 0: return  # No enemies = no need to regenerate
	if current_ms - last_flow_field_update < 3000: return
	if not _nexus_valid: return
	last_flow_field_update = current_ms
	if flow_field.has_method("update_density"):
		flow_field.update_density(positions, active_count)
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)

# ─────────────────────────────────────────────────────────────
#  HELPER — cache flow field arrays (cheap ref copy each frame)
# ─────────────────────────────────────────────────────────────
func _cache_flow_field():
	ff_grid       = flow_field.grid
	ff_obstacle   = flow_field.obstacle_field
	ff_grid_size  = flow_field.grid_size
	ff_grid_offset = flow_field.grid_offset
	ff_cell_size  = float(flow_field.cell_size)

# ─────────────────────────────────────────────────────────────
#  HELPER — movement, separation, wall resolution
# ─────────────────────────────────────────────────────────────
func _tick_movement(delta: float):
	for i in range(active_count):
		var pos     = positions[i]
		var t_idx   = types[i]
		var my_scale = type_scales[t_idx]
		var my_speed = type_speeds[t_idx]

		# --- Flow field direction lookup (O(1) per enemy per frame) ---
		var t_dir    = Vector2.ZERO
		var gx_ff    = int(floor(pos.x / ff_cell_size)) - ff_grid_offset.x
		var gy_ff    = int(floor(pos.y / ff_cell_size)) - ff_grid_offset.y
		if gx_ff >= 0 and gx_ff < ff_grid_size.x and gy_ff >= 0 and gy_ff < ff_grid_size.y:
			t_dir = ff_grid[gx_ff][gy_ff]

		# --- U-turn prevention (dot product check, no sqrt needed) ---
		var vel     = velocities[i]
		var speed_sq = vel.x * vel.x + vel.y * vel.y
		if speed_sq > 400.0 and t_dir != Vector2.ZERO:
			var inv_sp  = 1.0 / sqrt(speed_sq)
			var vnx     = vel.x * inv_sp
			var vny     = vel.y * inv_sp
			if vnx * t_dir.x + vny * t_dir.y < -0.5:  # >120° = reject reversal
				t_dir.x = vnx * 0.9 + t_dir.x * 0.1
				t_dir.y = vny * 0.9 + t_dir.y * 0.1
				var ls  = t_dir.x * t_dir.x + t_dir.y * t_dir.y
				if ls > 0.0001:
					var il = 1.0 / sqrt(ls)
					t_dir.x *= il
					t_dir.y *= il

		# --- Movement integration ---
		var lf = 6.0 * delta
		var vx = vel.x + (t_dir.x * my_speed - vel.x) * lf
		var vy = vel.y + (t_dir.y * my_speed - vel.y) * lf
		velocities[i].x = vx
		velocities[i].y = vy
		pos.x += vx * delta
		pos.y += vy * delta

		# --- Enemy–enemy separation (spatial grid, check each pair once) ---
		var gx = clampi(int(pos.x * inv_grid_cell_size), 0, GRID_WIDTH - 1)
		var gy = clampi(int(pos.y * inv_grid_cell_size), 0, GRID_HEIGHT - 1)
		for dy in range(max(0, gy - 1), min(GRID_HEIGHT, gy + 2)):
			var row = dy * GRID_WIDTH
			for dx in range(max(0, gx - 1), min(GRID_WIDTH, gx + 2)):
				var other_idx = grid_heads[row + dx]
				while other_idx != -1:
					if other_idx > i:
						var op    = positions[other_idx]
						var ddx   = pos.x - op.x
						var ddy   = pos.y - op.y
						var dsq   = ddx * ddx + ddy * ddy
						var oth_s = type_scales[types[other_idx]]
						var sep   = separation_radius_multiplier * (my_scale + oth_s)
						if dsq < sep * sep:
							if dsq < 0.0001:
								ddx = 0.1; ddy = 0.1; dsq = 0.02
							var dist    = sqrt(dsq)
							var overlap = sep - dist
							var mm      = my_scale * my_scale
							var om      = oth_s * oth_s
							var tm      = mm + om
							var push    = overlap * overlap_weight * 0.5
							var px      = (ddx / dist) * push
							var py      = (ddy / dist) * push
							pos.x       += px * (om / tm)
							pos.y       += py * (om / tm)
							op.x        -= px * (mm / tm)
							op.y        -= py * (mm / tm)
							positions[other_idx] = op
					other_idx = grid_next[other_idx]

		# --- Soft wall push + hard escape ---
		var tx = int(floor(pos.x / 32.0)) - ff_grid_offset.x
		var ty = int(floor(pos.y / 32.0)) - ff_grid_offset.y
		var margin = 6.0 * my_scale
		var lx = pos.x - (tx + ff_grid_offset.x) * 32.0
		var ly = pos.y - (ty + ff_grid_offset.y) * 32.0

		if lx < margin and tx > 0 and tx - 1 < ff_grid_size.x and ff_obstacle[tx - 1][ty]:
			pos.x += (margin - lx) * 0.5
		elif lx > 32.0 - margin and tx + 1 < ff_grid_size.x and ff_obstacle[tx + 1][ty]:
			pos.x -= (lx - (32.0 - margin)) * 0.5
		if ly < margin and ty > 0 and ty - 1 < ff_grid_size.y and ff_obstacle[tx][ty - 1]:
			pos.y += (margin - ly) * 0.5
		elif ly > 32.0 - margin and ty + 1 < ff_grid_size.y and ff_obstacle[tx][ty + 1]:
			pos.y -= (ly - (32.0 - margin)) * 0.5

		if tx < 0 or tx >= ff_grid_size.x or ty < 0 or ty >= ff_grid_size.y or ff_obstacle[tx][ty]:
			var best_dsq  = 1000000.0
			var escape    = pos
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var cx = tx + ox
					var cy = ty + oy
					if cx >= 0 and cx < ff_grid_size.x and cy >= 0 and cy < ff_grid_size.y:
						if not ff_obstacle[cx][cy]:
							var gc  = Vector2(cx + ff_grid_offset.x, cy + ff_grid_offset.y) * 32.0 + Vector2(16, 16)
							var dsq = pos.distance_squared_to(gc)
							if dsq < best_dsq:
								best_dsq = dsq
								escape   = gc
			pos = escape
			velocities[i] = velocities[i] * 0.8

		positions[i] = pos

# ─────────────────────────────────────────────────────────────
#  HELPER — update multimesh transforms
# ─────────────────────────────────────────────────────────────
func _tick_render():
	var type_counters = []
	type_counters.resize(enemy_types.size())
	type_counters.fill(0)

	for i in range(active_count):
		var t        = types[i]
		var type_def = enemy_types[t]
		var s        = Vector2(type_def.scale, -type_def.scale)
		if velocities[i].x < 0:
			s.x = -s.x
		var xform = Transform2D(0, positions[i])
		xform.x *= s.x
		xform.y *= s.y
		var local_idx = type_counters[t]
		multimeshes[t].multimesh.set_instance_transform_2d(local_idx, xform)
		type_counters[t] += 1

	for t in range(enemy_types.size()):
		multimeshes[t].multimesh.visible_instance_count = type_counters[t]

# ─────────────────────────────────────────────────────────────
#  HELPER — death + nexus hit detection
# ─────────────────────────────────────────────────────────────
func _tick_deaths():
	var to_remove: Array[int] = []

	for i in range(active_count):
		if healths[i] <= 0:
			to_remove.append(i)
			GlobalEvents.enemy_killed.emit(types[i], positions[i], gold_yields[i])
		elif _nexus_valid and _nexus_rect.has_point(positions[i]):
			GlobalEvents.nexus_damaged.emit(type_nexus_dmg[types[i]])
			to_remove.append(i)

	if to_remove.is_empty(): return
	to_remove.sort()
	to_remove.reverse()
	for idx in to_remove:
		_remove_enemy(idx)

# ─────────────────────────────────────────────────────────────
#  DAMAGE
# ─────────────────────────────────────────────────────────────
func damage_enemy(index: int, amount: float):
	if index >= 0 and index < active_count:
		var armor = type_armors[types[index]]
		healths[index] -= amount * (1.0 - armor)

# ─────────────────────────────────────────────────────────────
#  SPATIAL GRID UPDATE
# ─────────────────────────────────────────────────────────────
func _update_spatial_grid():
	grid_heads.fill(-1)
	for i in range(active_count):
		var p   = positions[i]
		var gx  = clampi(int(p.x / float(grid_cell_size)), 0, GRID_WIDTH - 1)
		var gy  = clampi(int(p.y / float(grid_cell_size)), 0, GRID_HEIGHT - 1)
		var idx = gy * GRID_WIDTH + gx
		grid_next[i]   = grid_heads[idx]
		grid_heads[idx] = i

# ─────────────────────────────────────────────────────────────
#  NEARBY ENEMIES QUERY (used by turrets)
# ─────────────────────────────────────────────────────────────
func get_nearby_enemies(world_pos: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var gp    = Vector2i(world_pos / float(grid_cell_size))
	var gr    = int(ceil(radius / float(grid_cell_size)))
	var gxmin = clampi(gp.x - gr, 0, GRID_WIDTH - 1)
	var gxmax = clampi(gp.x + gr, 0, GRID_WIDTH - 1)
	var gymin = clampi(gp.y - gr, 0, GRID_HEIGHT - 1)
	var gymax = clampi(gp.y + gr, 0, GRID_HEIGHT - 1)
	var rsq   = radius * radius
	for y in range(gymin, gymax + 1):
		var row = y * GRID_WIDTH
		for x in range(gxmin, gxmax + 1):
			var idx = grid_heads[row + x]
			while idx != -1:
				if world_pos.distance_squared_to(positions[idx]) <= rsq:
					results.append(idx)
				idx = grid_next[idx]
	return results

# ─────────────────────────────────────────────────────────────
#  REMOVE ENEMY (swap-with-last for O(1))
# ─────────────────────────────────────────────────────────────
func _remove_enemy(index: int):
	active_count -= 1
	if index < active_count:
		positions[index]   = positions[active_count]
		velocities[index]  = velocities[active_count]
		healths[index]     = healths[active_count]
		max_healths[index] = max_healths[active_count]
		types[index]       = types[active_count]
		gold_yields[index] = gold_yields[active_count]
