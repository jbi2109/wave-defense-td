extends Node2D
class_name TurretPlacementManager

const TURRET_PREFAB = preload("res://prefabs/turret.tscn")
const RangeIndicatorScript = preload("res://scripts/range_indicator.gd")

var selected_type: String = ""
var ghost_instance: Sprite2D = null
var range_indicator: Node2D = null

@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var wave_manager: WaveManager = get_node("../WaveManager")

var definitions := {}

func _ready():
	GlobalEvents.wave_started.connect(_on_wave_started)
	for child in get_children():
		if child.get_script() != null and "turret_definition" in child.get_script().resource_path:
			definitions[child.turret_type] = child

func get_definition(type: String) -> Node:
	return definitions.get(type, null)

func get_turret_cost(type: String) -> int:
	var t_def = get_definition(type)
	if t_def:
		return t_def.cost
	return 0

func _exit_tree():
	if ghost_instance:
		ghost_instance.queue_free()
	if range_indicator:
		range_indicator.queue_free()

func start_placement(type: String):
	if not _can_place():
		return
	cancel_placement()
	
	selected_type = type
	var t_def = get_definition(type)
	if not t_def:
		return
		
	var s = t_def.scale
	var tex_path = t_def.sprite_path
	if tex_path == "":
		return
		
	ghost_instance = Sprite2D.new()
	ghost_instance.z_index = 10
	
	# Load sprite
	if tex_path.begins_with("res://Assets"):
		tex_path = tex_path.replace("res://Assets", "res://assets")
	ghost_instance.texture = load(tex_path)
	
	ghost_instance.scale = Vector2(s, s)
	if type == "slow":
		ghost_instance.self_modulate = Color(0.2, 0.7, 1.0, 1.0)
	
	# Add to main scene
	get_parent().add_child(ghost_instance)
	
	# Create range indicator
	range_indicator = RangeIndicatorScript.new()
	range_indicator.radius = t_def.attack_range
	range_indicator.fill_color = Color(0.2, 0.8, 0.2, 0.12)
	range_indicator.line_color = Color(0.2, 0.8, 0.2, 0.45)
	range_indicator.z_index = 9
	get_parent().add_child(range_indicator)

func cancel_placement():
	selected_type = ""
	if ghost_instance:
		ghost_instance.queue_free()
		ghost_instance = null
	if range_indicator:
		range_indicator.queue_free()
		range_indicator = null

func _can_place() -> bool:
	if not wave_manager:
		return true
	return wave_manager.current_wave == 0 or wave_manager.is_inter_wave

func _process(_delta):
	if selected_type == "":
		return
		
	if not _can_place():
		cancel_placement()
		return
		
	# Follow mouse snapped to grid
	var mouse_pos = get_global_mouse_position()
	var cell_size = 32.0
	var grid_x = floor(mouse_pos.x / cell_size)
	var grid_y = floor(mouse_pos.y / cell_size)
	var snap_pos = Vector2(grid_x, grid_y) * cell_size + Vector2(16.0, 16.0)
	
	if ghost_instance:
		ghost_instance.global_position = snap_pos
		
		# Validation
		var valid = _is_position_valid(snap_pos)
		if valid:
			ghost_instance.modulate = Color(0.3, 1.0, 0.3, 0.6) # Translucent green
		else:
			ghost_instance.modulate = Color(1.0, 0.3, 0.3, 0.6) # Translucent red
			
		if range_indicator:
			range_indicator.global_position = snap_pos
			if valid:
				range_indicator.fill_color = Color(0.2, 0.8, 0.2, 0.12)
				range_indicator.line_color = Color(0.2, 0.8, 0.2, 0.45)
			else:
				range_indicator.fill_color = Color(1.0, 0.2, 0.2, 0.12)
				range_indicator.line_color = Color(1.0, 0.2, 0.2, 0.45)
			
		# Input handle
		if Input.is_action_just_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# Prevent clicking HUD buttons from triggering build
			# (Simple check: mouse y should be above the build bar)
			if mouse_pos.y < 900:
				if valid:
					var cost = get_turret_cost(selected_type)
					if Globals.spend_gold(cost):
						_place_turret(snap_pos)
						cancel_placement()
					else:
						print("Not enough gold!")
						
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if selected_type != "":
				SoundManager.play_sfx("sell")
			cancel_placement()

func _is_position_valid(pos: Vector2) -> bool:
	if not flow_field:
		return false
		
	# Grid bounds
	var cell_size = float(flow_field.cell_size)
	var offset = flow_field.grid_offset
	var tx = int(floor(pos.x / cell_size)) - offset.x
	var ty = int(floor(pos.y / cell_size)) - offset.y
	
	if tx < 0 or tx >= flow_field.grid_size.x or ty < 0 or ty >= flow_field.grid_size.y:
		return false
		
	# Must be an obstacle (i.e. dirt/unwalkable background, not path)
	if not flow_field.obstacle_field[tx][ty]:
		return false
		
	# Must not overlap existing turret
	var turrets = get_tree().get_nodes_in_group("turret")
	for t in turrets:
		if is_instance_valid(t) and t != ghost_instance:
			if t.global_position.distance_squared_to(pos) < 28.0 * 28.0:
				return false
				
	return true

func _place_turret(pos: Vector2):
	var turret = TURRET_PREFAB.instantiate()
	turret.global_position = pos
	turret.turret_type = selected_type
	get_parent().add_child(turret)
	GlobalEvents.turret_placed.emit(selected_type, pos)
	SoundManager.play_sfx("build")
	print("Placed turret: ", selected_type, " at ", pos)

func _on_wave_started(_wave_num: int, _enemy_count: int):
	cancel_placement()
