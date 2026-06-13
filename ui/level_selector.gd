extends Control

## Entry screen. Builds one map card per Data.maps entry from the in-scene
## CardTemplate — registering a new map needs no selector edits.

@onready var cards_container: HBoxContainer = $CenterContainer/VBoxContainer/CardsContainer
@onready var card_template: PanelContainer = $CenterContainer/VBoxContainer/CardsContainer/CardTemplate
@onready var btn_settings: Button = $CenterContainer/VBoxContainer/BottomButtons/SettingsButton
@onready var btn_quit: Button = $CenterContainer/VBoxContainer/BottomButtons/QuitButton

var settings_scene: PackedScene = preload("res://ui/settings_menu.tscn")

func _ready() -> void:
	card_template.visible = false
	var ids := Data.maps.keys()
	ids.sort()
	for id in ids:
		var entry: Dictionary = Data.maps[id]
		var card := card_template.duplicate() as PanelContainer
		card.name = "Card_" + id
		card.visible = true
		card.get_node("VBox/NameLabel").text = entry.get("name", id)
		card.get_node("VBox/DescriptionLabel").text = entry.get("description", "")
		card.get_node("VBox/HighScoreLabel").text = "High Score: Wave %d" % SaveManager.high_scores.get(id, 0)
		card.get_node("VBox/PlayButton").pressed.connect(_on_map_selected.bind(id))
		cards_container.add_child(card)

	btn_settings.pressed.connect(_on_settings_pressed)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit_pressed)

func _on_map_selected(map_id: String) -> void:
	Globals.selected_map = map_id
	get_tree().change_scene_to_file("res://battle/battle.tscn")

func _on_settings_pressed() -> void:
	var menu: Control = settings_scene.instantiate() as Control
	add_child(menu)

func _on_quit_pressed() -> void:
	get_tree().quit()
