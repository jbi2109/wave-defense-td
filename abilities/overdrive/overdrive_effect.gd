extends Node2D

var _timer: float = 0.0
var duration: float = 0.6
var sprite: Sprite2D = null

func _ready():
	sprite = Sprite2D.new()
	var tex = load("res://abilities/overdrive/overdrive.jpg")
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(0.5, 0.5)
	
	sprite.modulate = Color(2.0, 1.2, 0.4, 1.0) # Orange/yellow energy
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	sprite.material = mat
	add_child(sprite)
	
	var camera = get_viewport().get_camera_2d()
	if camera:
		global_position = camera.global_position
	else:
		global_position = Vector2(960, 540)

func init():
	pass

func _process(delta):
	_timer += delta
	if _timer >= duration:
		queue_free()
	else:
		if sprite:
			var ratio = _timer / duration
			sprite.scale = Vector2.ONE * lerpf(0.5, 4.0, ratio)
			sprite.modulate.a = 1.0 - ratio
