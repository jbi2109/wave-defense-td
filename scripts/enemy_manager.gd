extends MultiMeshInstance2D
class_name EnemyManager

@export var max_enemies: int = 2000
@export var enemy_speed: float = 120.0
@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var nexus: Node2D = get_node("../Nexus")

var active_count: int = 0
var positions = PackedVector2Array()
var velocities = PackedVector2Array()
var healths = PackedFloat32Array()

@export var grid_cell_size: int = 128
var spatial_grid = {} 

func _ready():
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.mesh = QuadMesh.new()
	multimesh.mesh.size = Vector2(24, 24)
	multimesh.instance_count = max_enemies
	
	# Load the raw dino image and crop it to the first frame
	var raw_tex = load("res://assets/enemies/dino1.png")
	var raw_img = raw_tex.get_image()
	var frame_width = raw_img.get_width() / 24
	var frame_img = raw_img.get_region(Rect2i(0, 0, frame_width, raw_img.get_height()))
	
	# Ensure the image is in a standard format and remove any lingering tint logic
	frame_img.convert(Image.FORMAT_RGBA8)
	
	texture = ImageTexture.create_from_image(frame_img)
	
	positions.resize(max_enemies)
	velocities.resize(max_enemies)
	healths.resize(max_enemies)
	
	for i in range(max_enemies):
		multimesh.set_instance_transform_2d(i, Transform2D(0, Vector2(-5000, -5000)))

func spawn_enemy(pos: Vector2):
	print("EnemyManager: Spawning at ", pos)
	if active_count < max_enemies:
		positions[active_count] = pos
		velocities[active_count] = Vector2.ZERO
		healths[active_count] = 10.0
		active_count += 1
		print("Spawned enemy at: ", pos, " Total: ", active_count)

func _physics_process(delta):
	if not flow_field: return
	
	_update_spatial_grid()
	
	var task_id = WorkerThreadPool.add_group_task(_update_enemy_batch.bind(delta), active_count, 64)
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	
	var to_remove = []
	for i in range(active_count):
		# QuadMesh in 2D renders upside down, so flip Y.
		var s = Vector2(1, -1)
		if velocities[i].x < 0:
			s.x = -1
			
		var t = Transform2D(0, positions[i])
		t.x *= s.x
		t.y *= s.y
		multimesh.set_instance_transform_2d(i, t)
		
		if healths[i] <= 0:
			to_remove.append(i)
		elif is_instance_valid(nexus) and nexus.has_method("has_point") and nexus.has_point(positions[i]):
			GlobalEvents.nexus_damaged.emit(1)
			to_remove.append(i)
			
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
			# Adjust for flow field offset
			var field_pos = check_pos - flow_field.grid_offset
			if field_pos.x >= 0 and field_pos.x < flow_field.grid_size.x and field_pos.y >= 0 and field_pos.y < flow_field.grid_size.y:
				if flow_field.obstacle_field[field_pos.x][field_pos.y]:
					var wall_center = Vector2(check_pos) * 32.0 + Vector2(16, 16)
					
					# Hard collision
					var wall_rect = Rect2(Vector2(check_pos) * 32.0, Vector2(32, 32))
					if wall_rect.has_point(pos):
						var diff = pos - wall_center
						if diff == Vector2.ZERO: diff = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() * 0.1
						if abs(diff.x) > abs(diff.y):
							pos.x = wall_center.x + sign(diff.x) * 16.1
						else:
							pos.y = wall_center.y + sign(diff.y) * 16.1
						
					var dist_sq_wall = pos.distance_squared_to(wall_center)
					if dist_sq_wall < 1600: # 40px radius (up from 32)
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
						var dist_sq = pos.distance_squared_to(other_pos)
						if dist_sq < 900: # 30px separation radius
							var push_dir = (pos - other_pos).normalized()
							separation += push_dir * (1.0 - (dist_sq / 900.0))
							neighbor_count += 1
	
	if neighbor_count > 0:
		separation = (separation / float(neighbor_count)).normalized() * 1.5
		
	# Combine forces: Flow Field + Wall Avoidance + Enemy Separation
	dir = (dir + separation + wall_push * 8.0).normalized()
	
	velocities[i] = velocities[i].lerp(dir * enemy_speed, 6.0 * delta)
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
	multimesh.set_instance_transform_2d(active_count, Transform2D(0, Vector2(-5000, -5000)))
