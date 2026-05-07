extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var grass_layer = $GrassLayer
@onready var dirt_layer = $DirtLayer

var spawn_point: Vector2 = Vector2(0, 272) # Left side entry

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
var spawn_rate: float = 0.05
var spawn_timer: float = 0.0

var is_spawning: bool = false
var is_game_over: bool = false

func _ready():
	await get_tree().process_frame
	_setup_map_visuals()
	flow_field.generate_field(nexus.global_position)
	
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_button_pressed)
	$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(_on_restart_button_pressed)

func _setup_map_visuals():
	# Use Solid Colors for visibility
	grass_layer.tile_set = TileSet.new()
	grass_layer.tile_set.tile_size = Vector2i(32, 32)
	grass_layer.modulate = Color("#3a6b32") # Dark Green (Walls)
	
	dirt_layer.tile_set = TileSet.new()
	dirt_layer.tile_set.tile_size = Vector2i(32, 32)
	dirt_layer.modulate = Color("#8b6b4f") # Dirt Brown (Path)

	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex = ImageTexture.create_from_image(img)
	var source = TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(32, 32)
	source.create_tile(Vector2i(0, 0))
	grass_layer.tile_set.add_source(source, 0)
	dirt_layer.tile_set.add_source(source, 0)

	# 1. Fill EVERYTHING with Grass (Walls)
	grass_layer.clear()
	for x in range(-5, 65):
		for y in range(-5, 40):
			grass_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	# 2. Draw Complex Dirt Path based on new reference image
	dirt_layer.clear()
	var path_cells = []
	
	# Start (Left edge off-screen) to Top-Middle
	for x in range(-5, 20):
		for y in range(6, 12): path_cells.append(Vector2i(x, y))
	
	# Middle-Top Horizontal
	for x in range(20, 30):
		for y in range(4, 10): path_cells.append(Vector2i(x, y))
		
	# Top Horizontal to Right
	for x in range(30, 65):
		for y in range(4, 9): path_cells.append(Vector2i(x, y))
		
	# Right Drop Down
	for y in range(9, 20):
		for x in range(20, 26): path_cells.append(Vector2i(x, y))
	
	# Middle Loop Back Left
	for x in range(12, 26):
		for y in range(15, 21): path_cells.append(Vector2i(x, y))
		
	# Left Drop Down
	for y in range(21, 28):
		for x in range(12, 18): path_cells.append(Vector2i(x, y))
		
	# Bottom Loop Right
	for x in range(12, 35):
		for y in range(27, 33): path_cells.append(Vector2i(x, y))
		
	# Dip down
	for y in range(33, 36):
		for x in range(30, 36): path_cells.append(Vector2i(x, y))
		
	# Bottom Right Exit (Extend off-screen)
	for x in range(36, 65):
		for y in range(20, 26): path_cells.append(Vector2i(x, y))
		
	# Connecting piece
	for y in range(26, 36):
		for x in range(36, 42): path_cells.append(Vector2i(x, y))

	for cell in path_cells:
		dirt_layer.set_cell(cell, 0, Vector2i(0, 0))
		
	# Update Flow Field Obstacles based on Path
	for x in range(-5, 80):
		for y in range(-5, 50):
			var is_path = path_cells.has(Vector2i(x, y))
			flow_field.set_obstacle(Vector2i(x, y), not is_path)
			
	# Move Nexus to End of Path (Right side)
	nexus.global_position = Vector2(1900, 750)
	
	# Position Turrets in Grass pockets
	var t1 = get_node_or_null("Turret1")
	if t1: t1.global_position = Vector2(550, 400)
	var t2 = get_node_or_null("Turret2")
	if t2: t2.global_position = Vector2(750, 800)

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

func _start_next_wave():
	current_wave += 1
	enemies_to_spawn = 100 + (current_wave * 50) 
	enemies_spawned = 0
	is_spawning = true
	spawn_timer = 0
	print("--- WAVE ", current_wave, " STARTED! ---")

func _spawn_single_enemy():
	# Tiny jitter so they are guaranteed to spawn exactly on the path
	var offset = Vector2(randf_range(-2, 2), randf_range(-2, 2))
	enemy_manager.spawn_enemy(spawn_point + offset)
	enemies_spawned += 1
