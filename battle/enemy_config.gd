extends Node2D
class_name EnemyConfig

var enemy_types: Array[Node] = []
var type_scales: Array[float] = []
var type_speeds: Array[float] = []
var type_healths: Array[float] = []
var type_split_count: Array[int] = []
var type_split_type: Array[int] = []

func _ready():
	for child in get_children():
		if child.get_script() != null and "enemy_definition" in child.get_script().resource_path:
			enemy_types.append(child)
			type_scales.append(child.scale if "scale" in child else 1.0)
			type_speeds.append(child.speed if "speed" in child else 100.0)
			type_healths.append(child.health if "health" in child else 10.0)
			type_split_count.append(child.split_count if "split_count" in child else 0)
			type_split_type.append(child.split_type_index if "split_type_index" in child else 0)
