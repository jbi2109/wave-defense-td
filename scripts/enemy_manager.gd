extends Node2D
class_name EnemyManager

const EnemyDef = preload("res://scripts/enemy_definition.gd")

@export var enemy_separation: float = 12.0
@export var overlap_weight: float = 0.05
var enemy_types: Array[Node] = []
var current_capacity: int = 0

@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var nexus: Node2D = get_node("../Nexus")

var active_count: int = 0
var positions = PackedVector2Array()
var velocities = PackedVector2Array()
var healths = PackedFloat32Array()
var types = PackedInt32Array()
@export var grid_cell_size: int = 32
const GRID_WIDTH: int = 128
const GRID_HEIGHT: int = 128
const TILE_OFFSETS = [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]

var grid_heads = PackedInt32Array()
var grid_next = PackedInt32Array()
var type_scales = PackedFloat32Array()
var type_speeds = PackedFloat32Array()
var multimeshes: Array[MultiMeshInstance2D] = []

# Cached flow field variables for performance
var ff_grid: Array = []
var ff_obstacle: Array = []
var ff_grid_size: Vector2i
var ff_grid_offset: Vector2i
var ff_cell_size: float = 32.0

func _ready():
	for child in get_children():
		if child is EnemyDef or (child.get_script() != null and "enemy_definition.gd" in child.get_script().resource_path):
			enemy_types.append(child)
			
	if enemy_types.is_empty():
		# Create a default swarmer
		var swarmer = EnemyDef.new()
		swarmer.enemy_name = "Swarmer"
		swarmer.texture_path = "res://assets/enemies/dino1.png"
		swarmer.hframes = 24
		swarmer.scale = 1.0
		swarmer.speed = 120.0
		swarmer.health = 10.0
		swarmer.spawn_weight = 10.0
		enemy_types.append(swarmer)
		add_child(swarmer)
		
		# Create a default tank
		var tank = EnemyDef.new()
		tank.enemy_name = "Tank"
		tank.texture_path = "res://assets/enemies/dino2.png" # Assuming dino2 exists, fallback to dino1 otherwise
		if not ResourceLoader.exists(tank.texture_path):
			tank.texture_path = "res://assets/enemies/dino1.png"
		tank.hframes = 24
		tank.scale = 1.8
		tank.speed = 60.0
		tank.health = 50.0
		tank.spawn_weight = 2.0
		enemy_types.append(tank)
		add_child(tank)
	
	grid_heads.resize(GRID_WIDTH * GRID_HEIGHT)
	type_scales.resize(enemy_types.size())
	type_speeds.resize(enemy_types.size())
	
	for i in range(enemy_types.size()):
		var type = enemy_types[i]
		type_scales[i] = type.scale
		type_speeds[i] = type.speed
		
		var mmi = MultiMeshInstance2D.new()
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		mmi.multimesh.mesh = QuadMesh.new()
		mmi.multimesh.mesh.size = Vector2(24, 24)
		
		var raw_tex = load(type.texture_path)
		if raw_tex:
			var raw_img = raw_tex.get_image()
			var frame_width = raw_img.get_width() / type.hframes
			var frame_img = raw_img.get_region(Rect2i(0, 0, frame_width, raw_img.get_height()))
			frame_img.convert(Image.FORMAT_RGBA8)
			mmi.texture = ImageTexture.create_from_image(frame_img)
		
		add_child(mmi)
		multimeshes.append(mmi)
		
	inv_grid_cell_size = 1.0 / float(grid_cell_size)
	_ensure_capacity(256)

func _ensure_capacity(required: int):
	if required <= current_capacity:
		return
	var new_cap = current_capacity
	if new_cap == 0:
		new_cap = 256
	while new_cap < required:
		new_cap *= 2
	current_capacity = new_cap
	positions.resize(new_cap)
	velocities.resize(new_cap)
	healths.resize(new_cap)
	types.resize(new_cap)
	grid_next.resize(new_cap)
	for mmi in multimeshes:
		var old_count = mmi.multimesh.instance_count
		mmi.multimesh.instance_count = new_cap
		for j in range(old_count, new_cap):
			mmi.multimesh.set_instance_transform_2d(j, Transform2D(0, Vector2(-5000, -5000)))

func spawn_enemy(pos: Vector2, type_index: int = 0):
	_ensure_capacity(active_count + 1)
	positions[active_count] = pos
	velocities[active_count] = Vector2.ZERO
	healths[active_count] = enemy_types[type_index].health
	types[active_count] = type_index
	active_count += 1

var current_delta: float = 0.0
var inv_grid_cell_size: float = 0.0
var last_flow_field_update: int = 0

func _physics_process(delta):
	if not flow_field: return
	
	current_delta = delta
	var current_ms = Time.get_ticks_msec()
	
	_update_spatial_grid()
	
	# Cache nexus rect for fast overlap check
	var nexus_valid = is_instance_valid(nexus)
	var nexus_rect_global = Rect2()
	if nexus_valid and "extents" in nexus:
		nexus_rect_global = Rect2(nexus.global_position - nexus.extents, nexus.extents * 2.0)
	elif nexus_valid:
		# Fallback if nexus doesn't have extents property directly
		nexus_rect_global = Rect2(nexus.global_position - Vector2(32, 32), Vector2(64, 64))
		
	# Regenerate the flow field BFS every 3 seconds (the expensive operation)
	if current_ms - last_flow_field_update > 3000 and nexus_valid:
		last_flow_field_update = current_ms
		if flow_field.has_method("update_density"):
			flow_field.update_density(positions, active_count)
		flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
	
	# Cache flow field variables to avoid cross-script lookups in the loop
	ff_grid = flow_field.grid
	ff_obstacle = flow_field.obstacle_field
	ff_grid_size = flow_field.grid_size
	ff_grid_offset = flow_field.grid_offset
	ff_cell_size = float(flow_field.cell_size)
	
	for i in range(active_count):
		var pos = positions[i]
		var t_idx = types[i]
		var my_scale = type_scales[t_idx]
		var my_speed = type_speeds[t_idx]
		
		# 1. Read flow field direction at CURRENT position every frame
		#    This is just an array lookup (O(1)) — the expensive BFS regeneration
		#    is on a 3-second timer above, not here.
		var t_dir = Vector2.ZERO
		var grid_pos_x = int(floor(pos.x / ff_cell_size)) - ff_grid_offset.x
		var grid_pos_y = int(floor(pos.y / ff_cell_size)) - ff_grid_offset.y
		if grid_pos_x >= 0 and grid_pos_x < ff_grid_size.x and grid_pos_y >= 0 and grid_pos_y < ff_grid_size.y:
			t_dir = ff_grid[grid_pos_x][grid_pos_y]
		
		# U-turn prevention: if the enemy is already moving and the flow field
		# suggests going nearly backwards (>120°), reject the reversal and
		# keep the current heading. This stops enemies flipping between paths.
		var vel = velocities[i]
		var speed_sq = vel.x * vel.x + vel.y * vel.y
		if speed_sq > 400.0 and t_dir != Vector2.ZERO: # moving > ~20 px/s
			var inv_speed = 1.0 / sqrt(speed_sq)
			var vel_nx = vel.x * inv_speed
			var vel_ny = vel.y * inv_speed
			var dot = vel_nx * t_dir.x + vel_ny * t_dir.y
			if dot < -0.5: # angle > 120° = U-turn
				# Blend heavily toward current direction to prevent reversal
				t_dir.x = vel_nx * 0.9 + t_dir.x * 0.1
				t_dir.y = vel_ny * 0.9 + t_dir.y * 0.1
				var len_sq = t_dir.x * t_dir.x + t_dir.y * t_dir.y
				if len_sq > 0.0001:
					var inv_len = 1.0 / sqrt(len_sq)
					t_dir.x *= inv_len
					t_dir.y *= inv_len

		# 2. Movement Integration
		var vx = vel.x
		var vy = vel.y
		var lerp_f = 6.0 * delta
		vx += (t_dir.x * my_speed - vx) * lerp_f
		vy += (t_dir.y * my_speed - vy) * lerp_f
		velocities[i].x = vx
		velocities[i].y = vy
		
		pos.x += vx * delta
		pos.y += vy * delta

		# 3. SOLID OBJECT COLLISION (Every Frame Position-Based Dynamics)
		var gx = clampi(int(pos.x * inv_grid_cell_size), 0, GRID_WIDTH - 1)
		var gy = clampi(int(pos.y * inv_grid_cell_size), 0, GRID_HEIGHT - 1)
		var gx_min = gx - 1 if gx > 0 else 0
		var gx_max = gx + 1 if gx < GRID_WIDTH - 1 else GRID_WIDTH - 1
		var gy_min = gy - 1 if gy > 0 else 0
		var gy_max = gy + 1 if gy < GRID_HEIGHT - 1 else GRID_HEIGHT - 1
		
		for y in range(gy_min, gy_max + 1):
			var row_offset = y * GRID_WIDTH
			for x in range(gx_min, gx_max + 1):
				var other_idx = grid_heads[row_offset + x]
				while other_idx != -1:
					if other_idx > i: # Only check each pair once for 2x performance and stability
						var other_pos = positions[other_idx]
						var dx = pos.x - other_pos.x
						var dy = pos.y - other_pos.y
						var dist_sq = dx*dx + dy*dy
						var other_scale = type_scales[types[other_idx]]
						var sep_dist = enemy_separation * (my_scale + other_scale)
						if dist_sq < sep_dist * sep_dist:
							if dist_sq < 0.0001:
								dx = 0.1
								dy = 0.1
								dist_sq = 0.02
								
							var dist = sqrt(dist_sq)
							var overlap = sep_dist - dist
							
							var my_mass = my_scale * my_scale
							var other_mass = other_scale * other_scale
							var total_mass = my_mass + other_mass
							
							var push_amount = overlap * overlap_weight * 0.5
							var push_x = (dx / dist) * push_amount
							var push_y = (dy / dist) * push_amount
							
							pos.x += push_x * (other_mass / total_mass)
							pos.y += push_y * (other_mass / total_mass)
							
							other_pos.x -= push_x * (my_mass / total_mass)
							other_pos.y -= push_y * (my_mass / total_mass)
							positions[other_idx] = other_pos # Instantly update other enemy's position
							
					other_idx = grid_next[other_idx]

		# 4. HARD GRID CLAMP (Zero Clipping Guarantee)
		var tx = int(floor(pos.x / 32.0)) - ff_grid_offset.x
		var ty = int(floor(pos.y / 32.0)) - ff_grid_offset.y
		
		# Soft Wall Push (Prevents squishing directly against grid boundaries)
		var wall_push_x = 0.0
		var wall_push_y = 0.0
		var margin = 6.0 * my_scale
		
		var local_x = pos.x - (tx + ff_grid_offset.x) * 32.0
		var local_y = pos.y - (ty + ff_grid_offset.y) * 32.0
		
		if local_x < margin and tx > 0 and ff_obstacle[tx - 1][ty]:
			wall_push_x += margin - local_x
		elif local_x > 32.0 - margin and tx < ff_grid_size.x - 1 and ff_obstacle[tx + 1][ty]:
			wall_push_x -= local_x - (32.0 - margin)
			
		if local_y < margin and ty > 0 and ff_obstacle[tx][ty - 1]:
			wall_push_y += margin - local_y
		elif local_y > 32.0 - margin and ty < ff_grid_size.y - 1 and ff_obstacle[tx][ty + 1]:
			wall_push_y -= local_y - (32.0 - margin)
			
		pos.x += wall_push_x * 0.5
		pos.y += wall_push_y * 0.5
		
		# If they are deeply in a wall, find nearest grass in 3x3
		if tx < 0 or tx >= ff_grid_size.x or ty < 0 or ty >= ff_grid_size.y or ff_obstacle[tx][ty]:
			var best_dist_sq = 1000000.0
			var escape_pos = pos
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var cx = tx + ox
					var cy = ty + oy
					if cx >= 0 and cx < ff_grid_size.x and cy >= 0 and cy < ff_grid_size.y:
						if not ff_obstacle[cx][cy]:
							var grass_center = Vector2(cx + ff_grid_offset.x, cy + ff_grid_offset.y) * 32.0 + Vector2(16, 16)
							var d_sq = pos.distance_squared_to(grass_center)
							if d_sq < best_dist_sq:
								best_dist_sq = d_sq
								escape_pos = grass_center
			pos = escape_pos
			velocities[i] = velocities[i] * 0.8 # Less drastic dampening
		
		positions[i] = pos
	var to_remove = []
	var type_counters = []
	type_counters.resize(enemy_types.size())
	type_counters.fill(0)
	
	for i in range(active_count):
		var t = types[i]
		var type_def = enemy_types[t]
		
		# QuadMesh in 2D renders upside down, so flip Y.
		var s = Vector2(type_def.scale, -type_def.scale)
		if velocities[i].x < 0:
			s.x = -s.x
			
		var xform = Transform2D(0, positions[i])
		xform.x *= s.x
		xform.y *= s.y
		
		var mmi = multimeshes[t]
		var local_idx = type_counters[t]
		mmi.multimesh.set_instance_transform_2d(local_idx, xform)
		type_counters[t] += 1
		
		if healths[i] <= 0:
			to_remove.append(i)
		elif nexus_valid and nexus_rect_global.has_point(positions[i]):
			GlobalEvents.nexus_damaged.emit(1)
			to_remove.append(i)
			
	# Simply set visible instances instead of moving off-screen
	for t in range(enemy_types.size()):
		var mmi = multimeshes[t]
		mmi.multimesh.visible_instance_count = type_counters[t]
			
	# Remove backwards to keep indices valid
	if to_remove.size() > 0:
		to_remove.sort()
		to_remove.reverse()
		for idx in to_remove:
			_remove_enemy(idx)

func damage_enemy(index: int, amount: float):
	if index >= 0 and index < active_count:
		healths[index] -= amount

func _update_spatial_grid():
	grid_heads.fill(-1)
	for i in range(active_count):
		var p = positions[i]
		var gx = clampi(int(p.x / float(grid_cell_size)), 0, GRID_WIDTH - 1)
		var gy = clampi(int(p.y / float(grid_cell_size)), 0, GRID_HEIGHT - 1)
		var cell_idx = gy * GRID_WIDTH + gx
		
		grid_next[i] = grid_heads[cell_idx]
		grid_heads[cell_idx] = i

func get_nearby_enemies(world_pos: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var grid_pos = Vector2i(world_pos / float(grid_cell_size))
	var grid_radius = int(ceil(radius / float(grid_cell_size)))
	
	var gx_min = clampi(grid_pos.x - grid_radius, 0, GRID_WIDTH - 1)
	var gx_max = clampi(grid_pos.x + grid_radius, 0, GRID_WIDTH - 1)
	var gy_min = clampi(grid_pos.y - grid_radius, 0, GRID_HEIGHT - 1)
	var gy_max = clampi(grid_pos.y + grid_radius, 0, GRID_HEIGHT - 1)
	
	var radius_sq = radius * radius
	
	for y in range(gy_min, gy_max + 1):
		for x in range(gx_min, gx_max + 1):
			var cell_idx = y * GRID_WIDTH + x
			var other_idx = grid_heads[cell_idx]
			while other_idx != -1:
				if world_pos.distance_squared_to(positions[other_idx]) <= radius_sq:
					results.append(other_idx)
				other_idx = grid_next[other_idx]
				
	return results

func _remove_enemy(index):
	active_count -= 1
	if index < active_count:
		positions[index] = positions[active_count]
		velocities[index] = velocities[active_count]
		healths[index] = healths[active_count]
		types[index] = types[active_count]
