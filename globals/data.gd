extends Node



const stats := {
	"damage": {"name": "Damage"},
	"attack_speed": {"name": "Speed"},
	"attack_range": {"name": "Range"},
	"bulletSpeed": {"name": "Bullet Speed"},
	"bulletPierce": {"name": "Bullet Pierce"},
	"ray_length": {"name": "Ray Length"},
	"ray_duration": {"name": "Ray Duration"},
}

const bullets := {
	"fire": {
		"frames": "res://assets/bullets/bullet1.tres",
	},
	"laser": {
		"frames": "res://assets/bullets/bullet2.tres",
	}
}

const maps := {
	"map1": {
		"name": "Map 1 (Winding Corners)",
		"bg": "",
		"scene": "res://levels/map_1.tscn",
		"baseHp": 10,
		"startingGold": 100,
		"spawner_settings": {
			"difficulty": {"initial": 2.0, "increase": 1.5, "multiplies": true},
			"max_waves": 10,
			"wave_spawn_count": 10,
			"special_waves": {},
		},
	},
	"map2": {
		"name": "Map 2 (Serpentine)",
		"bg": "",
		"scene": "res://levels/map_2.tscn",
		"baseHp": 10,
		"startingGold": 100,
		"spawner_settings": {
			"difficulty": {"initial": 2.5, "increase": 1.6, "multiplies": true},
			"max_waves": 15,
			"wave_spawn_count": 12,
			"special_waves": {},
		},
	},
	"map3": {
		"name": "Map 3 (Labyrinth)",
		"bg": "",
		"scene": "res://levels/map_3.tscn",
		"baseHp": 10,
		"startingGold": 120,
		"spawner_settings": {
			"difficulty": {"initial": 3.0, "increase": 1.7, "multiplies": true},
			"max_waves": 20,
			"wave_spawn_count": 15,
			"special_waves": {},
		},
	},
}

