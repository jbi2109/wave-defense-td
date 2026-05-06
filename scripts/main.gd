extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var grass_layer = $GrassLayer
@onready var dirt_layer = $DirtLayer

var spawn_point: Vector2 = Vector2(0, 176) # Start of path (x:0, y:5.5*32)

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
var spawn_rate: float = 0.2
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
	# Use Seamless World Shaders for Grass (Background) and Dirt (Path)
	var shader = load("res://assets/shaders/terrain_seamless.gdshader")
	
	# Grass Layer (Background)
	grass_layer.tile_set = TileSet.new()
	grass_layer.tile_set.tile_size = Vector2i(32, 32)
	var grass_mat = ShaderMaterial.new()
	grass_mat.shader = shader
	grass_mat.set_shader_parameter("noise_tex", load("res://assets/grass_base.tres"))
	grass_mat.set_shader_parameter("color_a", Color("#1a3317"))
	grass_mat.set_shader_parameter("color_b", Color("#3a6b32"))
	grass_mat.set_shader_parameter("scale", 0.002)
	grass_layer.material = grass_mat
	
	# Dirt Layer (Path)
	dirt_layer.tile_set = TileSet.new()
	dirt_layer.tile_set.tile_size = Vector2i(32, 32)
	var dirt_mat = ShaderMaterial.new()
	dirt_mat.shader = shader
	dirt_mat.set_shader_parameter("noise_tex", load("res://assets/stone_base.tres"))
	dirt_mat.set_shader_parameter("color_a", Color("#5a3e2b"))
	dirt_mat.set_shader_parameter("color_b", Color("#8b6b4f"))
	dirt_mat.set_shader_parameter("scale", 0.005)
	dirt_layer.material = dirt_mat

	# Base tile texture (white square) so shader has something to draw on
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex = ImageTexture.create_from_image(img)
	var source_grass = TileSetAtlasSource.new()
	source_grass.texture = tex
	source_grass.texture_region_size = Vector2i(32, 32)
	source_grass.create_tile(Vector2i(0, 0))
	
	var source_dirt = TileSetAtlasSource.new()
	source_dirt.texture = tex
	source_dirt.texture_region_size = Vector2i(32, 32)
	source_dirt.create_tile(Vector2i(0, 0))
	
	grass_layer.tile_set.add_source(source_grass, 0)
	dirt_layer.tile_set.add_source(source_dirt, 0)

	# 1. Fill EVERYTHING with Grass
	grass_layer.clear()
	for x in range(-5, 65):
		for y in range(-5, 40):
			grass_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	# 2. Draw Dirt Path (S-Curve)
	dirt_layer.clear()
	var path_cells = []
	for x in range(0, 45):
		for y in range(3, 8): path_cells.append(Vector2i(x, y))
	for y in range(8, 15):
		for x in range(40, 45): path_cells.append(Vector2i(x, y))
	for x in range(10, 45):
		for y in range(15, 20): path_cells.append(Vector2i(x, y))
	for y in range(20, 28):
		for x in range(10, 15): path_cells.append(Vector2i(x, y))
	for x in range(10, 65):
		for y in range(28, 33): path_cells.append(Vector2i(x, y))

	for cell in path_cells:
		dirt_layer.set_cell(cell, 0, Vector2i(0, 0))

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
	var offset = Vector2(randf_range(-16, 16), randf_range(-16, 16))
	enemy_manager.spawn_enemy(spawn_point + offset)
	enemies_spawned += 1
