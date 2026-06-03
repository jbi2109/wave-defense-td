extends Node2D
class_name TurretPlacementManager

const TURRET_PREFAB = preload("res://prefabs/turret.tscn")

var selected_type: String = ""
var ghost_instance: Node2D = null

enum PlacementState { NONE, PLACING_BASE, SETTING_CONE }
var current_state: PlacementState = PlacementState.NONE
var base_placement_pos: Vector2 = Vector2.ZERO
var current_cone_center: float = 0.0
var current_cone_width: float = TAU

var _left_mouse_was_down := false
var _editing_existing_turret: Turret = null

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

func start_placement(type: String):
	if not _can_place():
		return
	cancel_placement()
	
	selected_type = type
	current_state = PlacementState.PLACING_BASE
	var t_def = get_definition(type)
	if not t_def:
		return
		
	var s = t_def.scale
	var tex_path = t_def.sprite_path
	if tex_path == "":
		return
		
	ghost_instance = Node2D.new()
	ghost_instance.z_index = 10
	
	var base_sprite = Sprite2D.new()
	base_sprite.texture = load("res://assets/turrets/base.png")
	base_sprite.scale = Vector2(s, s)
	if type == "slow":
		pass
	elif type == "generator":
		base_sprite.self_modulate = Color(1.0, 0.8, 0.2, 1.0)
	
	var gun_sprite = Sprite2D.new()
	if tex_path.begins_with("res://Assets"):
		tex_path = tex_path.replace("res://Assets", "res://assets")
	gun_sprite.texture = load(tex_path)
	gun_sprite.scale = Vector2(s, s)
	
	ghost_instance.add_child(base_sprite)
	ghost_instance.add_child(gun_sprite)
	
	get_parent().add_child(ghost_instance)

func cancel_placement():
	if _editing_existing_turret:
		_editing_existing_turret = null
		ghost_instance = null
	selected_type = ""
	current_state = PlacementState.NONE
	if ghost_instance:
		ghost_instance.queue_free()
		ghost_instance = null
	queue_redraw()

func _can_place() -> bool:
	if not wave_manager:
		return true
	return wave_manager.current_wave == 0 or wave_manager.is_inter_wave

func _process(_delta):
	var mouse_pos = get_global_mouse_position()
	
	var left_mouse_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var left_mouse_just_pressed = left_mouse_down and not _left_mouse_was_down
	_left_mouse_was_down = left_mouse_down
	
	if selected_type == "" or current_state == PlacementState.NONE:
		if left_mouse_just_pressed and _can_place() and mouse_pos.y < 900:
			var turrets = get_tree().get_nodes_in_group("turret")
			for t in turrets:
				if is_instance_valid(t) and t.global_position.distance_squared_to(mouse_pos) < 28.0 * 28.0:
					selected_type = t.turret_type
					current_state = PlacementState.SETTING_CONE
					base_placement_pos = t.global_position
					current_cone_center = t.cone_center
					current_cone_width = t.cone_width
					ghost_instance = t
					_editing_existing_turret = t
					break
		return
		
	if not _can_place():
		cancel_placement()
		return
		
	queue_redraw()
	
	if current_state == PlacementState.PLACING_BASE:
		var cell_size = 32.0
		var grid_x = floor(mouse_pos.x / cell_size)
		var grid_y = floor(mouse_pos.y / cell_size)
		var snap_pos = Vector2(grid_x, grid_y) * cell_size + Vector2(16.0, 16.0)
		
		if ghost_instance:
			ghost_instance.global_position = snap_pos
			ghost_instance.get_child(1).rotation = 0.0
			
			var valid = _is_position_valid(snap_pos)
			if valid:
				ghost_instance.modulate = Color(0.3, 1.0, 0.3, 0.6)
			else:
				ghost_instance.modulate = Color(1.0, 0.3, 0.3, 0.6)
				
			if left_mouse_just_pressed or Input.is_action_just_pressed("ui_accept"):
				if mouse_pos.y < 900:
					if valid:
						var cost = get_turret_cost(selected_type)
						if Globals.gold >= cost:
							base_placement_pos = snap_pos
							current_state = PlacementState.SETTING_CONE
							ghost_instance.modulate = Color(1.0, 1.0, 1.0, 0.8)
						else:
							print("Not enough gold!")
							
	elif current_state == PlacementState.SETTING_CONE:
		var dist = base_placement_pos.distance_to(mouse_pos)
		current_cone_center = (mouse_pos - base_placement_pos).angle()
		
		var max_width = PI 
		var min_width = PI / 8.0
		var dist_clamped = clamp(dist, 32.0, 300.0)
		var t = (dist_clamped - 32.0) / (300.0 - 32.0)
		current_cone_width = lerp(max_width, min_width, t)
		
		if ghost_instance:
			ghost_instance.global_position = base_placement_pos
			if ghost_instance.has_node("GunSprite"):
				ghost_instance.get_node("GunSprite").rotation = current_cone_center
			else:
				ghost_instance.rotation = current_cone_center
			
		if left_mouse_just_pressed or Input.is_action_just_pressed("ui_accept"):
			if mouse_pos.y < 900:
				if _editing_existing_turret:
					_editing_existing_turret.cone_center = current_cone_center
					_editing_existing_turret.cone_width = current_cone_width
					if is_instance_valid(enemy_manager) and enemy_manager.has_method("update_turret"):
						enemy_manager.update_turret(_editing_existing_turret)
					
					_editing_existing_turret = null
					ghost_instance = null
					selected_type = ""
					current_state = PlacementState.NONE
				else:
					var cost = get_turret_cost(selected_type)
					if Globals.spend_gold(cost):
						_place_turret(base_placement_pos, current_cone_center, current_cone_width)
						cancel_placement()
					else:
						cancel_placement()
					
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if selected_type != "":
			SoundManager.play_sfx("sell")
		cancel_placement()

func _draw():
	if current_state == PlacementState.SETTING_CONE:
		var t_def = get_definition(selected_type)
		if t_def:
			var r = t_def.attack_range
			var p1 = base_placement_pos + Vector2.RIGHT.rotated(current_cone_center - current_cone_width / 2.0) * r
			var p2 = base_placement_pos + Vector2.RIGHT.rotated(current_cone_center + current_cone_width / 2.0) * r
			
			var local_base = to_local(base_placement_pos)
			var local_p1 = to_local(p1)
			var local_p2 = to_local(p2)
			
			draw_line(local_base, local_p1, Color(0.0, 1.0, 1.0, 0.5), 2.0)
			draw_line(local_base, local_p2, Color(0.0, 1.0, 1.0, 0.5), 2.0)
			
			var points = PackedVector2Array()
			var segments = 32
			for i in range(segments + 1):
				var a = (current_cone_center - current_cone_width / 2.0) + current_cone_width * float(i) / float(segments)
				points.append(to_local(base_placement_pos + Vector2.RIGHT.rotated(a) * r))
			for i in range(segments):
				draw_line(points[i], points[i+1], Color(0.0, 1.0, 1.0, 0.5), 2.0)
				
			var local_mouse = to_local(get_global_mouse_position())
			draw_line(local_base, local_mouse, Color(0.0, 1.0, 1.0, 0.2), 1.0)

func _is_position_valid(pos: Vector2) -> bool:
	if not flow_field:
		return false
		
	var cell_size = float(flow_field.cell_size)
	var offset = flow_field.grid_offset
	var tx = int(floor(pos.x / cell_size)) - offset.x
	var ty = int(floor(pos.y / cell_size)) - offset.y
	
	if tx < 0 or tx >= flow_field.grid_size.x or ty < 0 or ty >= flow_field.grid_size.y:
		return false
		
	if not flow_field.obstacle_field[tx][ty]:
		return false
		
	var turrets = get_tree().get_nodes_in_group("turret")
	for t in turrets:
		if is_instance_valid(t) and t != ghost_instance:
			if t.global_position.distance_squared_to(pos) < 28.0 * 28.0:
				return false
				
	return true

func _place_turret(pos: Vector2, cone_center: float, cone_width: float):
	var turret = TURRET_PREFAB.instantiate()
	turret.global_position = pos
	turret.turret_type = selected_type
	turret.cone_center = cone_center
	turret.cone_width = cone_width
	get_parent().add_child(turret)
	GlobalEvents.turret_placed.emit(selected_type, pos)
	SoundManager.play_sfx("build")
	print("Placed turret: ", selected_type, " at ", pos)

func _on_wave_started(_wave_num: int, _enemy_count: int):
	cancel_placement()
