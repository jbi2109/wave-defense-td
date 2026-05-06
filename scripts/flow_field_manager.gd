extends Node2D
class_name FlowFieldManager

@export var grid_size: Vector2i = Vector2i(40, 40)
@export var cell_size: int = 32

var grid = [] # 2D array of Vector2 directions
var cost_field = [] # 2D array of integers

func _ready():
    _init_fields()

func _init_fields():
    grid.clear()
    cost_field.clear()
    for x in range(grid_size.x):
        grid.append([])
        cost_field.append([])
        for y in range(grid_size.y):
            grid[x].append(Vector2.ZERO)
            cost_field[x].append(65535) # Max value for Dijkstra

func generate_field(target_pos: Vector2):
    _init_fields()
    
    var target_grid_pos = Vector2i(target_pos / float(cell_size))
    target_grid_pos.x = clamp(target_grid_pos.x, 0, grid_size.x - 1)
    target_grid_pos.y = clamp(target_grid_pos.y, 0, grid_size.y - 1)
    
    # 1. Dijkstra Pass
    var queue = [target_grid_pos]
    cost_field[target_grid_pos.x][target_grid_pos.y] = 0
    
    while queue.size() > 0:
        var current = queue.pop_front()
        var current_cost = cost_field[current.x][current.y]
        
        for neighbor in _get_neighbors(current):
            if cost_field[neighbor.x][neighbor.y] > current_cost + 1:
                cost_field[neighbor.x][neighbor.y] = current_cost + 1
                queue.push_back(neighbor)
    
    # 2. Vector Field Pass
    for x in range(grid_size.x):
        for y in range(grid_size.y):
            var min_cost = cost_field[x][y]
            var best_neighbor = Vector2i(x, y)
            
            for neighbor in _get_neighbors(Vector2i(x, y)):
                if cost_field[neighbor.x][neighbor.y] < min_cost:
                    min_cost = cost_field[neighbor.x][neighbor.y]
                    best_neighbor = neighbor
            
            if best_neighbor != Vector2i(x, y):
                grid[x][y] = (Vector2(best_neighbor) - Vector2(x, y)).normalized()

func _get_neighbors(pos: Vector2i) -> Array[Vector2i]:
    var neighbors: Array[Vector2i] = []
    var dirs = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),
                Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
    for d in dirs:
        var n = pos + d
        if n.x >= 0 and n.x < grid_size.x and n.y >= 0 and n.y < grid_size.y:
            neighbors.append(n)
    return neighbors

func get_direction(world_pos: Vector2) -> Vector2:
    var x = int(world_pos.x / cell_size)
    var y = int(world_pos.y / cell_size)
    if x >= 0 and x < grid_size.x and y >= 0 and y < grid_size.y:
        return grid[x][y]
    return Vector2.ZERO
