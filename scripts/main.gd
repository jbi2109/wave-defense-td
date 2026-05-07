extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var grass_layer = $GrassLayer
@onready var dirt_layer = $DirtLayer

var spawn_point: Vector2 = Vector2(0, 176) # Left side entry

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
	# Grass Layer (Background/Walls)
	grass_layer.tile_set = TileSet.new()
	grass_layer.tile_set.tile_size = Vector2i(32, 32)
	grass_layer.modulate = Color("#3a6b32") # Dark Green (Walls)
	
	# Dirt Layer (Path)
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
	
	# 2. Draw Complex Dirt Path exactly like "Sir, We Have an Orc Problem"
	dirt_layer.clear()
	var path_cells = []
	
	# Start Top-Left, moving Right
	for x in range(-5, 22):
		for y in range(4, 9): path_cells.append(Vector2i(x, y))
	
	# Drop Down
	for y in range(9, 22):
		for x in range(17, 22): path_cells.append(Vector2i(x, y))
		
	# Loop Back Left
	for x in range(12, 17):
		for y in range(17, 22): path_cells.append(Vector2i(x, y))
		
	# Drop Down again
	for y in range(22, 28):
		for x in range(12, 17): path_cells.append(Vector2i(x, y))
		
	# Move Right across bottom
	for x in range(12, 38):
		for y in range(28, 33): path_cells.append(Vector2i(x, y))
		
	# Move UP
	for y in range(12, 28):
		for x in range(33, 38): path_cells.append(Vector2i(x, y))
		
	# Move Right across top
	for x in range(38, 50):
		for y in range(12, 17): path_cells.append(Vector2i(x, y))
		
	# Drop Down
	for y in range(17, 25):
		for x in range(45, 50): path_cells.append(Vector2i(x, y))
		
	# Move Right to Nexus
	for x in range(50, 65):
		for y in range(20, 25): path_cells.append(Vector2i(x, y))

	for cell in path_cells:
		dirt_layer.set_cell(cell, 0, Vector2i(0, 0))
		
	# Update Flow Field Obstacles based on Path
	for x in range(-5, 80):
		for y in range(-5, 50):
			var is_path = path_cells.has(Vector2i(x, y))
			flow_field.set_obstacle(Vector2i(x, y), not is_path)
			
	# Move Nexus to End of Path (Right side)
	nexus.global_position = Vector2(1900, 720)
	
	# Position Turrets in Grass pockets (island in the middle)
	var t1 = get_node_or_null("Turret1")
	if t1: t1.global_position = Vector2(850, 450)
	var t2 = get_node_or_null("Turret2")
	if t2: t2.global_position = Vector2(850, 750)

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
	# Wave 1 = 150
	enemies_to_spawn = 100 + (current_wave * 50) 
	enemies_spawned = 0
	is_spawning = true
	spawn_timer = 0
	print("--- WAVE ", current_wave, " STARTED! ---")

func _spawn_single_enemy():
	var offset = Vector2(randf_range(-16, 16), randf_range(-16, 16))
	enemy_manager.spawn_enemy(spawn_point + offset)
	enemies_spawned += 1
