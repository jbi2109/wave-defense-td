extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus

var spawn_timer: float = 0.0

func _ready():
    # Wait for nodes to be ready
    await get_tree().process_frame
    flow_field.generate_field(nexus.global_position)

func _process(delta):
    spawn_timer -= delta
    if spawn_timer <= 0:
        _spawn_wave()
        spawn_timer = 2.0

func _spawn_wave():
    var spawn_pos = Vector2(randf_range(0, 1152), randf_range(0, 648))
    # Ensure spawn is far from nexus
    while spawn_pos.distance_to(nexus.global_position) < 300:
        spawn_pos = Vector2(randf_range(0, 1152), randf_range(0, 648))
    
    for i in range(10): # Spawn 10 at a time
        enemy_manager.spawn_enemy(spawn_pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)))
