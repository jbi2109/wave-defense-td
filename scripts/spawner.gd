@tool
extends Marker2D
class_name EnemySpawner

@export var extents: Vector2 = Vector2(50, 200):
	set(value):
		extents = value
		if Engine.is_editor_hint():
			queue_redraw()

func _ready():
	add_to_group("spawner")
	
	# Visual indicator for editor
	if Engine.is_editor_hint():
		queue_redraw()

func _draw():
	if Engine.is_editor_hint():
		draw_rect(Rect2(-extents, extents * 2), Color.RED, false, 4.0)
		# Use a simpler way to get font that works in all 4.x versions
		var font = ThemeDB.get_fallback_font()
		draw_string(font, Vector2(-25, -extents.y - 10), "SPAWNER", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

func get_random_spawn_point() -> Vector2:
	var rx = randf_range(-extents.x, extents.x)
	var ry = randf_range(-extents.y, extents.y)
	return to_global(Vector2(rx, ry))
