extends Node2D

var radius: float = 120.0
var damage_per_sec: float = 15.0
var duration: float = 4.0
var slow_factor: float = 0.8
var enemy_manager: EnemyManager = null

var _timer: float = 0.0
var _tick_timer: float = 0.0
var tick_interval: float = 0.25
var sprite: Sprite2D = null

func init(pos: Vector2, r: float, dmg: float, dur: float, slow: float, em: EnemyManager):
	global_position = pos
	radius = r
	damage_per_sec = dmg
	duration = dur
	slow_factor = slow
	enemy_manager = em
	
	if sprite and sprite.texture:
		var s = (radius * 2.0) / sprite.texture.get_width()
		sprite.scale = Vector2(s, s)

func _ready():
	z_index = -1 # Render behind enemies (z=0) but above the ground (z=-10)
	
	sprite = Sprite2D.new()
	var tex = load("res://assets/acid_pool.png")
	if tex:
		sprite.texture = tex
		var s = (radius * 2.0) / tex.get_width()
		sprite.scale = Vector2(s, s)
	
	# Use normal blend mode (MIX) so we can make it darker green
	sprite.modulate = Color(0.2, 0.7, 0.1, 0.85) # Darker acid green
	add_child(sprite)

func _process(delta):
	_timer += delta
	if _timer >= duration:
		queue_free()
		return
		
	if sprite and _timer > duration - 0.5:
		sprite.modulate.a = lerpf(0.7, 0.0, (_timer - (duration - 0.5)) / 0.5)
		
	_tick_timer += delta
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_tick_effects()

func _apply_tick_effects():
	if not enemy_manager: return
	
	var damage_tick = damage_per_sec * tick_interval
	enemy_manager.pending_damages.append({
		"pos": global_position,
		"radius": radius,
		"damage": damage_tick,
		"effect_type": 3,
		"effect_value": slow_factor
	})
