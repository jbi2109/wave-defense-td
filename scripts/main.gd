extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var grass_layer = $GrassLayer
@onready var dirt_layer = $DirtLayer

var enemy_scene = preload("res://prefabs/enemy.tscn")
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
	grass_layer.tile_set = TileSet.new()
	grass_layer.tile_set.tile_size = Vector2i(32, 32)
	
	# Grass gets collision layer 1
	grass_layer.tile_set.add_physics_layer(0)
	grass_layer.tile_set.set_physics_layer_collision_layer(0, 1)
	grass_layer.tile_set.set_physics_layer_collision_mask(0, 1)
	
	dirt_layer.tile_set = TileSet.new()
	dirt_layer.tile_set.tile_size = Vector2i(32, 32)

	var grass_tex = load("res://assets/shader/Shader_cliff.png")
	var dirt_tex = load("res://assets/shader/shader-texture_1.png")
	
	var source_grass = TileSetAtlasSource.new()
	source_grass.texture = grass_tex
	source_grass.texture_region_size = Vector2i(32, 32)
	source_grass.create_tile(Vector2i(0, 0))
	# Add physics polygon to grass
	var tile_data = source_grass.get_tile_data(Vector2i(0,0), 0)
	tile_data.add_collision_polygon(0)
	var polygon = PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)])
	tile_data.set_collision_polygon_points(0, 0, polygon)
	
	grass_layer.tile_set.add_source(source_grass, 0)
	
	var source_dirt = TileSetAtlasSource.new()
	source_dirt.texture = dirt_tex
	source_dirt.texture_region_size = Vector2i(32, 32)
	source_dirt.create_tile(Vector2i(0, 0))
	dirt_layer.tile_set.add_source(source_dirt, 0)

	# 1. Fill EVERYTHING with Grass (Walls)
	grass_layer.clear()
	for x in range(-5, 65):
		for y in range(-5, 40):
			grass_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
	
	# 2. Draw Complex Dirt Path
	dirt_layer.clear()
	var path_cells = []
	for x in range(-5, 22):
		for y in range(4, 9): path_cells.append(Vector2i(x, y))
	for y in range(9, 22):
		for x in range(17, 22): path_cells.append(Vector2i(x, y))
	for x in range(12, 17):
		for y in range(17, 22): path_cells.append(Vector2i(x, y))
	for y in range(22, 28):
		for x in range(12, 17): path_cells.append(Vector2i(x, y))
	for x in range(12, 38):
		for y in range(28, 33): path_cells.append(Vector2i(x, y))
	for y in range(12, 28):
		for x in range(33, 38): path_cells.append(Vector2i(x, y))
	for x in range(38, 50):
		for y in range(12, 17): path_cells.append(Vector2i(x, y))
	for y in range(17, 25):
		for x in range(45, 50): path_cells.append(Vector2i(x, y))
	for x in range(50, 65):
		for y in range(20, 25): path_cells.append(Vector2i(x, y))

	for cell in path_cells:
		dirt_layer.set_cell(cell, 0, Vector2i(0, 0))
		# Remove Grass underneath
		grass_layer.set_cell(cell, -1, Vector2i(-1, -1))
		
	# Update Flow Field Obstacles based on Path
	for x in range(-5, 80):
		for y in range(-5, 50):
			var is_path = path_cells.has(Vector2i(x, y))
			flow_field.set_obstacle(Vector2i(x, y), not is_path)
			
	nexus.global_position = Vector2(1900, 720)
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
	else:
		if get_tree().get_nodes_in_group("enemies").size() == 0 and not is_game_over and current_wave > 0:
			$HUD/Overlay/NextWaveButton.visible = true

func _on_next_wave_button_pressed():
	if not is_spawning and get_tree().get_nodes_in_group("enemies").size() == 0:
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
	var offset = Vector2(randf_range(-12, 12), randf_range(-12, 12))
	var e = enemy_scene.instantiate()
	e.global_position = spawn_point + offset
	enemy_manager.add_child(e)
	enemies_spawned += 1
