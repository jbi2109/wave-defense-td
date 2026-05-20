extends Sprite2D
class_name Turret

enum TargetMode { FIRST, LAST, STRONGEST, CLOSEST }

@export var turret_type: String   = ""          ## Key into Data.turrets dict
@export var target_mode: TargetMode = TargetMode.CLOSEST

# Runtime stats (populated from Data.gd or export overrides)
var damage: float       = 5.0
var attack_range: float = 300.0
var fire_rate: float    = 0.2    ## Seconds between shots
var current_level: int  = 1
var total_spent: int    = 0      ## Tracks gold spent (for sell value)

@onready var enemy_manager: EnemyManager = get_node("../EnemyManager")

var _fire_timer: float = 0.0

# ─────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────
func _ready():
	if turret_type != "" and Data.turrets.has(turret_type):
		_load_stats_from_data()

func _load_stats_from_data():
	var def = Data.turrets[turret_type]
	damage       = def.stats.get("damage", damage)
	attack_range = def.stats.get("attack_range", attack_range)
	fire_rate    = 1.0 / def.stats.get("attack_speed", 1.0 / fire_rate)
	total_spent  = def.get("cost", 0)

# ─────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────
func _process(delta):
	_fire_timer -= delta
	if not enemy_manager: return

	var target_idx = _find_target()
	if target_idx == -1: return

	look_at(enemy_manager.positions[target_idx])

	if _fire_timer <= 0.0:
		_fire(target_idx)
		_fire_timer = fire_rate

# ─────────────────────────────────────────────────────────────
#  TARGETING
# ─────────────────────────────────────────────────────────────
func _find_target() -> int:
	var nearby = enemy_manager.get_nearby_enemies(global_position, attack_range)
	if nearby.is_empty(): return -1

	match target_mode:
		TargetMode.CLOSEST:
			return _target_closest(nearby)
		TargetMode.STRONGEST:
			return _target_strongest(nearby)
		TargetMode.FIRST:
			return _target_first(nearby)
		TargetMode.LAST:
			return _target_last(nearby)
	return _target_closest(nearby)

func _target_closest(indices: Array[int]) -> int:
	var best_idx = -1
	var best_dsq = INF
	for idx in indices:
		var dsq = global_position.distance_squared_to(enemy_manager.positions[idx])
		if dsq < best_dsq:
			best_dsq = dsq
			best_idx = idx
	return best_idx

func _target_strongest(indices: Array[int]) -> int:
	var best_idx = -1
	var best_hp  = -1.0
	for idx in indices:
		if enemy_manager.healths[idx] > best_hp:
			best_hp  = enemy_manager.healths[idx]
			best_idx = idx
	return best_idx

func _target_first(indices: Array[int]) -> int:
	# "First" = lowest health remaining as a proxy for closest to nexus
	var best_idx = -1
	var best_hp  = INF
	for idx in indices:
		if enemy_manager.healths[idx] < best_hp:
			best_hp  = enemy_manager.healths[idx]
			best_idx = idx
	return best_idx

func _target_last(indices: Array[int]) -> int:
	# "Last" = highest health (furthest from nexus proxy)
	return _target_strongest(indices)

# ─────────────────────────────────────────────────────────────
#  FIRE
# ─────────────────────────────────────────────────────────────
func _fire(target_idx: int):
	enemy_manager.damage_enemy(target_idx, damage)
	# TODO Phase 2: spawn bullet node for visual

# ─────────────────────────────────────────────────────────────
#  UPGRADE
# ─────────────────────────────────────────────────────────────
func upgrade() -> bool:
	if turret_type == "" or not Data.turrets.has(turret_type): return false
	var def = Data.turrets[turret_type]
	if current_level >= def.get("max_level", 1): return false

	var cost = def.get("upgrade_cost", 0)
	if Globals.gold < cost: return false

	Globals.gold -= cost
	GlobalEvents.gold_changed.emit(Globals.gold)
	total_spent += cost
	current_level += 1

	# Apply upgrade bonuses from Data.turrets[type].upgrades
	var upgrades = def.get("upgrades", {})
	if upgrades.has("damage"):
		var u = upgrades["damage"]
		if u.get("multiplies", false):
			damage *= u["amount"]
		else:
			damage += u["amount"]
	if upgrades.has("attack_speed"):
		var u = upgrades["attack_speed"]
		if u.get("multiplies", false):
			fire_rate /= u["amount"]   # faster = lower interval
		else:
			fire_rate -= u["amount"]
	fire_rate = maxf(fire_rate, 0.03)  # Never faster than ~33 shots/s

	GlobalEvents.turret_upgraded.emit(self)
	return true

func sell() -> int:
	var refund = int(total_spent * 0.6)
	Globals.gold += refund
	GlobalEvents.gold_changed.emit(Globals.gold)
	GlobalEvents.turret_sold.emit(self)
	queue_free()
	return refund

func get_upgrade_cost() -> int:
	if turret_type == "" or not Data.turrets.has(turret_type): return 0
	return Data.turrets[turret_type].get("upgrade_cost", 0)

func is_max_level() -> bool:
	if turret_type == "" or not Data.turrets.has(turret_type): return true
	return current_level >= Data.turrets[turret_type].get("max_level", 1)
