extends Node2D
class_name FlowFieldManager

@export var grid_size: Vector2i = Vector2i(100, 60) # Expand to fit 1920x1080
@export var cell_size: int = 32
@export var grid_offset: Vector2i = Vector2i(-10, -10)

var grid = [] # 2D array of Vector2 directions
var cost_field = [] # 2D array of integers
var obstacle_field = [] # 2D array of bools (true = blocked)

@export var build_layer: TileMapLayer

func _ready():
	_init_fields()
	scan_layers()

func _init_fields():
	grid.clear()
	cost_field.clear()
	obstacle_field.clear()
	for x in range(grid_size.x):
		grid.append([])
		cost_field.append([])
		obstacle_field.append([])
		for y in range(grid_size.y):
			grid[x].append(Vector2.ZERO)
			cost_field[x].append(65535) # Max value for Dijkstra
			obstacle_field[x].append(false)

func scan_layers():
	if not build_layer:
		return
	
	for x in range(grid_offset.x, grid_offset.x + grid_size.x):
		for y in range(grid_offset.y, grid_offset.y + grid_size.y):
			if build_layer.get_cell_source_id(Vector2i(x, y)) != -1:
				set_obstacle(Vector2i(x, y), true)

func set_obstacle(grid_pos: Vector2i, is_obstacle: bool):
	var gp = grid_pos - grid_offset
	if gp.x >= 0 and gp.x < grid_size.x and gp.y >= 0 and gp.y < grid_size.y:
		obstacle_field[gp.x][gp.y] = is_obstacle

func generate_field_for_rect(target_pos: Vector2, extents: Vector2):
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid[x][y] = Vector2.ZERO
			cost_field[x][y] = 65535
	
	var rect = Rect2(target_pos - extents, extents * 2)
	var queue = []
	
	# Find all grid cells that fall within the rect
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var world_pos = Vector2(x + grid_offset.x, y + grid_offset.y) * cell_size + Vector2(cell_size / 2.0, cell_size / 2.0)
			if rect.has_point(world_pos):
				cost_field[x][y] = 0
				queue.push_back(Vector2i(x, y))
	
	# Fallback if the rect is too small to cover any cell centers
	if queue.is_empty():
		var target_grid_pos = Vector2i(target_pos / float(cell_size)) - grid_offset
		target_grid_pos.x = clamp(target_grid_pos.x, 0, grid_size.x - 1)
		target_grid_pos.y = clamp(target_grid_pos.y, 0, grid_size.y - 1)
		cost_field[target_grid_pos.x][target_grid_pos.y] = 0
		queue.push_back(target_grid_pos)
	
	_run_flow_field_passes(queue)

func generate_field(target_pos: Vector2):
	# Don't re-init obstacle field, just cost and grid
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			grid[x][y] = Vector2.ZERO
			cost_field[x][y] = 65535
	
	var target_grid_pos = Vector2i(target_pos / float(cell_size)) - grid_offset
	target_grid_pos.x = clamp(target_grid_pos.x, 0, grid_size.x - 1)
	target_grid_pos.y = clamp(target_grid_pos.y, 0, grid_size.y - 1)
	
	var queue = [target_grid_pos]
	cost_field[target_grid_pos.x][target_grid_pos.y] = 0
	
	_run_flow_field_passes(queue)

func _run_flow_field_passes(queue: Array):
	# 1. Dijkstra Pass
	while queue.size() > 0:
		var current = queue.pop_front()
		var current_cost = cost_field[current.x][current.y]
		
		for neighbor in _get_neighbors(current):
			# Skip obstacles
			if obstacle_field[neighbor.x][neighbor.y]:
				continue
				
			if cost_field[neighbor.x][neighbor.y] > current_cost + 1:
				cost_field[neighbor.x][neighbor.y] = current_cost + 1
				queue.push_back(neighbor)
	
	# 2. Vector Field Pass
	for x in range(grid_size.x):
		for y in range(grid_size.y):
			if obstacle_field[x][y]: continue # No direction in walls
			
			var min_cost = cost_field[x][y]
			var best_neighbor = Vector2i(x, y)
			
			for neighbor in _get_neighbors(Vector2i(x, y)):
				if obstacle_field[neighbor.x][neighbor.y]: continue
				
				if cost_field[neighbor.x][neighbor.y] < min_cost:
					min_cost = cost_field[neighbor.x][neighbor.y]
					best_neighbor = neighbor
			
			if best_neighbor != Vector2i(x, y):
				grid[x][y] = (Vector2(best_neighbor) - Vector2(x, y)).normalized()

func _get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var cardinals = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	for d in cardinals:
		var n = pos + d
		if n.x >= 0 and n.x < grid_size.x and n.y >= 0 and n.y < grid_size.y:
			neighbors.append(n)
			
	var diagonals = [
		{"dir": Vector2i(1, 1), "c1": Vector2i(1, 0), "c2": Vector2i(0, 1)},
		{"dir": Vector2i(1, -1), "c1": Vector2i(1, 0), "c2": Vector2i(0, -1)},
		{"dir": Vector2i(-1, 1), "c1": Vector2i(-1, 0), "c2": Vector2i(0, 1)},
		{"dir": Vector2i(-1, -1), "c1": Vector2i(-1, 0), "c2": Vector2i(0, -1)}
	]
	for d in diagonals:
		var n = pos + d["dir"]
		if n.x >= 0 and n.x < grid_size.x and n.y >= 0 and n.y < grid_size.y:
			var p1 = pos + d["c1"]
			var p2 = pos + d["c2"]
			var valid1 = p1.x >= 0 and p1.x < grid_size.x and p1.y >= 0 and p1.y < grid_size.y
			var valid2 = p2.x >= 0 and p2.x < grid_size.x and p2.y >= 0 and p2.y < grid_size.y
			if valid1 and valid2 and not obstacle_field[p1.x][p1.y] and not obstacle_field[p2.x][p2.y]:
				neighbors.append(n)
	return neighbors

func get_direction(world_pos: Vector2) -> Vector2:
	var grid_pos = Vector2i(world_pos / float(cell_size)) - grid_offset
	if grid_pos.x >= 0 and grid_pos.x < grid_size.x and grid_pos.y >= 0 and grid_pos.y < grid_size.y:
		return grid[grid_pos.x][grid_pos.y]
	return Vector2.ZERO
