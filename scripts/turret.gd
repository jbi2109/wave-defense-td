extends Sprite2D

@export var attack_range: float = 300.0
@export var fire_rate: float = 0.2
@onready var enemy_manager: EnemyManager = get_node("../EnemyManager")

var fire_timer: float = 0.0

func _process(delta):
    fire_timer -= delta
    if not enemy_manager: return
    
    var target_idx = _find_closest_enemy()
    if target_idx != -1:
        var target_pos = enemy_manager.positions[target_idx]
        look_at(target_pos)
        
        if fire_timer <= 0:
            _fire(target_idx)
            fire_timer = fire_rate

func _find_closest_enemy() -> int:
    var closest_idx = -1
    var min_dist_sq = attack_range * attack_range
    
    # Use spatial partitioning
    var nearby_enemies = enemy_manager.get_nearby_enemies(global_position, attack_range)
    
    for i in nearby_enemies:
        var dist_sq = global_position.distance_squared_to(enemy_manager.positions[i])
        if dist_sq < min_dist_sq:
            min_dist_sq = dist_sq
            closest_idx = i
            
    return closest_idx

func _fire(target_idx):
    # For prototype: direct health reduction
    enemy_manager.healths[target_idx] -= 5.0
    if enemy_manager.healths[target_idx] <= 0:
        enemy_manager._remove_enemy(target_idx)
    
    # Visual tracer (optional placeholder)
    print("Turret FIRE at enemy ", target_idx)
