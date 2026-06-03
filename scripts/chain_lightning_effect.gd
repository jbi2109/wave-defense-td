extends Node2D

var _timer: float = 0.0
var duration: float = 0.5
var bolt_segments: Array = []  # Array of arrays of Vector2 (one bolt per hit enemy)

# Legacy init for backwards compat (unused now)
func init(pts: Array):
	init_bolts_from_above(pts)

func init_bolts_from_above(hit_positions: Array):
	bolt_segments = []
	for target_pos in hit_positions:
		# Bolt comes from 400px above the enemy straight down
		var sky_pos = target_pos + Vector2(randf_range(-15, 15), -400.0)
		bolt_segments.append(_generate_lightning_bolt(sky_pos, target_pos))

func _generate_lightning_bolt(from: Vector2, to: Vector2) -> Array:
	var bolt = [from]
	var dist = from.distance_to(to)
	var steps = int(maxf(5, dist / 20.0))
	var dir = (to - from).normalized()
	var normal = Vector2(-dir.y, dir.x)
	
	for i in range(1, steps):
		var ratio = float(i) / steps
		var base_pos = from.lerp(to, ratio)
		# More jitter near the middle, less at endpoints
		var jitter_amount = 18.0 * sin(ratio * PI)
		var offset = normal * randf_range(-jitter_amount, jitter_amount)
		bolt.append(base_pos + offset)
		
	bolt.append(to)
	return bolt

func _process(delta):
	_timer += delta
	if _timer >= duration:
		queue_free()
	else:
		queue_redraw()

func _draw():
	if bolt_segments.is_empty(): return
	
	var alpha = 1.0 - (_timer / duration)
	if alpha <= 0.0: return
	
	var core_color = Color(0.85, 0.9, 1.0, alpha)
	var glow_color = Color(0.4, 0.5, 1.0, alpha * 0.4)
	var bright_color = Color(1.0, 1.0, 1.0, alpha * 0.8)
	
	# Draw each bolt (glow pass, then core, then bright center)
	for bolt in bolt_segments:
		for i in range(bolt.size() - 1):
			var p1 = to_local(bolt[i])
			var p2 = to_local(bolt[i + 1])
			draw_line(p1, p2, glow_color, 8.0)
		for i in range(bolt.size() - 1):
			var p1 = to_local(bolt[i])
			var p2 = to_local(bolt[i + 1])
			draw_line(p1, p2, core_color, 3.0)
		for i in range(bolt.size() - 1):
			var p1 = to_local(bolt[i])
			var p2 = to_local(bolt[i + 1])
			draw_line(p1, p2, bright_color, 1.0)
		
		# Impact flash at bottom of bolt
		var impact = to_local(bolt[bolt.size() - 1])
		var flash_size = 12.0 * alpha
		draw_circle(impact, flash_size, Color(0.7, 0.8, 1.0, alpha * 0.6))
		draw_circle(impact, flash_size * 0.5, Color(1.0, 1.0, 1.0, alpha * 0.8))
