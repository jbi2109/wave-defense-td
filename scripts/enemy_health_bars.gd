extends Node2D
class_name EnemyHealthBars

@onready var enemy_manager: EnemyManager = get_node("../EnemyManager")

var boss_progress_bar: ProgressBar = null
var boss_label: Label = null

func _ready():
	# Find Boss HUD elements under HUD/Overlay
	var hud_overlay = get_node_or_null("../HUD/Overlay")
	if hud_overlay:
		boss_progress_bar = hud_overlay.get_node_or_null("BossProgressBar")
		boss_label = hud_overlay.get_node_or_null("BossLabel")
		
	if boss_progress_bar:
		boss_progress_bar.visible = false
	if boss_label:
		boss_label.visible = false

func _process(_delta):
	queue_redraw()
	_update_boss_hud()

func _draw():
	if not enemy_manager or enemy_manager.active_count == 0:
		return
		
	var active_count = enemy_manager.active_count
	var positions = enemy_manager.positions
	var healths = enemy_manager.healths
	var max_healths = enemy_manager.max_healths
	var types = enemy_manager.types
	var type_scales = enemy_manager.type_scales
	
	for i in range(active_count):
		var hp = healths[i]
		if is_nan(hp) or hp <= 0.0:
			continue
			
		var max_hp = max_healths[i]
		if is_nan(max_hp) or max_hp <= 0.0:
			continue
			
		var ratio = clampf(hp / max_hp, 0.0, 1.0)
		if is_nan(ratio) or is_inf(ratio):
			continue
			
		var t = types[i]
		var is_boss_type = enemy_manager.type_is_boss[t]
		
		# Draw only if boss or damaged
		if is_boss_type or ratio < 1.0:
			var scale_val = type_scales[t]
			var size_w = 32.0 * scale_val
			var size_h = 4.0
			
			# Offset above enemy head
			var draw_pos = positions[i] + Vector2(-size_w / 2.0, -18.0 * scale_val)
			
			# Draw background (black border)
			draw_rect(Rect2(draw_pos + Vector2(-1, -1), Vector2(size_w + 2, size_h + 2)), Color(0, 0, 0, 0.8))
			
			# Draw filled portion
			var color = Color(0.8, 0.2, 0.2) # Red
			if ratio > 0.5:
				color = Color(0.2, 0.8, 0.2) # Green
			elif ratio > 0.25:
				color = Color(0.8, 0.8, 0.2) # Yellow
				
			draw_rect(Rect2(draw_pos, Vector2(size_w * ratio, size_h)), color)

func _update_boss_hud():
	if not enemy_manager or enemy_manager.active_count == 0 or enemy_manager.active_boss_count == 0:
		_hide_boss_hud()
		return
		
	var active_count = enemy_manager.active_count
	var healths = enemy_manager.healths
	var max_healths = enemy_manager.max_healths
	var types = enemy_manager.types
	
	var total_boss_hp = 0.0
	var total_boss_max_hp = 0.0
	var last_boss_name = "Boss"
	var boss_count = 0
	
	for i in range(active_count):
		var t = types[i]
		if enemy_manager.type_is_boss[t]:
			total_boss_hp += healths[i]
			total_boss_max_hp += max_healths[i]
			last_boss_name = enemy_manager.type_names[t]
			boss_count += 1
			
	if boss_count > 0 and total_boss_max_hp > 0.0:
		if boss_progress_bar:
			boss_progress_bar.visible = true
			boss_progress_bar.value = (total_boss_hp / total_boss_max_hp) * 100.0
		if boss_label:
			boss_label.visible = true
			if boss_count > 1:
				boss_label.text = "%s (%d remaining)" % [last_boss_name, boss_count]
			else:
				boss_label.text = last_boss_name
	else:
		_hide_boss_hud()

func _hide_boss_hud():
	if boss_progress_bar:
		boss_progress_bar.visible = false
	if boss_label:
		boss_label.visible = false
