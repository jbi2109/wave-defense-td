extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus

var spawn_point: Vector2 = Vector2(50, 50) # Fixed spawn point top-left

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
var spawn_rate: float = 0.05 # 20 enemies per second trickling out
var spawn_timer: float = 0.0

var time_between_waves: float = 3.0
var wave_timer: float = 2.0 # Start first wave quickly

var is_spawning: bool = false

var is_game_over: bool = false

func _ready():
    # Wait for nodes to be ready
    await get_tree().process_frame
    flow_field.generate_field(nexus.global_position)
    
    GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
    $HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_button_pressed)
    $HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(_on_restart_button_pressed)

func _on_restart_button_pressed():
    get_tree().reload_current_scene()

func _process(delta):
    if is_game_over: return
    
    if is_spawning:
        spawn_timer -= delta
        if spawn_timer <= 0:
            _spawn_single_enemy()
            spawn_timer = spawn_rate
            
        if enemies_spawned >= enemies_to_spawn:
            is_spawning = false
            $HUD/Overlay/NextWaveButton.visible = true
    elif enemy_manager.active_count == 0 and not is_game_over:
        $HUD/Overlay/NextWaveButton.visible = true

func _on_next_wave_button_pressed():
    if not is_spawning and enemy_manager.active_count == 0:
        _start_next_wave()
        $HUD/Overlay/NextWaveButton.visible = false

func _on_nexus_destroyed():
    is_game_over = true
    is_spawning = false
    $HUD/Overlay/GameOverContainer.visible = true
    $HUD/Overlay/NextWaveButton.visible = false
    print("GAME OVER")

func _start_next_wave():
    current_wave += 1
    # Scale difficulty: Wave 1 = 150, Wave 2 = 200...
    enemies_to_spawn = 100 + (current_wave * 50) 
    enemies_spawned = 0
    is_spawning = true
    spawn_timer = 0
    print("--- WAVE ", current_wave, " STARTED! Spawning ", enemies_to_spawn, " enemies ---")

func _spawn_single_enemy():
    # Add slight jitter to the fixed spawn point to prevent stacking exactly on top
    var offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
    enemy_manager.spawn_enemy(spawn_point + offset)
    enemies_spawned += 1
