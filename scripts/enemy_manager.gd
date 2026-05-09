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
	var frame_width = raw_img.get_width() / 4
	var frame_img = raw_img.get_region(Rect2i(0, 0, frame_width, raw_img.get_height()))
	
	# Tint them green to make "little green men"
	var green_tint = Color("#55ff55")
	for x in range(frame_img.get_width()):
		for y in range(frame_img.get_height()):
			var c = frame_img.get_pixel(x, y)
			if c.a > 0.1:
				frame_img.set_pixel(x, y, c * green_tint)
				
	texture = ImageTexture.create_from_image(frame_img)
	
	positions.resize(max_enemies)
	velocities.resize(max_enemies)
	healths.resize(max_enemies)
	
	for i in range(max_enemies):
		multimesh.set_instance_transform_2d(i, Transform2D(0, Vector2(-5000, -5000)))

func spawn_enemy(pos: Vector2):
	if active_count < max_enemies:
		positions[active_count] = pos
		velocities[active_count] = Vector2.ZERO
		healths[active_count] = 10.0
		active_count += 1

func _physics_process(delta):
	if not flow_field: return
	
	_update_spatial_grid()
	
	var task_id = WorkerThreadPool.add_group_task(_update_enemy_batch.bind(delta), active_count, 64)
	WorkerThreadPool.wait_for_group_task_completion(task_id)
	
	for i in range(active_count):
		var t = Transform2D(velocities[i].angle(), positions[i])
		multimesh.set_instance_transform_2d(i, t)
		
		if positions[i].x > 1950.0: # Exit screen right
			GlobalEvents.nexus_damaged.emit(1)
			_remove_enemy(i)

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
	var offsets = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]
	for off in offsets:
		var check_pos = tile_pos + off
		if check_pos.x >= 0 and check_pos.x < flow_field.grid_size.x and check_pos.y >= 0 and check_pos.y < flow_field.grid_size.y:
			if flow_field.obstacle_field[check_pos.x][check_pos.y]:
				var wall_center = Vector2(check_pos) * 32.0 + Vector2(16, 16)
				var dist_sq_wall = pos.distance_squared_to(wall_center)
				if dist_sq_wall < 1024: # 32px radius
					wall_push += (pos - wall_center).normalized() * (1.0 - (dist_sq_wall / 1024.0))
	
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
	dir = (dir + separation + wall_push * 2.0).normalized()
	
	velocities[i] = velocities[i].lerp(dir * enemy_speed, 4.0 * delta)
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
