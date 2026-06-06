extends Node2D

var radius: float = 120.0
var damage_per_sec: float = 15.0
var duration: float = 4.0
var slow_factor: float = 0.8
var damage: float = 0.0

var _timer: float = 0.0
var sprite: Sprite2D = null

func init(pos: Vector2, r: float, dmg: float, dur: float, s_factor: float):
	global_position = pos
	radius = r
	damage = dmg
	duration = dur
	slow_factor = s_factor
	
	if sprite and sprite.texture:
		var s = (radius * 2.0) / sprite.texture.get_width()
		sprite.scale = Vector2(s, s)

func _ready():
	z_index = -1 # Render behind enemies (z=0) but above the ground (z=-10)
	
	sprite = Sprite2D.new()
	var tex = load("res://abilities/acid_pool/acid_pool.png")
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
	
	GlobalEvents.aoe_damage_requested.emit(global_position, radius, damage * delta, false)
	GlobalEvents.aoe_slow_requested.emit(global_position, radius, slow_factor)

func _apply_tick_effects():
	pass
