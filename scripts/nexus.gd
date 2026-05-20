@tool
extends StaticBody2D

@export var health: int = 1000

@export var extents: Vector2 = Vector2(10, 130):
	set(value):
		extents = value
		if Engine.is_editor_hint():
			queue_redraw()

var _max_health: int = 1000

func _ready():
	_max_health = health
	if not Engine.is_editor_hint():
		GlobalEvents.nexus_damaged.connect(_on_damaged)
	if Engine.is_editor_hint():
		queue_redraw()

func _draw():
	if Engine.is_editor_hint():
		draw_rect(Rect2(-extents, extents * 2), Color.BLUE, false, 4.0)
		var font = ThemeDB.get_fallback_font()
		draw_string(font, Vector2(-20, -extents.y - 10), "NEXUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)

func has_point(point: Vector2) -> bool:
	return Rect2(-extents, extents * 2).has_point(to_local(point))

func _on_damaged(amount: int):
	health -= amount
	health  = maxi(health, 0)
	# Emit to HUD via Globals signal
	Globals.baseHpChanged.emit(health, _max_health)
	if health <= 0:
		GlobalEvents.nexus_destroyed.emit()
