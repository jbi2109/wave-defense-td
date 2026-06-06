extends Control
class_name WaveAnnouncement

@onready var label: Label = $Label

func _ready():
	modulate.a = 0.0
	GlobalEvents.wave_started.connect(_on_wave_started)

func _on_wave_started(wave_num: int, _enemy_count: int):
	var msg = "WAVE %d" % wave_num
	match wave_num:
		1:
			msg = "WAVE 1\nDEFEND THE NEXUS"
		3:
			msg = "WAVE 3\nRUNNERS UNLEASHED"
		5:
			msg = "WAVE 5\nMINI BOSS INCOMING"
		10:
			msg = "WAVE 10\nMINI BOSS DUALITY"
		15:
			msg = "WAVE 15\nTHE FINAL BATTLE"
			
	label.text = msg
	
	# Create tween animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Reset state
	modulate.a = 0.0
	label.scale = Vector2(0.8, 0.8)
	label.pivot_offset = label.size / 2.0
	
	# Fade in and scale up
	tween.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Wait 1.5s then fade out
	tween.chain().tween_interval(1.5)
	
	var fade_out = tween.chain().set_parallel(true)
	fade_out.tween_property(self, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_out.tween_property(label, "scale", Vector2(1.1, 1.1), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
