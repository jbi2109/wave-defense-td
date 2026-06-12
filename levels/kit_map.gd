@tool
extends Node2D
class_name KitMap

# Root script for maps assembled from the reusable Polygon2D piece kit (levels/pieces/).
# Unlike Map1Gen/Map2Gen there is NO mask — walkability is the union of the child pieces:
# Polygon2D nodes in group "map_path" (walkable) minus group "map_wall" (dirt islands), read
# by battle.gd::_setup_map_logic. This script only supplies the per-map world size that
# battle.gd::_apply_map_config uses to cover-fit the camera. Spawn/nexus come from the
# SpawnMarker/NexusMarker children. Build a map by dragging pieces from levels/pieces/ onto
# the 160-unit grid and rotating them in 90° steps so corridors line up.

# Per-map gameplay config (waves, base HP, starting gold) — read by battle.gd.
@export var config: MapConfig

@export var world_size: Vector2 = Vector2(3840, 1786):
	set(value):
		world_size = value
		if Engine.is_editor_hint():
			queue_redraw()

func _draw() -> void:
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, world_size), Color(1, 1, 1, 0.25), false, 6.0)
