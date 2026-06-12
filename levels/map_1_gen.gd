@tool
extends Node2D
class_name Map1Gen

# Map-generation helper for the "orc way" mask-driven map pipeline.
#
# The studio game `Sir, we have an orc problem` builds maps from a painted B&W
# mask (white = walkable, black = wall) which is fed into an SDF + flow field.
# This repo already runs that downstream pipeline in `battle.gd` /
# `flow_field_manager.gd`; this script supplies the *input*: a rounded-corner
# mask PNG plus the matching rounded walkable polygon used for the visual fill.
#
# Authoring a new map = define ROUTE + CORNER_RADIUS, call `bake_mask_to_file()`,
# then set the map root's `mask_path` to the baked PNG. See docs/ARCHITECTURE.md
# "Map Building Pipeline".

const WORLD_SIZE := Vector2(1920, 1080)
const MASK_SIZE := Vector2i(480, 270)          # quarter of world res (~4px/cell, matches fine grid)
const MASK_PATH := "res://levels/map_1_mask.png"
const CORNER_RADIUS: float = 60.0              # world units; "moderate" rounding

# Original sharp 12-point walkable corridor outline (from the pre-round map_2).
# static var (not const): a PackedVector2Array built from Vector2() isn't a
# constant expression in GDScript.
static var ROUTE := PackedVector2Array([
	Vector2(0, 200), Vector2(600, 200), Vector2(600, 700), Vector2(1100, 700),
	Vector2(1100, 200), Vector2(1920, 200), Vector2(1920, 400), Vector2(1300, 400),
	Vector2(1300, 900), Vector2(400, 900), Vector2(400, 400), Vector2(0, 400),
])

# Path to the baked mask. battle.gd calls get_mask_image() to drive the
# obstacle/SDF/flow pipeline — white = walkable.
@export var mask_path: String = MASK_PATH

# Load the walkable mask as an Image. Prefers the imported Texture2D (export-safe);
# falls back to a raw Image.load() if the import sidecar is missing. Returns null
# if unreadable, in which case battle.gd falls back to the Grass_Path polygon.
func get_mask_image() -> Image:
	if mask_path.is_empty():
		return null
	# Prefer the imported Texture2D (export-safe) when it exists; else read the raw
	# PNG. The exists() guard avoids ResourceLoader error spam before the editor
	# has generated the .import sidecar.
	if ResourceLoader.exists(mask_path):
		var tex := ResourceLoader.load(mask_path) as Texture2D
		if tex:
			return tex.get_image()
	var img := Image.new()
	if img.load(mask_path) != OK:
		push_warning("Map1Gen: failed to load mask at %s" % mask_path)
		return null
	return img

# Replace each sharp corner of a closed polygon with a smooth quadratic-Bezier
# fillet. radius is clamped per-corner to half the shorter adjacent edge so
# short segments can't self-intersect. Near-collinear vertices pass through.
static func round_polygon(points: PackedVector2Array, radius: float, samples: int = 8) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	for i in n:
		var p0 := points[(i - 1 + n) % n]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
		# Keep corners on the left/right map edges square — these are the corridor
		# openings behind the spawner (x≈0) and behind the nexus (x≈WORLD width),
		# so the spawn/arrival mouths stay flush instead of pinched by a fillet.
		if p1.x <= 1.0 or p1.x >= WORLD_SIZE.x - 1.0:
			out.append(p1)
			continue
		var v_in := p1 - p0
		var v_out := p2 - p1
		var len_in := v_in.length()
		var len_out := v_out.length()
		if len_in < 0.001 or len_out < 0.001:
			out.append(p1)
			continue
		var dir_in := v_in / len_in
		var dir_out := v_out / len_out
		if dir_in.dot(dir_out) > 0.999:  # straight-through: keep vertex
			out.append(p1)
			continue
		var r: float = min(radius, len_in * 0.5, len_out * 0.5)
		var a := p1 - dir_in * r    # tangent point on incoming edge
		var c := p1 + dir_out * r   # tangent point on outgoing edge
		for s in range(samples + 1):
			var t := float(s) / float(samples)
			var omt := 1.0 - t
			out.append(omt * omt * a + 2.0 * omt * t * p1 + t * t * c)
	return out

# Rasterise the rounded walkable polygon into an L8 mask (white = walkable) and
# save it to MASK_PATH. Returns {err, poly} — poly is the rounded polygon, reused
# as the visual Grass_Path fill so render and simulation match exactly.
static func bake_mask_to_file() -> Dictionary:
	var poly := round_polygon(ROUTE, CORNER_RADIUS)
	var data := PackedByteArray()
	data.resize(MASK_SIZE.x * MASK_SIZE.y)
	for py in MASK_SIZE.y:
		var row := py * MASK_SIZE.x
		var wy := (py + 0.5) / float(MASK_SIZE.y) * WORLD_SIZE.y
		for px in MASK_SIZE.x:
			var wp := Vector2((px + 0.5) / float(MASK_SIZE.x) * WORLD_SIZE.x, wy)
			data[row + px] = 255 if Geometry2D.is_point_in_polygon(wp, poly) else 0
	var img := Image.create_from_data(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_L8, data)
	var err := img.save_png(MASK_PATH)
	return {"err": err, "poly": poly}
