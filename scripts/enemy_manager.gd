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
	multimesh.mesh.size = Vector2(32, 32)
	multimesh.instance_count = max_enemies
	
	texture = load("res://assets/enemies/dino1.png")
	
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
		
		if positions[i].distance_squared_to(nexus.global_position) < 2500: # 50px
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
