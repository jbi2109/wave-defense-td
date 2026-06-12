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
var currentMap    : Node2D

# ─── Economy ───────────────────────────────────────────────
var gold: int          = 150
var starting_gold: int = 150

# ─── Mana System ───────────────────────────────────────────
var mana: float = 100.0
var max_mana: float = 100.0
var mana_regen: float = 1.25 # per second

# ─── Abilities ─────────────────────────────────────────────
var equipped_abilities: Array[String] = ["Orbital Strike", "Frost Nova", "Chain Lightning"]

func _process(delta: float):
	if mana < max_mana:
		mana += mana_regen * delta
		if mana > max_mana:
			mana = max_mana
		GlobalEvents.mana_changed.emit(mana, max_mana)

func spend_mana(amount: float) -> bool:
	if mana < amount: return false
	mana -= amount
	GlobalEvents.mana_changed.emit(mana, max_mana)
	return true

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
	mana = max_mana
	GlobalEvents.mana_changed.emit(mana, max_mana)
