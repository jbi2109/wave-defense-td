extends Node2D
class_name EnemyConfig

# The enemy roster. ARRAY ORDER IS THE TYPE INDEX — GPU buffers, split_type_index
# and the boss overrides in battle.gd reference enemies by index. Canonical order:
# 0 Swarmer, 1 Tank, 2 Runner, 3 Armored, 4 MiniBoss, 5 BigBoss, 6 Flyer, 7 Splitter.
@export var definitions: Array[EnemyDefinition] = []

var enemy_types: Array[EnemyDefinition] = []
var type_scales: Array[float] = []
var type_speeds: Array[float] = []
var type_healths: Array[float] = []
var type_split_count: Array[int] = []
var type_split_type: Array[int] = []
var type_golds: Array[int] = []
var type_nexus_dmg: Array[int] = []

func _ready():
	for d in definitions:
		if d is EnemyDefinition:
			enemy_types.append(d)
			type_scales.append(d.scale)
			type_speeds.append(d.speed)
			type_healths.append(d.health)
			type_split_count.append(d.split_count)
			type_split_type.append(d.split_type_index)
			type_golds.append(d.gold_yield)
			type_nexus_dmg.append(d.nexus_damage)
	if enemy_types.is_empty():
		push_warning("EnemyConfig: no enemy definitions assigned!")
