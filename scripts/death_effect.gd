extends CPUParticles2D

func _ready():
	# Automatically clean up when particles finish emitting
	one_shot = true
	emitting = true
	finished.connect(queue_free)
