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
	pass

func _update_boss_hud():
	_hide_boss_hud()

func _hide_boss_hud():
	if boss_progress_bar:
		boss_progress_bar.visible = false
	if boss_label:
		boss_label.visible = false
