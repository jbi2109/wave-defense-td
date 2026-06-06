extends PanelContainer
class_name SettingsMenu

@onready var master_slider = $VBoxContainer/VolumeMaster/HSlider
@onready var master_value_label = $VBoxContainer/VolumeMaster/ValueLabel
@onready var sfx_slider = $VBoxContainer/VolumeSFX/HSlider
@onready var sfx_value_label = $VBoxContainer/VolumeSFX/ValueLabel
@onready var music_slider = $VBoxContainer/VolumeMusic/HSlider
@onready var music_value_label = $VBoxContainer/VolumeMusic/ValueLabel

@onready var damage_numbers_check = $VBoxContainer/Performance/DamageNumbersCheck
@onready var high_perf_check = $VBoxContainer/Performance/HighPerfCheck

@onready var close_button = $VBoxContainer/CloseButton

func _ready():
	master_slider.value = SaveManager.settings.get("volume_master", 0.8)
	sfx_slider.value = SaveManager.settings.get("volume_sfx", 0.8)
	music_slider.value = SaveManager.settings.get("volume_music", 0.8)
	
	damage_numbers_check.button_pressed = SaveManager.settings.get("show_damage_numbers", true)
	high_perf_check.button_pressed = SaveManager.settings.get("high_performance_flowfield", false)
	
	_update_value_labels()
	
	if get_tree().current_scene and get_tree().current_scene.name == "Main":
		get_tree().paused = true
	
	master_slider.value_changed.connect(_on_master_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	music_slider.value_changed.connect(_on_music_changed)
	
	damage_numbers_check.toggled.connect(_on_damage_numbers_toggled)
	high_perf_check.toggled.connect(_on_high_perf_toggled)
	
	close_button.pressed.connect(_on_close_pressed)

func _update_value_labels():
	master_value_label.text = "%d%%" % int(master_slider.value * 100)
	sfx_value_label.text = "%d%%" % int(sfx_slider.value * 100)
	music_value_label.text = "%d%%" % int(music_slider.value * 100)

func _on_master_changed(value: float):
	SaveManager.set_setting("volume_master", value)
	_update_value_labels()

func _on_sfx_changed(value: float):
	SaveManager.set_setting("volume_sfx", value)
	_update_value_labels()

func _on_music_changed(value: float):
	SaveManager.set_setting("volume_music", value)
	_update_value_labels()

func _on_damage_numbers_toggled(button_pressed: bool):
	SaveManager.set_setting("show_damage_numbers", button_pressed)

func _on_high_perf_toggled(button_pressed: bool):
	SaveManager.set_setting("high_performance_flowfield", button_pressed)

func _on_close_pressed():
	# Allow custom handler or free
	if get_tree().paused:
		get_tree().paused = false
	queue_free()
