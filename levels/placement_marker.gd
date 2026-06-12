@tool
extends Marker2D
class_name PlacementMarker

# Draggable editor marker for a map's spawn or nexus location. battle.gd::_apply_map_config
# reads its global position (+ extents) at load and relocates $EnemySpawner / $Nexus there.
# Mirrors the spawner.gd / nexus.gd editor gizmos so the spot is visible and movable in the
# 2D editor — drag it to move where enemies spawn / where the nexus sits.

@export_enum("spawn", "nexus") var kind: String = "spawn":
	set(value):
		kind = value
		if Engine.is_editor_hint():
			queue_redraw()

@export var extents: Vector2 = Vector2(60, 200):
	set(value):
		extents = value
		if Engine.is_editor_hint():
			queue_redraw()

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var col := Color.RED if kind == "spawn" else Color.DODGER_BLUE
	draw_rect(Rect2(-extents, extents * 2), col, false, 5.0)
	var font := ThemeDB.get_fallback_font()
	draw_string(font, Vector2(-extents.x, -extents.y - 12), kind.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
