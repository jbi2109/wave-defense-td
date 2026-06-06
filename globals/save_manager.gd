extends Node

const SAVE_PATH = "user://save_data.json"

var settings = {
	"volume_master": 0.8,
	"volume_sfx": 0.8,
	"volume_music": 0.8,
	"show_damage_numbers": true,
	"high_performance_flowfield": false
}

var high_scores = {
	"map1": 0,
	"map2": 0
}

var gold_collected: int = 0

func _ready():
	_ensure_audio_bus("SFX")
	_ensure_audio_bus("Music")
	load_game()

func save_game():
	var save_dict = {
		"settings": settings,
		"high_scores": high_scores,
		"gold_collected": gold_collected
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_dict)
		file.store_string(json_string)
		file.close()

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		save_game() # Save default settings
		_apply_settings()
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			var data = json.data
			if data is Dictionary:
				if data.has("settings") and data["settings"] is Dictionary:
					for k in data["settings"].keys():
						settings[k] = data["settings"][k]
				if data.has("high_scores") and data["high_scores"] is Dictionary:
					for k in data["high_scores"].keys():
						high_scores[k] = data["high_scores"][k]
				if data.has("gold_collected"):
					gold_collected = int(data["gold_collected"])
		_apply_settings()

func update_high_score(map_id: String, wave: int):
	if not high_scores.has(map_id) or wave > high_scores[map_id]:
		high_scores[map_id] = wave
		save_game()

func set_setting(key: String, value):
	settings[key] = value
	save_game()
	_apply_settings()

func _apply_settings():
	_set_bus_volume("Master", settings.get("volume_master", 0.8))
	_set_bus_volume("SFX", settings.get("volume_sfx", 0.8))
	_set_bus_volume("Music", settings.get("volume_music", 0.8))

func _set_bus_volume(bus_name: String, val: float):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx != -1:
		var db = linear_to_db(val)
		db = clampf(db, -80.0, 6.0)
		AudioServer.set_bus_volume_db(bus_idx, db)
		AudioServer.set_bus_mute(bus_idx, val <= 0.0)

func _ensure_audio_bus(bus_name: String):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1:
		AudioServer.add_bus()
		var new_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_idx, bus_name)
		AudioServer.set_bus_send(new_idx, "Master")
