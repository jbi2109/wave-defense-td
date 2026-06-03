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
var gpu_idx: int = -1
var target_pos: Vector2 = Vector2.INF

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
		
	call_deferred("_register_with_manager")

func _register_with_manager():
	if is_instance_valid(enemy_manager) and enemy_manager.has_method("add_turret"):
		enemy_manager.add_turret(self)

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
	if target_pos != Vector2.INF and rotates:
		var target_angle = (target_pos - global_position).angle()
		rotation = lerp_angle(rotation, target_angle, delta * 15.0)

# ─────────────────────────────────────────────────────────────
#  GPU EVENTS
# ─────────────────────────────────────────────────────────────
func on_gpu_fire(p_target_pos: Vector2):
	target_pos = p_target_pos
	
	SoundManager.play_sfx("shoot_" + turret_type)
	
	# Spawn visual tracer
	var tracer_scene = load("res://scripts/bullet_tracer.gd")
	var tracer = Node2D.new()
	tracer.set_script(tracer_scene)
	
	var m_pos = global_position
	if has_node("Muzzle"):
		m_pos = $Muzzle.global_position
		
	var col = Color(1.0, 0.9, 0.5, 0.9)
	var w = 3.0
	
	match turret_type:
		"gatling":
			col = Color(1.0, 0.85, 0.4, 0.9)
			w = 2.0
		"laser":
			col = Color(1.0, 0.4, 0.1, 0.8)
			w = 6.0
		"ray":
			col = Color(0.1, 0.8, 1.0, 0.9)
			w = 4.0
		"melee":
			col = Color(0.9, 0.2, 0.1, 0.7)
			w = 12.0
		"slow":
			col = Color(0.1, 0.7, 1.0, 0.9)
			w = 4.0
			
	get_parent().add_child(tracer)
	tracer.global_position = global_position
	tracer.init(m_pos, target_pos, col, w)

# ─────────────────────────────────────────────────────────────
#  MANAGEMENT
# ─────────────────────────────────────────────────────────────
func _enter_tree():
	if not is_in_group("turret"):
		add_to_group("turret")

func _exit_tree():
	if is_instance_valid(enemy_manager) and enemy_manager.has_method("remove_turret"):
		enemy_manager.remove_turret(self)



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

	if is_instance_valid(enemy_manager) and enemy_manager.has_method("update_turret"):
		enemy_manager.update_turret(self)

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

