extends Node2D
class_name TurretPlacementManager

const TURRET_PREFAB = preload("res://prefabs/turret.tscn")

var selected_type: String = ""
var ghost_instance: Sprite2D = nil

@onready var flow_field: FlowFieldManager = get_node("../FlowFieldManager")
@onready var wave_manager: WaveManager = get_node("../WaveManager")

func _ready():
	GlobalEvents.wave_started.connect(_on_wave_started)

func _exit_tree():
	if ghost_instance:
		ghost_instance.queue_free()

func start_placement(type: String):
	if not _can_place():
		return
	cancel_placement()
	
	selected_type = type
	if not Data.turrets.has(type):
		return
		
	var def = Data.turrets[type]
	ghost_instance = Sprite2D.new()
	ghost_instance.z_index = 10
	
	# Load sprite
	var tex_path = def.sprite
	if tex_path.begins_with("res://Assets"):
		tex_path = tex_path.replace("res://Assets", "res://assets")
	ghost_instance.texture = load(tex_path)
	
	var s = def.get("scale", 1.0)
	ghost_instance.scale = Vector2(s, s)
	
	# Add to main scene
	get_parent().add_child(ghost_instance)

func cancel_placement():
	selected_type = ""
	if ghost_instance:
		ghost_instance.queue_free()
		ghost_instance = nil

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
			
		# Input handle
		if Input.is_action_just_pressed("ui_accept") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# Prevent clicking HUD buttons from triggering build
			# (Simple check: mouse y should be above the build bar)
			if mouse_pos.y < 900:
				if valid:
					var cost = Data.turrets[selected_type].get("cost", 0)
					if Globals.spend_gold(cost):
						_place_turret(snap_pos)
						cancel_placement()
					else:
						print("Not enough gold!")
						
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
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
	print("Placed turret: ", selected_type, " at ", pos)

func _on_wave_started(_wave_num: int, _enemy_count: int):
	cancel_placement()
