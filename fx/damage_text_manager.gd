extends Node2D
class_name DamageTextManager

static var instance: DamageTextManager = null

class DamageText:
	var position: Vector2
	var text: String
	var velocity: Vector2
	var color: Color
	var life: float
	var max_life: float

var active_texts: Array[DamageText] = []
var font: Font

func _ready():
	instance = self
	font = ThemeDB.fallback_font
	z_index = 20 # Draw above entities

func spawn_damage_text(pos: Vector2, amount: float, is_crit: bool = false):
	if not SaveManager.settings.get("show_damage_numbers", true):
		return
	var dt = DamageText.new()
	dt.position = pos + Vector2(randf_range(-15, 15), randf_range(-5, 5))
	
	if amount < 1.0:
		dt.text = "%.1f" % amount
	else:
		dt.text = str(int(amount))
		
	# Random upward velocity
	dt.velocity = Vector2(randf_range(-40, 40), randf_range(-90, -130))
	dt.max_life = 0.6 if is_crit else 0.45
	dt.life = dt.max_life
	
	if is_crit:
		dt.color = Color(1.0, 0.2, 0.2) # Bright Red
	else:
		dt.color = Color(1.0, 0.9, 0.3) # Soft Yellow
		
	active_texts.append(dt)
	queue_redraw()

func _process(delta):
	if active_texts.is_empty():
		return
		
	var i = active_texts.size() - 1
	while i >= 0:
		var dt = active_texts[i]
		dt.life -= delta
		if dt.life <= 0.0:
			active_texts.remove_at(i)
		else:
			dt.position += dt.velocity * delta
			dt.velocity.y *= 0.95 # Slow vertical movement down
		i -= 1
		
	queue_redraw()

func _draw():
	if not font:
		return
		
	for dt in active_texts:
		var alpha = clampf(dt.life / dt.max_life, 0.0, 1.0)
		var col = dt.color
		col.a = alpha
		var outline_col = Color(0, 0, 0, alpha * 0.8)
		
		var size = 15
		if dt.max_life > 0.5: # crit
			size = 20
			
		var draw_pos = dt.position
		
		# Draw outline first
		draw_string_outline(font, draw_pos, dt.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, 3, outline_col)
		# Draw filled text
		draw_string(font, draw_pos, dt.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)
