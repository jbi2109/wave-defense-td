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

@onready var ground_layer = $GroundLayer

func _ready():
	# Wait for nodes to be ready
	await get_tree().process_frame
	_setup_map_visuals()
	flow_field.generate_field(nexus.global_position)
	
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_button_pressed)
	$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(_on_restart_button_pressed)

func _setup_map_visuals():
	var tileset = ground_layer.tile_set
	if not tileset:
		tileset = TileSet.new()
		ground_layer.tile_set = tileset
	
	# Ensure atlas sources exist (0 for Grass, 1 for Dirt)
	if tileset.get_source_count() == 0:
		var grass_tex = load("res://assets/grass_noise.tres")
		var dirt_tex = load("res://assets/dirt_noise.tres")
		
		# Apply color gradients via script since tool is limited
		var grass_grad = Gradient.new()
		grass_grad.add_point(0, Color("#2d5a27"))
		grass_grad.add_point(1, Color("#4a8a3f"))
		grass_tex.color_ramp = grass_grad
		
		var dirt_grad = Gradient.new()
		dirt_grad.add_point(0, Color("#5a3e2b"))
		dirt_grad.add_point(1, Color("#8b6b4f"))
		dirt_tex.color_ramp = dirt_grad
		grass_source.texture = grass_tex
		grass_source.texture_region_size = Vector2i(32, 32)
		grass_source.create_tile(Vector2i(0, 0))
		tileset.add_source(grass_source, 0)
		
		var dirt_source = TileSetAtlasSource.new()
		dirt_source.texture = dirt_tex
		dirt_source.texture_region_size = Vector2i(32, 32)
		dirt_source.create_tile(Vector2i(0, 0))
		tileset.add_source(dirt_source, 1)

	# Fill background with "grass"
	for x in range(-5, 45):
		for y in range(-5, 25):
			ground_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	# Draw path
	var current = Vector2i(spawn_point / 32.0)
	var target = Vector2i(nexus.global_position / 32.0)
	
	# Draw a thicker dirt path
	for x in range(min(current.x, target.x), max(current.x, target.x) + 1):
		ground_layer.set_cell(Vector2i(x, current.y), 1, Vector2i(0, 0))
		ground_layer.set_cell(Vector2i(x, current.y+1), 1, Vector2i(0, 0))
	for y in range(min(current.y, target.y), max(current.y, target.y) + 1):
		ground_layer.set_cell(Vector2i(target.x, y), 1, Vector2i(0, 0))
		ground_layer.set_cell(Vector2i(target.x+1, y), 1, Vector2i(0, 0))

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
			# Button will only show once all enemies are dead (checked in next block)
	elif enemy_manager.active_count == 0 and not is_game_over and current_wave > 0:
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
