extends Node
@warning_ignore("unused_signal")
signal goldChanged(newGold)
@warning_ignore("unused_signal")
signal baseHpChanged(newHp, maxHp)
@warning_ignore("unused_signal")
signal waveStarted(wave_count, enemy_count)
@warning_ignore("unused_signal")
signal waveCleared(wait_time)
@warning_ignore("unused_signal")
signal enemyDestroyed(remain)

var selected_map  := ""
var auto_test_active: bool = true
var mainNode      : Node2D
var turretsNode   : Node2D
var projectilesNode: Node2D
var currentMap    : Node2D
var hud           : Control

# ─── Economy ───────────────────────────────────────────────
var gold: int          = 150
var starting_gold: int = 150

func add_gold(amount: int):
	gold += amount
	GlobalEvents.gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold < amount: return false
	gold -= amount
	GlobalEvents.gold_changed.emit(gold)
	return true

func reset_gold():
	gold = starting_gold
	GlobalEvents.gold_changed.emit(gold)

# ─── Scene restart ─────────────────────────────────────────
func restart_current_level():
	var currentLevelScene := load(currentMap.scene_file_path)
	currentMap.queue_free()
	var newMap = currentLevelScene.instantiate()
	newMap.map_type = selected_map
	mainNode.add_child(newMap)
	hud.reset()
