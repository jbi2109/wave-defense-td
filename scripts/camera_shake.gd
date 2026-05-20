extends Camera2D
class_name CameraShake

var _shake_timer: float = 0.0
var _shake_intensity: float = 0.0
var _original_offset: Vector2 = Vector2.ZERO

func _ready():
	_original_offset = offset
	GlobalEvents.nexus_damaged.connect(_on_nexus_damaged)

func shake(duration: float, intensity: float):
	_shake_timer = duration
	_shake_intensity = intensity

func _process(delta):
	if _shake_timer > 0.0:
		_shake_timer -= delta
		# Fade out shake intensity over time
		var ratio = _shake_timer / 0.3
		if _shake_timer <= 0.0:
			offset = _original_offset
		else:
			offset = _original_offset + Vector2(
				randf_range(-_shake_intensity * ratio, _shake_intensity * ratio),
				randf_range(-_shake_intensity * ratio, _shake_intensity * ratio)
			)

func _on_nexus_damaged(_current_hp: int):
	shake(0.3, 12.0)
