extends Sprite2D

@export var attack_range: float = 300.0
@export var fire_rate: float = 0.2
@onready var enemy_manager: Node2D = get_node("../EnemyManager")

var fire_timer: float = 0.0

func _process(delta):
	fire_timer -= delta
	if not enemy_manager: return
	
	var target = _find_closest_enemy()
	if target:
		look_at(target.global_position)
		
		if fire_timer <= 0:
			_fire(target)
			fire_timer = fire_rate

func _find_closest_enemy() -> Node2D:
	var closest_enemy = null
	var min_dist_sq = attack_range * attack_range
	
	for enemy in enemy_manager.get_children():
		if enemy.is_queued_for_deletion():
			continue
		var dist_sq = global_position.distance_squared_to(enemy.global_position)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_enemy = enemy
			
	return closest_enemy

func _fire(target: Node2D):
	if target.has_method("take_damage"):
		target.take_damage(5.0)
