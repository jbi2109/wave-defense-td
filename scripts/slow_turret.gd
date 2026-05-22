extends Turret
class_name SlowTurret

@export var slow_factor: float = 0.4  ## Scale speed by 40% (60% slow)

func _fire(p_target_idx: int):
	if not enemy_manager:
		return
		
	var targets = enemy_manager.get_nearby_enemies(global_position, attack_range)
	for idx in targets:
		if idx >= 0 and idx < enemy_manager.active_count:
			# Apply the slow factor (the lower value is stronger slow)
			enemy_manager.speed_modifiers[idx] = minf(enemy_manager.speed_modifiers[idx], slow_factor)
			enemy_manager.damage_enemy(idx, damage)
			
	# Spawn visual tracer to the main target
	var tracer_scene = load("res://scripts/bullet_tracer.gd")
	var tracer = Node2D.new()
	tracer.set_script(tracer_scene)
	
	var m_pos = global_position
	if has_node("Muzzle"):
		m_pos = $Muzzle.global_position
		
	var target_pos = enemy_manager.positions[p_target_idx]
	get_parent().add_child(tracer)
	tracer.global_position = global_position
	tracer.init(m_pos, target_pos, Color(0.1, 0.7, 1.0, 0.9), 4.0) # Ice cyan tracer
