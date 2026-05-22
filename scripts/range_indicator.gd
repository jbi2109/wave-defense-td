extends Node2D
class_name RangeIndicator

var radius: float = 0.0:
	set(value):
		radius = value
		queue_redraw()

var fill_color: Color = Color(0.2, 0.6, 1.0, 0.12)
var line_color: Color = Color(0.2, 0.6, 1.0, 0.45)

func _draw():
	if radius > 0.0:
		draw_circle(Vector2.ZERO, radius, fill_color)
		# Draw a smooth dashed-looking or standard line
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, line_color, 2.5, true)
