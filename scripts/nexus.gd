extends StaticBody2D

@export var health: int = 100

func _ready():
	GlobalEvents.nexus_damaged.connect(_on_damaged)

func _on_damaged(amount: int):
	health -= amount
	print("Nexus health: ", health)
	if health <= 0:
		GlobalEvents.nexus_destroyed.emit()
		print("Nexus DESTROYED")
