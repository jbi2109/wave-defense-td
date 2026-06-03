extends PanelContainer
class_name AbilityLoadout

@onready var close_button = $VBoxContainer/CloseButton
@onready var warning_label = $VBoxContainer/WarningLabel
@onready var items_container = $VBoxContainer/ScrollContainer/ItemsContainer

var ability_details = [
	{
		"name": "Orbital Strike",
		"stats": "50 MP, 5s CD",
		"desc": "Fires a devastating laser beam from space. High damage, large area."
	},
	{
		"name": "Frost Nova",
		"stats": "30 MP, 4s CD",
		"desc": "Triggers an icy blast slowing all enemies by 70% and dealing minor damage."
	},
	{
		"name": "Chain Lightning",
		"stats": "40 MP, 3s CD",
		"desc": "Targets enemy closest to cursor. Bounces to up to 5 nearby enemies."
	},
	{
		"name": "Overdrive",
		"stats": "60 MP, 12s CD",
		"desc": "Supercharges all turrets, increasing their firing speed by 50% for 5 seconds."
	},
	{
		"name": "Acid Pool",
		"stats": "35 MP, 6s CD",
		"desc": "Creates a toxic puddle for 4 seconds dealing continuous damage and slowing by 20%."
	},
	{
		"name": "Dynamite",
		"stats": "25 MP, 4s CD",
		"desc": "Places an explosive that detonates after a short delay, dealing heavy damage to nearby enemies."
	}
]

var selected_set: Dictionary = {}

func _ready():
	var equipped = SaveManager.settings.get("equipped_abilities", ["Orbital Strike", "Frost Nova", "Chain Lightning"])
	for ability_name in equipped:
		selected_set[ability_name] = true
	
	_build_ui()
	_update_state()
	
	if close_button:
		close_button.pressed.connect(_on_close_pressed)



func _build_ui():
	for child in items_container.get_children():
		child.queue_free()
		
	for detail in ability_details:
		var item = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.13, 0.18, 0.8)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		item.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 15)

		
		var cb = CheckBox.new()
		cb.button_pressed = selected_set.has(detail.name)
		cb.toggled.connect(func(pressed): _on_checkbox_toggled(detail.name, cb, pressed))
		hbox.add_child(cb)
		
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var head = HBoxContainer.new()
		var name_lbl = Label.new()
		name_lbl.text = detail.name
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
		head.add_child(name_lbl)
		
		var stats_lbl = Label.new()
		stats_lbl.text = " (" + detail.stats + ")"
		stats_lbl.add_theme_font_size_override("font_size", 14)
		stats_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		head.add_child(stats_lbl)
		vbox.add_child(head)
		
		var desc_lbl = Label.new()
		desc_lbl.text = detail.desc
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
		vbox.add_child(desc_lbl)
		
		hbox.add_child(vbox)
		item.add_child(hbox)
		items_container.add_child(item)

func _on_checkbox_toggled(ability_name: String, cb: CheckBox, pressed: bool):
	if pressed:
		if selected_set.size() >= 3:
			cb.button_pressed = false
			SoundManager.play_sfx("hit") # error buzzer sound
			return
		selected_set[ability_name] = true
	else:
		selected_set.erase(ability_name)
		
	_update_state()

func _update_state():
	var count = selected_set.size()
	if warning_label:
		if count > 0 and count <= 3:
			warning_label.text = "%d/3 abilities selected. Ready to deploy!" % count
			warning_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3, 1.0))
		else:
			warning_label.text = "You must select 1 to 3 abilities! (Selected: 0/3)"
			warning_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1.0))
	if close_button:
		close_button.disabled = (count == 0 or count > 3)


func _on_close_pressed():
	if selected_set.size() == 0 or selected_set.size() > 3:
		return
		
	var arr: Array[String] = []
	for ability_name in selected_set.keys():
		arr.append(ability_name)
		
	SaveManager.set_setting("equipped_abilities", arr)
	SaveManager.save_game()
	
	queue_free()
