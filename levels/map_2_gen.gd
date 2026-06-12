@tool
extends Node2D
class_name Map2Gen

# Map-generation helper for map_2 (in-game "Map 2 Serpentine"), mask-driven "orc way"
# pipeline — same as map_1 (Map1Gen) but with a central ISLAND obstacle.
#
# Walkable = inside the rounded corridor ROUTE *and not* inside the rounded ISLAND.
# The baked mask (white = walkable) feeds battle.gd's SDF + flow field. The two
# rounded polygons are reused as the visual Grass_Path (corridor) and Dirt_Mound
# (island) fills. See docs/ARCHITECTURE.md "Map Building Pipeline".
#
# Bake with tools/gen_map_2_mask.py (the practical offline baker; Godot game_eval
# stalls on the heavy loop). Keep ROUTE/ISLAND/round_polygon in sync with it.

const WORLD_SIZE := Vector2(1920, 1080)
const MASK_SIZE := Vector2i(480, 270)          # quarter of world res (~4px/cell, matches fine grid)
const MASK_PATH := "res://levels/map_2_mask.png"
const CORNER_RADIUS: float = 60.0              # corridor rounding (match map_1)
const ISLAND_RADIUS: float = 50.0              # island corner smoothing (keeps irregular silhouette)

# Cleaned serpentine corridor outline (snapped near-axis segments straight, deduped,
# edges snapped to 0 / 1920). Left mouth y200..415 (spawner), right mouth y200..450 (nexus).
static var ROUTE := PackedVector2Array([
	Vector2(0, 200), Vector2(850, 200), Vector2(915, 250), Vector2(915, 720),
	Vector2(965, 760), Vector2(1170, 760), Vector2(1225, 720), Vector2(1235, 240),
	Vector2(1300, 200), Vector2(1920, 200), Vector2(1920, 450), Vector2(1470, 450),
	Vector2(1470, 1010), Vector2(250, 1010), Vector2(215, 950), Vector2(215, 460),
	Vector2(180, 415), Vector2(0, 415),
])

# Central island obstacle (irregular blob with a right-side pinch). Smoothed by
# round_polygon(ISLAND_RADIUS); the per-corner half-edge clamp keeps the pinch.
static var ISLAND := PackedVector2Array([
	Vector2(423, 402), Vector2(599, 346), Vector2(749, 366), Vector2(703, 548),
	Vector2(767, 869), Vector2(542, 897), Vector2(363, 708),
])

# The baked mask. battle.gd calls get_mask_image() to drive obstacle/SDF/flow.
# Per-map gameplay config (waves, base HP, starting gold) - read by battle.gd.
@export var config: MapConfig

@export var mask_path: String = MASK_PATH

# Load the walkable mask as an Image. Prefers the imported Texture2D (export-safe);
# falls back to a raw Image.load(). Returns null if unreadable (battle.gd then
# falls back to the Grass_Path polygon).
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
		push_warning("Map2Gen: failed to load mask at %s" % mask_path)
		return null
	return img

# Replace each sharp corner of a closed polygon with a smooth quadratic-Bezier
# fillet. radius is clamped per-corner to half the shorter adjacent edge so short
# segments / pinches survive. Vertices on the left/right map edges (x≈0 / x≈WORLD
# width) are kept square — the corridor mouths behind spawner/nexus. Island points
# are never near those edges, so the same function smooths the island cleanly.
static func round_polygon(points: PackedVector2Array, radius: float, samples: int = 8) -> PackedVector2Array:
	var n := points.size()
	if n < 3:
		return points
	var out := PackedVector2Array()
	for i in n:
		var p0 := points[(i - 1 + n) % n]
		var p1 := points[i]
		var p2 := points[(i + 1) % n]
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
		if dir_in.dot(dir_out) > 0.999:
			out.append(p1)
			continue
		var r: float = min(radius, len_in * 0.5, len_out * 0.5)
		var a := p1 - dir_in * r
		var c := p1 + dir_out * r
		for s in range(samples + 1):
			var t := float(s) / float(samples)
			var omt := 1.0 - t
			out.append(omt * omt * a + 2.0 * omt * t * p1 + t * t * c)
	return out

# Rasterise walkable = inside rounded corridor AND NOT inside rounded island, to an
# L8 mask (white = walkable). Returns {err, route, island} — route/island are the
# rounded polygons reused for the visual Grass_Path / Dirt_Mound fills.
static func bake_mask_to_file() -> Dictionary:
	var route := round_polygon(ROUTE, CORNER_RADIUS)
	var island := round_polygon(ISLAND, ISLAND_RADIUS)
	var data := PackedByteArray()
	data.resize(MASK_SIZE.x * MASK_SIZE.y)
	for py in MASK_SIZE.y:
		var row := py * MASK_SIZE.x
		var wy := (py + 0.5) / float(MASK_SIZE.y) * WORLD_SIZE.y
		for px in MASK_SIZE.x:
			var wp := Vector2((px + 0.5) / float(MASK_SIZE.x) * WORLD_SIZE.x, wy)
			var walkable := Geometry2D.is_point_in_polygon(wp, route) and not Geometry2D.is_point_in_polygon(wp, island)
			data[row + px] = 255 if walkable else 0
	var img := Image.create_from_data(MASK_SIZE.x, MASK_SIZE.y, false, Image.FORMAT_L8, data)
	var err := img.save_png(MASK_PATH)
	return {"err": err, "route": route, "island": island}
