extends Control
class_name HUDBuildMenu

@onready var placement_manager: TurretPlacementManager = get_node("../../../TurretPlacementManager")
@onready var wave_manager: WaveManager = get_node("../../../WaveManager")

# --- UI References ---
var build_bar: PanelContainer
var build_hbox: HBoxContainer

var upgrade_panel: PanelContainer
var upgrade_title: Label
var upgrade_stats: Label
var upgrade_btn: Button
var sell_btn: Button
var target_mode_option: OptionButton

const RangeIndicatorScript = preload("res://scripts/range_indicator.gd")

var selected_turret: Turret = null
var selection_indicator: Node2D = null

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if get_parent() is Control:
		get_parent().mouse_filter = Control.MOUSE_FILTER_IGNORE
		
	_create_ui_nodes()
	_populate_build_menu()
	
	# Connect events
	GlobalEvents.gold_changed.connect(_on_gold_changed)
	GlobalEvents.wave_started.connect(_on_wave_started)
	GlobalEvents.wave_cleared.connect(_on_wave_cleared)
	
	upgrade_panel.visible = false
	_update_build_bar_visibility()

func _create_ui_nodes():
	# 1. Build Bar at bottom center
	build_bar = PanelContainer.new()
	build_bar.name = "BuildBar"
	build_bar.anchor_left = 0.5
	build_bar.anchor_right = 0.5
	build_bar.anchor_top = 1.0
	build_bar.anchor_bottom = 1.0
	build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.offset_bottom = -20
	build_bar.offset_top = -100
	build_bar.offset_left = -250
	build_bar.offset_right = 250
	
	# Add style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.16, 0.85) # Sleek slate-dark
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	build_bar.add_theme_stylebox_override("panel", style)
	
	build_hbox = HBoxContainer.new()
	build_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	build_hbox.add_theme_constant_override("separation", 15)
	build_bar.add_child(build_hbox)
	add_child(build_bar)
	
	# 2. Upgrade Panel on the left side
	upgrade_panel = PanelContainer.new()
	upgrade_panel.name = "UpgradePanel"
	upgrade_panel.anchor_left = 0.0
	upgrade_panel.anchor_right = 0.0
	upgrade_panel.anchor_top = 1.0
	upgrade_panel.anchor_bottom = 1.0
	upgrade_panel.grow_horizontal = Control.GROW_DIRECTION_END
	upgrade_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	upgrade_panel.offset_left = 20
	upgrade_panel.offset_bottom = -120
	upgrade_panel.offset_top = -370
	upgrade_panel.offset_right = 320
	
	var up_style = StyleBoxFlat.new()
	up_style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	up_style.corner_radius_top_left = 8
	up_style.corner_radius_top_right = 8
	up_style.corner_radius_bottom_left = 8
	up_style.corner_radius_bottom_right = 8
	up_style.border_width_left = 2
	up_style.border_width_right = 2
	up_style.border_width_top = 2
	up_style.border_width_bottom = 2
	up_style.border_color = Color(0.4, 0.4, 0.45, 0.6)
	upgrade_panel.add_theme_stylebox_override("panel", up_style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	upgrade_title = Label.new()
	upgrade_title.text = "Turret Info"
	upgrade_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_title.add_theme_font_size_override("font_size", 20)
	upgrade_title.add_theme_color_override("font_color", Color(1, 0.85, 0.4)) # Gold text
	vbox.add_child(upgrade_title)
	
	upgrade_stats = Label.new()
	upgrade_stats.text = "Damage: 5\nRange: 200\nSpeed: 5/s"
	vbox.add_child(upgrade_stats)
	
	# Target Mode Selection
	var mode_label = Label.new()
	mode_label.text = "Target Mode:"
	vbox.add_child(mode_label)
	
	target_mode_option = OptionButton.new()
	target_mode_option.add_item("Closest", 0)
	target_mode_option.add_item("Strongest", 1)
	target_mode_option.add_item("First", 2)
	target_mode_option.add_item("Last", 3)
	target_mode_option.item_selected.connect(_on_target_mode_selected)
	vbox.add_child(target_mode_option)
	
	# Upgrade Button
	upgrade_btn = Button.new()
	upgrade_btn.text = "Upgrade ($50)"
	upgrade_btn.pressed.connect(_on_upgrade_pressed)
	vbox.add_child(upgrade_btn)
	
	# Sell Button
	sell_btn = Button.new()
	sell_btn.text = "Sell (+$30)"
	sell_btn.pressed.connect(_on_sell_pressed)
	# Reddish sell button style
	var red_style = StyleBoxFlat.new()
	red_style.bg_color = Color(0.5, 0.15, 0.15, 0.8)
	red_style.corner_radius_top_left = 4
	red_style.corner_radius_top_right = 4
	red_style.corner_radius_bottom_left = 4
	red_style.corner_radius_bottom_right = 4
	sell_btn.add_theme_stylebox_override("normal", red_style)
	vbox.add_child(sell_btn)
	
	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(hide_upgrade_panel)
	vbox.add_child(close_btn)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	margin.add_child(vbox)
	
	upgrade_panel.add_child(margin)
	add_child(upgrade_panel)

	# 3. Settings Button at top-left
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(100, 35)
	settings_btn.offset_left = 10
	settings_btn.offset_top = 50
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.22, 0.28, 0.8)
	btn_style.corner_radius_top_left = 4
	btn_style.corner_radius_top_right = 4
	btn_style.corner_radius_bottom_left = 4
	btn_style.corner_radius_bottom_right = 4
	settings_btn.add_theme_stylebox_override("normal", btn_style)
	
	add_child(settings_btn)
	settings_btn.pressed.connect(func():
		var existing = get_node_or_null("SettingsMenu")
		if not existing:
			var sm_scene = load("res://scenes/ui/settings_menu.tscn")
			if sm_scene:
				var sm = sm_scene.instantiate()
				add_child(sm)
	)

func _populate_build_menu():
	# Clear previous
	for child in build_hbox.get_children():
		child.queue_free()
		
	# Populate based on TurretPlacementManager definitions
	if placement_manager:
		for type in placement_manager.definitions.keys():
			var t_def = placement_manager.definitions[type]
			var cost = t_def.cost
			var name_str = t_def.turret_name
			
			var btn = Button.new()
			btn.name = type
			btn.text = "%s\n$%d" % [name_str, cost]
			btn.custom_minimum_size = Vector2(100, 60)
			btn.pressed.connect(func(): _on_build_btn_pressed(type))
			
			# Stylish hover and coloring
			var btn_style = StyleBoxFlat.new()
			btn_style.bg_color = Color(0.18, 0.22, 0.3, 0.9)
			btn_style.corner_radius_top_left = 6
			btn_style.corner_radius_top_right = 6
			btn_style.corner_radius_bottom_left = 6
			btn_style.corner_radius_bottom_right = 6
			btn.add_theme_stylebox_override("normal", btn_style)
			
			build_hbox.add_child(btn)
		
	_update_build_buttons_state()

func _on_build_btn_pressed(type: String):
	if placement_manager:
		placement_manager.start_placement(type)

func _update_build_buttons_state():
	var gold = Globals.gold
	var can_build = _can_place()
	
	for btn in build_hbox.get_children():
		var type = btn.name
		if placement_manager and placement_manager.definitions.has(type):
			var t_def = placement_manager.definitions[type]
			var cost = t_def.cost
			var name_str = t_def.turret_name
			btn.text = "%s\n$%d" % [name_str, cost]
			# Disable if not enough gold or not in inter-wave phase
			btn.disabled = (gold < cost) or not can_build

func _can_place() -> bool:
	if not wave_manager:
		return true
	return wave_manager.current_wave == 0 or wave_manager.is_inter_wave

func _update_build_bar_visibility():
	var can_build = _can_place()
	build_bar.visible = can_build
	_update_build_buttons_state()

func show_upgrade_panel(turret: Turret):
	if selection_indicator:
		selection_indicator.queue_free()
		selection_indicator = null
		
	selected_turret = turret
	upgrade_panel.visible = true
	
	selection_indicator = RangeIndicatorScript.new()
	selection_indicator.radius = turret.attack_range
	selection_indicator.global_position = turret.global_position
	selection_indicator.fill_color = Color(0.2, 0.6, 1.0, 0.08)
	selection_indicator.line_color = Color(0.2, 0.6, 1.0, 0.35)
	selection_indicator.z_index = 8
	get_node("/root/Main").add_child(selection_indicator)
	
	_update_upgrade_panel_content()

func hide_upgrade_panel():
	selected_turret = null
	upgrade_panel.visible = false
	if selection_indicator:
		selection_indicator.queue_free()
		selection_indicator = null

func _update_upgrade_panel_content():
	if not is_instance_valid(selected_turret):
		hide_upgrade_panel()
		return
		
	var type = selected_turret.turret_type
	var t_def = selected_turret.get_definition()
	var name_str = t_def.turret_name if t_def else type.capitalize()
	
	upgrade_title.text = "%s (Lvl %d)" % [name_str, selected_turret.current_level]
	
	var is_max = selected_turret.is_max_level()
	var dmg_val = selected_turret.damage
	var range_val = selected_turret.attack_range
	var speed_val = 1.0 / selected_turret.fire_rate
	
	if selection_indicator:
		selection_indicator.radius = range_val
		selection_indicator.global_position = selected_turret.global_position
	
	var stats_text = "Damage: %.1f\nRange: %d\nSpeed: %.1f/s" % [dmg_val, range_val, speed_val]
	upgrade_stats.text = stats_text
	
	# Set current target mode
	target_mode_option.selected = selected_turret.target_mode
	
	if is_max:
		upgrade_btn.text = "Max Level"
		upgrade_btn.disabled = true
	else:
		var cost = selected_turret.get_upgrade_cost()
		upgrade_btn.text = "Upgrade ($%d)" % cost
		upgrade_btn.disabled = Globals.gold < cost
		
	var sell_val = int(selected_turret.total_spent * 0.6)
	sell_btn.text = "Sell (+$%d)" % sell_val



func _on_upgrade_pressed():
	if is_instance_valid(selected_turret):
		if selected_turret.upgrade():
			_update_upgrade_panel_content()

func _on_sell_pressed():
	if is_instance_valid(selected_turret):
		selected_turret.sell()
		hide_upgrade_panel()

func _on_target_mode_selected(index: int):
	if is_instance_valid(selected_turret):
		selected_turret.target_mode = index as Turret.TargetMode

func _on_gold_changed(_new_amount: int):
	_update_build_buttons_state()
	if upgrade_panel.visible:
		_update_upgrade_panel_content()

func _on_wave_started(_wave_num: int, _enemy_count: int):
	hide_upgrade_panel()
	_update_build_bar_visibility()

func _on_wave_cleared(_wave_num: int):
	_update_build_bar_visibility()

# Detect click on existing turrets
func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var existing = get_node_or_null("SettingsMenu")
		if existing:
			existing._on_close_pressed()
		else:
			var sm_scene = load("res://scenes/ui/settings_menu.tscn")
			if sm_scene:
				var sm = sm_scene.instantiate()
				add_child(sm)
				get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var ability_mgr = get_node_or_null("/root/Main/AbilityManager")
		if ability_mgr and ability_mgr.active_ability_index != -1:
			return
			
		var click_pos = get_global_mouse_position()
		var clicked_turret: Turret = null
		
		var turrets = get_tree().get_nodes_in_group("turret")
		for t in turrets:
			if is_instance_valid(t):
				if t.global_position.distance_to(click_pos) < 24.0:
					clicked_turret = t
					break
					
		if clicked_turret:
			show_upgrade_panel(clicked_turret)
		else:
			# If placing, let PlacementManager handle it. Otherwise close panel.
			if placement_manager.selected_type == "":
				hide_upgrade_panel()
