extends CharacterBody2D
class_name Enemy

@export var speed: float = 120.0
var health: float = 10.0

@onready var flow_field = get_node("/root/Main/FlowFieldManager")
@onready var nexus = get_node("/root/Main/Nexus")

func _physics_process(delta):
	if not is_instance_valid(flow_field):
		return
		
	var dir = flow_field.get_direction(global_position)
	
	# Apply velocity
	velocity = velocity.lerp(dir * speed, 10.0 * delta)
	
	# Rotate sprite to face direction
	if velocity.length_squared() > 10:
		$Sprite2D.flip_h = velocity.x < 0
	
	move_and_slide()
	
	if is_instance_valid(nexus) and global_position.distance_squared_to(nexus.global_position) < 2500:
		GlobalEvents.nexus_damaged.emit(1)
		queue_free()

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		queue_free()
