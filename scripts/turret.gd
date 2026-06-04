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

var target_dist: float = 60.0
var sweep_time: float = 0.0
var _dragging_target: bool = false

var cone_center: float = 0.0:
	set(val):
		cone_center = val
		if has_node("GunSprite"):
			$GunSprite.rotation = cone_center

var cone_width: float = TAU:
	set(val):
		cone_width = val
		if not _dragging_target:
			_update_target_dist_from_cone_width()

var sweep_phase: float = 0.0
var sweep_speed: float = PI / 6.0
var sweep_direction: float = 1.0

func _update_target_dist_from_cone_width():
	var max_w = PI * 0.75
	var min_w = PI / 8.0
	var denominator = min_w - max_w
	var t = 0.0
	if abs(denominator) > 0.0001:
		t = (cone_width - max_w) / denominator
	target_dist = lerp(20.0, 100.0, clampf(t, 0.0, 1.0))

func _update_cone_width():
	var t = (target_dist - 20.0) / 80.0
	cone_width = lerp(PI * 0.75, PI / 8.0, clampf(t, 0.0, 1.0))

var overdrive_timer: float = 0.0
var overdrive_multiplier: float = 1.5
var _was_overdriven: bool = false

@export_group("Inspector Overrides")
@export var size_override: float = 0.0
@export var damage_override: float = 0.0
@export var fire_rate_override: float = 0.0

var _target_sprite: Sprite2D = null

# ─────────────────────────────────────────────────────────────
#  INITIALISATION
# ─────────────────────────────────────────────────────────────
func _ready():
	add_to_group("turret")
	_load_stats_from_data()
	
	_target_sprite = Sprite2D.new()
	_target_sprite.texture = load("res://assets/turrets/target.png")
	_target_sprite.z_index = 5
	_target_sprite.top_level = true
	add_child(_target_sprite)
	
	sweep_time = randf() * TAU
	_update_target_dist_from_cone_width()
	
	if damage_override > 0.0:
		damage = damage_override
	if fire_rate_override > 0.0:
		fire_rate = fire_rate_override
	if size_override > 0.0:
		scale = Vector2(size_override, size_override)
		
	if has_node("GunSprite"):
		$GunSprite.z_index = 1
		$GunSprite.rotation = cone_center
		
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
			texture = preload("res://assets/turrets/base.png")
			if has_node("GunSprite"):
				$GunSprite.texture = load(tex_path)
		if turret_type == "slow":
			self_modulate = Color(0.2, 0.7, 1.0, 1.0)

# ─────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────
func _process(delta):
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	if is_instance_valid(_target_sprite):
		var is_build_phase = (wave_manager == null or wave_manager.current_wave == 0 or wave_manager.is_inter_wave)
		_target_sprite.visible = is_build_phase
		if is_build_phase:
			_target_sprite.global_position = global_position + Vector2.RIGHT.rotated(cone_center) * target_dist

	if overdrive_timer > 0.0:
		overdrive_timer -= delta
		if not _was_overdriven:
			_was_overdriven = true
			queue_redraw()
	elif _was_overdriven:
		_was_overdriven = false
		queue_redraw()

	var is_wave_active = wave_manager and wave_manager.current_wave > 0 and not wave_manager.is_inter_wave
	if not is_wave_active: return

	_fire_timer -= delta

	if rotates:
		sweep_time += sweep_speed * delta
		sweep_phase = (cone_width / 2.0) * sin(sweep_time)
		
		if has_node("GunSprite"):
			$GunSprite.rotation = cone_center + sweep_phase

func _unhandled_input(event: InputEvent):
	var wave_manager = get_node_or_null("/root/Main/WaveManager")
	var is_build_phase = (wave_manager == null or wave_manager.current_wave == 0 or wave_manager.is_inter_wave)
	if not is_build_phase:
		_dragging_target = false
		return
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			if is_instance_valid(_target_sprite) and _target_sprite.visible:
				var mouse_pos = get_global_mouse_position()
				if mouse_pos.distance_to(_target_sprite.global_position) < 24.0:
					_dragging_target = true
					get_viewport().set_input_as_handled()
		else:
			if _dragging_target:
				_dragging_target = false
				get_viewport().set_input_as_handled()
				if is_instance_valid(enemy_manager) and enemy_manager.has_method("update_turret"):
					enemy_manager.update_turret(self)
					
	elif event is InputEventMouseMotion and _dragging_target:
		var mouse_pos = get_global_mouse_position()
		var to_mouse = mouse_pos - global_position
		cone_center = to_mouse.angle()
		target_dist = clamp(to_mouse.length(), 20.0, 100.0)
		
		if is_instance_valid(_target_sprite):
			_target_sprite.global_position = global_position + Vector2.RIGHT.rotated(cone_center) * target_dist
			
		_update_cone_width()
		
		if has_node("GunSprite"):
			$GunSprite.rotation = cone_center
			
		if is_instance_valid(enemy_manager) and enemy_manager.has_method("update_turret"):
			enemy_manager.update_turret(self)
			
		get_viewport().set_input_as_handled()
		queue_redraw()

func _draw():
	if _was_overdriven:
		var r = max(texture.get_width(), texture.get_height()) * 0.55 if texture else 25.0
		var time = Time.get_ticks_msec() / 1000.0
		var pulse = 1.0 + sin(time * 6.0) * 0.08
		var current_r = r * pulse
		
		var num_segments = 3
		var segment_length = (TAU / num_segments) * 0.7 
		var spin = time * 3.0 - rotation
		
		var color = Color(1.0, 0.84, 0.0, 0.9)
		for i in range(num_segments):
			var start_angle = spin + i * (TAU / num_segments)
			var end_angle = start_angle + segment_length
			draw_arc(Vector2.ZERO, current_r, start_angle, end_angle, 12, color, 2.5, true)

# ─────────────────────────────────────────────────────────────
#  GPU EVENTS
# ─────────────────────────────────────────────────────────────
func on_gpu_fire(p_target_pos: Vector2):
	target_pos = p_target_pos
	
	SoundManager.play_sfx("shoot_" + turret_type, randf_range(0.85, 1.15))
	
	var current_rotation = rotation
	if has_node("GunSprite"):
		current_rotation = $GunSprite.rotation
		
		# Firing Recoil/Vibration Animation
		var tween = create_tween()
		if turret_type == "laser":
			# Flamethrower: vibration
			var original_pos = Vector2.ZERO
			tween.tween_property($GunSprite, "position", original_pos + Vector2(randf_range(-2, 2), randf_range(-2, 2)), 0.05)
			tween.tween_property($GunSprite, "position", original_pos, 0.05)
		else:
			# Others: Recoil
			var original_pos = Vector2.ZERO
			var recoil_dist = -8.0
			var recoil_vec = Vector2.RIGHT.rotated(current_rotation) * recoil_dist
			tween.tween_property($GunSprite, "position", original_pos + recoil_vec, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property($GunSprite, "position", original_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
	# Spawn visual tracer
	var tracer_scene = load("res://scripts/bullet_tracer.gd")
	var tracer = Node2D.new()
	tracer.set_script(tracer_scene)
	
	var m_pos = global_position
	if has_node("GunSprite"):
		m_pos = $GunSprite.global_position
		if $GunSprite.has_node("Muzzle"):
			m_pos = $GunSprite/Muzzle.global_position
			
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

	if t_def.damage_upgrade > 0.0:
		if t_def.damage_upgrade_multiplies:
			damage *= t_def.damage_upgrade
		else:
			damage += t_def.damage_upgrade
			
	if t_def.speed_upgrade > 0.0:
		if t_def.speed_upgrade_multiplies:
			fire_rate /= t_def.speed_upgrade
		else:
			fire_rate -= t_def.speed_upgrade
	fire_rate = maxf(fire_rate, 0.03)

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
