extends Node2D
class_name BulletTracer

var start_pos: Vector2
var end_pos: Vector2
var color: Color = Color(1.0, 0.95, 0.6, 0.9)
var width: float = 3.0
var duration: float = 0.08
var _timer: float = 0.0

func init(from: Vector2, to: Vector2, p_color: Color = Color(1.0, 0.95, 0.6, 0.9), p_width: float = 3.0):
	start_pos = from
	end_pos = to
	color = p_color
	width = p_width
	_timer = duration
	queue_redraw()

func _process(delta):
	_timer -= delta
	if _timer <= 0.0:
		queue_free()
	else:
		queue_redraw()

func _draw():
	var ratio = _timer / duration
	var current_color = Color(color.r, color.g, color.b, color.a * ratio)
	
	if width < 10.0:
		# Standard projectile tracer
		draw_line(start_pos - global_position, end_pos - global_position, current_color, width * ratio)
		# Draw muzzle flash circle
		draw_circle(start_pos - global_position, 8.0 * ratio, Color(1.0, 0.7, 0.2, 0.9 * ratio))
	else:
		# Melee/Explosion: Draw expanding shockwave ring at target
		draw_arc(end_pos - global_position, 40.0 * (1.0 - ratio), 0.0, TAU, 32, current_color, 4.0 * ratio, true)
