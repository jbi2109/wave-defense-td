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

# Map registry: id -> display name + scene. All other per-map gameplay data
# (waves, base HP, starting gold) lives in the MapConfig resource exported on
# each map scene's root (levels/map_*_config.tres).
const maps := {
	"map1": {
		"name": "Map 1 (Winding Corners)",
		"scene": "res://levels/map_1.tscn",
	},
	"map2": {
		"name": "Map 2 (Serpentine)",
		"scene": "res://levels/map_2.tscn",
	},
	"map3": {
		"name": "Map 3 (Labyrinth)",
		"scene": "res://levels/map_3.tscn",
	},
}

