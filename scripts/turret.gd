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

var rotates: bool = true

@onready var enemy_manager: EnemyManager = get_node("/root/Main/EnemyManager")
var _fire_timer: float = 0.0
var target_idx: int = -1

@export_group("Inspector Overrides")
@export var size_override: float = 0.0
@export var damage_override: float = 0.0
@export var fire_rate_override: float = 0.0

# ─────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────
func _ready():
	add_to_group("turret")
	_load_stats_from_data()
	
	if damage_override > 0.0:
		damage = damage_override
	if fire_rate_override > 0.0:
		fire_rate = fire_rate_override
	if size_override > 0.0:
		scale = Vector2(size_override, size_override)

func get_definition() -> Node:
	var placement_manager = get_node_or_null("/root/Main/TurretPlacementManager")
	if placement_manager and placement_manager.has_method("get_definition"):
		return placement_manager.get_definition(turret_type)
	return null

func _load_stats_from_data():
	var t_def = get_definition()
	if t_def:
		damage       = t_def.damage
		attack_range = t_def.attack_range
		fire_rate    = t_def.fire_rate
		total_spent  = t_def.cost
		var s        = t_def.scale
		scale        = Vector2(s, s)
		rotates      = t_def.rotates
		
		var tex_path = t_def.sprite_path
		if tex_path.begins_with("res://Assets"):
			tex_path = tex_path.replace("res://Assets", "res://assets")
		if tex_path != "":
			texture = load(tex_path)
		if turret_type == "slow":
			self_modulate = Color(0.2, 0.7, 1.0, 1.0)


# ─────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────
func _process(delta):
	_fire_timer -= delta
	if not enemy_manager: return

	# Check if current cached target is still valid
	var target_valid = false
	if target_idx >= 0 and target_idx < enemy_manager.active_count:
		if enemy_manager.healths[target_idx] > 0.0:
			var target_pos = enemy_manager.positions[target_idx]
			if global_position.distance_squared_to(target_pos) <= attack_range * attack_range:
				target_valid = true

	if not target_valid:
		target_idx = _find_target()

	if target_idx == -1: return

	if rotates:
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
func _fire(p_target_idx: int):
	SoundManager.play_sfx("shoot_" + turret_type)
	if turret_type == "slow":
		var targets = enemy_manager.get_nearby_enemies(global_position, attack_range)
		for idx in targets:
			if idx >= 0 and idx < enemy_manager.active_count:
				enemy_manager.speed_modifiers[idx] = minf(enemy_manager.speed_modifiers[idx], 0.4)
				enemy_manager.damage_enemy(idx, damage)
	else:
		enemy_manager.damage_enemy(p_target_idx, damage)
	
	# Spawn visual tracer
	var tracer_scene = load("res://scripts/bullet_tracer.gd")
	var tracer = Node2D.new()
	tracer.set_script(tracer_scene)
	
	var m_pos = global_position
	if has_node("Muzzle"):
		m_pos = $Muzzle.global_position
		
	var target_pos = enemy_manager.positions[p_target_idx]
	
	var col = Color(1.0, 0.9, 0.5, 0.9)
	var w = 3.0
	
	match turret_type:
		"gatling":
			col = Color(1.0, 0.85, 0.4, 0.9)
			w = 2.0
		"laser":
			col = Color(1.0, 0.4, 0.1, 0.8) # Fire/Flamethrower color
			w = 6.0
		"ray":
			col = Color(0.1, 0.8, 1.0, 0.9) # Cyan laser
			w = 4.0
		"melee":
			col = Color(0.9, 0.2, 0.1, 0.7) # Red explosive shockwave
			w = 12.0
		"slow":
			col = Color(0.1, 0.7, 1.0, 0.9) # Ice cyan laser
			w = 4.0
			
	# Add to main scene tree
	get_parent().add_child(tracer)
	tracer.global_position = global_position # Anchor to local coordinate space reference
	tracer.init(m_pos, target_pos, col, w)

# ─────────────────────────────────────────────────────────────
#  UPGRADE
# ─────────────────────────────────────────────────────────────
func upgrade() -> bool:
	var t_def = get_definition()
	if not t_def: return false
	if current_level >= t_def.max_level: return false

	var cost = t_def.upgrade_cost
	if Globals.gold < cost: return false

	Globals.gold -= cost
	GlobalEvents.gold_changed.emit(Globals.gold)
	total_spent += cost
	current_level += 1

	# Apply upgrade bonuses from t_def
	if t_def.damage_upgrade > 0.0:
		if t_def.damage_upgrade_multiplies:
			damage *= t_def.damage_upgrade
		else:
			damage += t_def.damage_upgrade
			
	if t_def.speed_upgrade > 0.0:
		if t_def.speed_upgrade_multiplies:
			fire_rate /= t_def.speed_upgrade   # faster = lower interval
		else:
			fire_rate -= t_def.speed_upgrade
	fire_rate = maxf(fire_rate, 0.03)  # Never faster than ~33 shots/s

	GlobalEvents.turret_upgraded.emit(self)
	SoundManager.play_sfx("build")
	return true

func sell() -> int:
	SoundManager.play_sfx("sell")
	var refund = int(total_spent * 0.6)
	Globals.gold += refund
	GlobalEvents.gold_changed.emit(Globals.gold)
	GlobalEvents.turret_sold.emit(self)
	queue_free()
	return refund

func get_upgrade_cost() -> int:
	var t_def = get_definition()
	if not t_def: return 0
	return t_def.upgrade_cost

func is_max_level() -> bool:
	var t_def = get_definition()
	if not t_def: return true
	return current_level >= t_def.max_level

