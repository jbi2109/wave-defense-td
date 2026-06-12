extends Control

@onready var map1_score_label: Label = $CenterContainer/VBoxContainer/CardsContainer/CardMap1/VBox/HighScoreLabel
@onready var map2_score_label: Label = $CenterContainer/VBoxContainer/CardsContainer/CardMap2/VBox/HighScoreLabel
@onready var map3_score_label: Label = $CenterContainer/VBoxContainer/CardsContainer/CardMap3/VBox/HighScoreLabel

@onready var btn_map1: Button = $CenterContainer/VBoxContainer/CardsContainer/CardMap1/VBox/PlayButton
@onready var btn_map2: Button = $CenterContainer/VBoxContainer/CardsContainer/CardMap2/VBox/PlayButton
@onready var btn_map3: Button = $CenterContainer/VBoxContainer/CardsContainer/CardMap3/VBox/PlayButton
@onready var btn_settings: Button = $CenterContainer/VBoxContainer/BottomButtons/SettingsButton
@onready var btn_quit: Button = $CenterContainer/VBoxContainer/BottomButtons/QuitButton

var settings_scene: PackedScene = preload("res://ui/settings_menu.tscn")

func _ready() -> void:
	# Load high scores
	var score1: int = SaveManager.high_scores.get("map1", 0)
	var score2: int = SaveManager.high_scores.get("map2", 0)
	var score3: int = SaveManager.high_scores.get("map3", 0)

	map1_score_label.text = "High Score: Wave %d" % score1
	map2_score_label.text = "High Score: Wave %d" % score2
	map3_score_label.text = "High Score: Wave %d" % score3

	# Connect buttons
	btn_map1.pressed.connect(_on_map_selected.bind("map1"))
	btn_map2.pressed.connect(_on_map_selected.bind("map2"))
	btn_map3.pressed.connect(_on_map_selected.bind("map3"))
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

