extends Node2D

var _timer: float = 0.0
var duration: float = 0.6
var sprite: Sprite2D = null

func _ready():
	sprite = Sprite2D.new()
	var tex = load("res://assets/orbital_beam.png")
	if tex:
		sprite.texture = tex
		# Pivot at bottom
		sprite.position = Vector2(0, -tex.get_height() / 2.0)
	
	sprite.modulate = Color(1.2, 1.2, 1.5, 1.0) # Brightness boost
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = mat
	add_child(sprite)

func init(pos: Vector2, radius: float):
	global_position = pos
	if sprite and sprite.texture:
		var s = (radius * 2.0) / sprite.texture.get_width()
		sprite.scale = Vector2(s, s)
		# Adjust pivot based on scale
		sprite.position = Vector2(0, -sprite.texture.get_height() * s / 2.0)

func _process(delta):
	_timer += delta
	if _timer >= duration:
		queue_free()
	else:
		if sprite:
			var ratio = _timer / duration
			sprite.modulate.a = 1.0 - (ratio * ratio) # Fade out non-linearly
