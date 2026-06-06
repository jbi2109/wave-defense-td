extends Node2D

var _timer: float = 0.0
var duration: float = 0.4
var sprite: Sprite2D = null

func _ready():
	sprite = Sprite2D.new()
	var tex = load("res://abilities/frost_nova/frost_nova.png")
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(0.1, 0.1) # Start small
	
	sprite.modulate = Color(1.2, 1.5, 2.0, 1.0) # Cold cyan/blue glow
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = mat
	add_child(sprite)

var radius: float = 38.0

func init(pos: Vector2, r: float):
	global_position = pos
	radius = r

func _process(delta):
	_timer += delta
	if _timer >= duration:
		queue_free()
	else:
		if sprite and sprite.texture:
			var ratio = _timer / duration
			# Scale based on radius (radius * 2.0 = diameter)
			var target_scale = (radius * 2.0) / sprite.texture.get_width()
			sprite.scale = Vector2.ONE * lerpf(0.1, target_scale, ratio)
			sprite.modulate.a = 1.0 - (ratio * ratio)
