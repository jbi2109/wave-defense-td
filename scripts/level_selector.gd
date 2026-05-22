extends Control

@onready var map1_score_label = $CenterContainer/VBoxContainer/CardsContainer/CardMap1/VBox/HighScoreLabel
@onready var map2_score_label = $CenterContainer/VBoxContainer/CardsContainer/CardMap2/VBox/HighScoreLabel

@onready var btn_map1 = $CenterContainer/VBoxContainer/CardsContainer/CardMap1/VBox/PlayButton
@onready var btn_map2 = $CenterContainer/VBoxContainer/CardsContainer/CardMap2/VBox/PlayButton
@onready var btn_settings = $CenterContainer/VBoxContainer/BottomButtons/SettingsButton
@onready var btn_quit = $CenterContainer/VBoxContainer/BottomButtons/QuitButton

var settings_scene = preload("res://scenes/ui/settings_menu.tscn")

func _ready():
	# Load high scores
	var score1 = SaveManager.high_scores.get("map1", 0)
	var score2 = SaveManager.high_scores.get("map2", 0)
	
	map1_score_label.text = "High Score: Wave %d" % score1
	map2_score_label.text = "High Score: Wave %d" % score2
	
	# Connect buttons
	btn_map1.pressed.connect(_on_map1_selected)
	btn_map2.pressed.connect(_on_map2_selected)
	btn_settings.pressed.connect(_on_settings_pressed)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit_pressed)
		


func _on_map1_selected():
	Globals.selected_map = "map1"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_map2_selected():
	Globals.selected_map = "map2"
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_settings_pressed():
	var menu = settings_scene.instantiate()
	add_child(menu)

func _on_quit_pressed():
	get_tree().quit()
