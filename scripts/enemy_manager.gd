extends Node2D
class_name EnemyManager

@export var max_enemies: int = 2000
var enemy_types: Array[EnemyDefinition] = []

@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var nexus: Node2D = get_node("../Nexus")

var active_count: int = 0
var positions = PackedVector2Array()
var velocities = PackedVector2Array()
var healths = PackedFloat32Array()
var types = PackedInt32Array()

@export var grid_cell_size: int = 128
var spatial_grid = {} 
var multimeshes: Array[MultiMeshInstance2D] = []

func _ready():
	for child in get_children():
		if child is EnemyDefinition:
			enemy_types.append(child)
			
	if enemy_types.is_empty():
		# Create a default swarmer
		var swarmer = EnemyDefinition.new()
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
		var tank = EnemyDefinition.new()
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
	
	positions.resize(max_enemies)
	velocities.resize(max_enemies)
	healths.resize(max_enemies)
	types.resize(max_enemies)
	
	for type in enemy_types:
		var mmi = MultiMeshInstance2D.new()
		mmi.multimesh = MultiMesh.new()
		mmi.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		mmi.multimesh.mesh = QuadMesh.new()
		mmi.multimesh.mesh.size = Vector2(24, 24)
		mmi.multimesh.instance_count = max_enemies
		
		var raw_tex = load(type.texture_path)
		if raw_tex:
			var raw_img = raw_tex.get_image()
			var frame_width = raw_img.get_width() / type.hframes
			var frame_img = raw_img.get_region(Rect2i(0, 0, frame_width, raw_img.get_height()))
			frame_img.convert(Image.FORMAT_RGBA8)
			mmi.texture = ImageTexture.create_from_image(frame_img)
		
		for i in range(max_enemies):
			mmi.multimesh.set_instance_transform_2d(i, Transform2D(0, Vector2(-5000, -5000)))
		
		add_child(mmi)
		multimeshes.append(mmi)

func spawn_enemy(pos: Vector2, type_index: int = 0):
	if active_count < max_enemies:
		positions[active_count] = pos
		velocities[active_count] = Vector2.ZERO
		healths[active_count] = enemy_types[type_index].health
		types[active_count] = type_index
		active_count += 1

func _physics_process(delta):
	if not flow_field: return
	
	_update_spatial_grid()
	
	var task_id = WorkerThreadPool.add_group_task(_update_enemy_batch.bind(delta), active_count, 64)
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	
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
		elif is_instance_valid(nexus) and nexus.has_method("has_point") and nexus.has_point(positions[i]):
			GlobalEvents.nexus_damaged.emit(1)
			to_remove.append(i)
			
	# Hide unused multimesh instances for this frame
	for t in range(enemy_types.size()):
		var mmi = multimeshes[t]
		for j in range(type_counters[t], max_enemies):
			# Optimization: only hide if it wasn't already hidden (approximate by checking just beyond active)
			if j > type_counters[t] + 10: break # Hacky fast skip, but proper way is keeping track of last frame count
			mmi.multimesh.set_instance_transform_2d(j, Transform2D(0, Vector2(-5000, -5000)))
			
	# Proper hide loop:
	for t in range(enemy_types.size()):
		var mmi = multimeshes[t]
		for j in range(type_counters[t], active_count + to_remove.size() + 1):
			if j < max_enemies:
				mmi.multimesh.set_instance_transform_2d(j, Transform2D(0, Vector2(-5000, -5000)))
			
	# Remove backwards to keep indices valid
	to_remove.sort()
	to_remove.reverse()
	for idx in to_remove:
		_remove_enemy(idx)

func damage_enemy(index: int, amount: float):
	if index >= 0 and index < active_count:
		healths[index] -= amount

func _update_spatial_grid():
	spatial_grid.clear()
	for i in range(active_count):
		var grid_pos = Vector2i(positions[i] / float(grid_cell_size))
		if not spatial_grid.has(grid_pos):
			spatial_grid[grid_pos] = []
		spatial_grid[grid_pos].append(i)

func _update_enemy_batch(i: int, delta: float):
	var pos = positions[i]
	var dir = flow_field.get_direction(pos)
	var type_def = enemy_types[types[i]]
	
	# Separation logic (Flocking/Boids)
	var separation = Vector2.ZERO
	var neighbor_count = 0
	
	# Wall avoidance logic
	var wall_push = Vector2.ZERO
	var grid_pos = Vector2i(pos / float(grid_cell_size))
	var tile_pos = Vector2i(pos / 32.0)
	
	# Check adjacent tiles for walls
	var offsets = [Vector2i(0,0), Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]
	for off in offsets:
		var check_pos = tile_pos + off
		if check_pos.x >= 0 and check_pos.x < flow_field.grid_size.x and check_pos.y >= 0 and check_pos.y < flow_field.grid_size.y:
			var field_pos = check_pos - flow_field.grid_offset
			if field_pos.x >= 0 and field_pos.x < flow_field.grid_size.x and field_pos.y >= 0 and field_pos.y < flow_field.grid_size.y:
				if flow_field.obstacle_field[field_pos.x][field_pos.y]:
					var wall_center = Vector2(check_pos) * 32.0 + Vector2(16, 16)
					var wall_rect = Rect2(Vector2(check_pos) * 32.0, Vector2(32, 32))
					if wall_rect.has_point(pos):
						var diff = pos - wall_center
						if diff == Vector2.ZERO: diff = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * 0.1
						if abs(diff.x) > abs(diff.y):
							pos.x = wall_center.x + sign(diff.x) * 16.1
						else:
							pos.y = wall_center.y + sign(diff.y) * 16.1
						
					var dist_sq_wall = pos.distance_squared_to(wall_center)
					if dist_sq_wall < 1600:
						var push_dir = (pos - wall_center)
						if push_dir == Vector2.ZERO: push_dir = Vector2(1, 0)
						wall_push += push_dir.normalized() * (1.0 - (dist_sq_wall / 1600.0))
	
	for x in range(grid_pos.x - 1, grid_pos.x + 2):
		for y in range(grid_pos.y - 1, grid_pos.y + 2):
			var cell = Vector2i(x, y)
			if spatial_grid.has(cell):
				for other_idx in spatial_grid[cell]:
					if other_idx != i:
						var other_pos = positions[other_idx]
						var other_type_def = enemy_types[types[other_idx]]
						var dist_sq = pos.distance_squared_to(other_pos)
						
						# Dynamic separation radius based on scale
						var sep_dist = 12.0 * type_def.scale + 12.0 * other_type_def.scale
						var sep_sq = sep_dist * sep_dist
						
						if dist_sq < sep_sq:
							var push_dir = (pos - other_pos).normalized()
							separation += push_dir * (1.0 - (dist_sq / sep_sq))
							neighbor_count += 1
	
	if neighbor_count > 0:
		separation = (separation / float(neighbor_count)).normalized() * 1.2
		
	dir = (dir + separation + wall_push * 8.0).normalized()
	
	velocities[i] = velocities[i].lerp(dir * type_def.speed, 6.0 * delta)
	positions[i] += velocities[i] * delta

func get_nearby_enemies(world_pos: Vector2, radius: float) -> Array[int]:
	var results: Array[int] = []
	var grid_pos = Vector2i(world_pos / float(grid_cell_size))
	var grid_radius = int(ceil(radius / float(grid_cell_size)))
	for x in range(grid_pos.x - grid_radius, grid_pos.x + grid_radius + 1):
		for y in range(grid_pos.y - grid_radius, grid_pos.y + grid_radius + 1):
			var cell = Vector2i(x, y)
			if spatial_grid.has(cell):
				results.append_array(spatial_grid[cell])
	return results

func _remove_enemy(index):
	active_count -= 1
	if index < active_count:
		positions[index] = positions[active_count]
		velocities[index] = velocities[active_count]
		healths[index] = healths[active_count]
		types[index] = types[active_count]
