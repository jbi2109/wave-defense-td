extends MultiMeshInstance2D
class_name EnemyManager

@export var max_enemies: int = 2000
@export var enemy_speed: float = 100.0
@export var flow_field: FlowFieldManager

var active_count: int = 0
var positions = PackedVector2Array()
var velocities = PackedVector2Array()
var healths = PackedFloat32Array()

func _ready():
    multimesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_2D
    multimesh.use_colors = true
    multimesh.instance_count = max_enemies
    
    positions.resize(max_enemies)
    velocities.resize(max_enemies)
    healths.resize(max_enemies)
    
    # Initialize hidden
    for i in range(max_enemies):
        multimesh.set_instance_transform_2d(i, Transform2D(0, Vector2(-1000, -1000)))

func spawn_enemy(pos: Vector2):
    if active_count < max_enemies:
        positions[active_count] = pos
        velocities[active_count] = Vector2.ZERO
        healths[active_count] = 10.0
        active_count += 1

func _physics_process(delta):
    if not flow_field: return
    
    for i in range(active_count):
        var pos = positions[i]
        var dir = flow_field.get_direction(pos)
        
        # Simple steering toward flow field direction
        velocities[i] = velocities[i].lerp(dir * enemy_speed, 5.0 * delta)
        positions[i] += velocities[i] * delta
        
        # Update MultiMesh transform
        var t = Transform2D(velocities[i].angle(), positions[i])
        multimesh.set_instance_transform_2d(i, t)
        
        # Basic Nexus collision check (simplified)
        if positions[i].length_squared() < 1600: # 40 pixels radius
            GlobalEvents.nexus_damaged.emit(1)
            # "Kill" enemy by swapping with last active
            _remove_enemy(i)

func _remove_enemy(index):
    active_count -= 1
    if index < active_count:
        positions[index] = positions[active_count]
        velocities[index] = velocities[active_count]
        healths[index] = healths[active_count]
    # Move inactive instance out of view
    multimesh.set_instance_transform_2d(active_count, Transform2D(0, Vector2(-1000, -1000)))
