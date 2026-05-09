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
	
	# Soft separation from other enemies to prevent exact stacking
	var separation = Vector2.ZERO
	var neighbors = get_tree().get_nodes_in_group("enemies")
	for neighbor in neighbors:
		if neighbor != self:
			var dist_sq = global_position.distance_squared_to(neighbor.global_position)
			if dist_sq > 0.1 and dist_sq < 144.0: # 12px radius for tighter packing
				var push_strength = 1.0 - (sqrt(dist_sq) / 12.0)
				separation += (global_position - neighbor.global_position).normalized() * (speed * push_strength * 0.4)
	
	if separation != Vector2.ZERO:
		velocity += separation
	
	# Rotate sprite to face direction
	if velocity.length_squared() > 10:
		$Sprite2D.flip_h = velocity.x < 0
	
	move_and_slide()
	
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		# Add a tiny bounce to slide off walls smoothly, not violently
		velocity += col.get_normal() * speed * 2.0 * delta
		
	if is_instance_valid(nexus) and global_position.distance_squared_to(nexus.global_position) < 2500:
		GlobalEvents.nexus_damaged.emit(1)
		queue_free()

func take_damage(amount: float):
	health -= amount
	if health <= 0:
		queue_free()
