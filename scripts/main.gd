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
	# 1. SETUP TILEMAPDUAL TILESET (Visuals)
	var ts = TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	
	ts.add_terrain_set(0)
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(0, 0) # Terrain 0: BG (Grass/Cliffs)
	ts.add_terrain(0, 1) # Terrain 1: FG (Dirt Path)
	
	var dual_tex = load("res://assets/shader/shader-tileset.png")
	var source = TileSetAtlasSource.new()
	source.texture = dual_tex
	source.texture_region_size = Vector2i(16, 16) # Dual grid uses half-size tiles
	
	# The 16 preset tiles required by TileMapDual topology SQUARE Standard
	var preset_tiles = [
		Vector2i(0, 3), Vector2i(3, 3), Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(0, 0), Vector2i(3, 2), Vector2i(2, 3), Vector2i(3, 1),
		Vector2i(1, 3), Vector2i(0, 1), Vector2i(1, 0), Vector2i(2, 2),
		Vector2i(3, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)
	]
	
	for i in range(16):
		var atlas_pos = preset_tiles[i]
		source.create_tile(atlas_pos)
		var td = source.get_tile_data(atlas_pos, 0)
		td.terrain_set = 0
		td.terrain = -1
		
		# Set peering bits (0 is bg, 1 is fg)
		var tl = 1 if (i & 1) else 0
		var tr = 1 if (i & 2) else 0
		var bl = 1 if (i & 4) else 0
		var br = 1 if (i & 8) else 0
		
		# In Match Corners and Sides, we set the corners
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, tl)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, tr)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, bl)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, br)

	ts.add_source(source, 0)
	
	dirt_layer.tile_set = ts
	
	# Tell TileMapDual to manually initialize
	if dirt_layer.has_method("_changed"):
		dirt_layer._changed()
		
	# 2. SETUP PHYSICS TILESET (Invisible layer just for collisions)
	var physics_ts = TileSet.new()
	physics_ts.tile_size = Vector2i(32, 32)
	physics_ts.add_physics_layer(0)
	physics_ts.set_physics_layer_collision_layer(0, 1)
	physics_ts.set_physics_layer_collision_mask(0, 1)
	
	var phys_source = TileSetAtlasSource.new()
	phys_source.texture = load("res://assets/shader/Shader_cliff.png")
	phys_source.texture_region_size = Vector2i(32, 32)
	phys_source.create_tile(Vector2i(0, 0))
	var ptd = phys_source.get_tile_data(Vector2i(0,0), 0)
	ptd.add_collision_polygon(0)
	ptd.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)]))
	physics_ts.add_source(phys_source, 0)
	
	grass_layer.tile_set = physics_ts
	grass_layer.visible = false # Hide it so we only see TileMapDual
	
	# 3. DRAW MAP
	# Fill EVERYTHING with Grass (Walls)
	grass_layer.clear()
	for x in range(-5, 65):
		for y in range(-5, 40):
			grass_layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
			if dirt_layer.has_method("draw_cell"):
				dirt_layer.draw_cell(Vector2i(x, y), 0)
	
	# Draw Complex Dirt Path
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
		grass_layer.set_cell(cell, -1, Vector2i(-1, -1)) # Remove collision
		if dirt_layer.has_method("draw_cell"):
			dirt_layer.draw_cell(cell, 1) # Draw Dirt
		
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
	enemies_to_spawn = 150 + (current_wave - 1) * 50 
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
