extends Node2D

var damage: float = 0.0
var radius: float = 0.0
var duration: float = 0.0
var timer: float = 0.0

@onready var sprite = Sprite2D.new()

func init(pos: Vector2, d: float, r: float, dur: float):
	global_position = pos
	damage = d
	radius = r
	duration = dur
	timer = dur
	
	sprite.texture = load("res://assets/turrets/dynamite.png")
	sprite.scale = Vector2(0.6, 0.6)
	add_child(sprite)

func _process(delta):
	timer -= delta
	
	# Flash the sprite red as it gets closer to exploding
	var speed = 0.1 + (timer / duration) * 0.3
	var flash = fmod(timer, speed) < (speed / 2.0)
	sprite.modulate = Color(2.0, 0.5, 0.5) if flash else Color.WHITE
	
	if timer <= 0.0:
		explode()

func explode():
	if GPUSim:
		GPUSim.apply_aoe_damage(global_position, radius, damage, false)
	
	var main_node = get_node_or_null("/root/Battle")
	if main_node and main_node.has_method("_spawn_death_particles"):
		main_node._spawn_death_particles(global_position, 5) # BigBoss explosion
		
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(0.5, 15.0)
		
	var sound_mgr = get_node_or_null("/root/SoundManager")
	if sound_mgr and sound_mgr.has_method("play_sfx"):
		sound_mgr.play_sfx("shoot_mortar")
		
	queue_free()
