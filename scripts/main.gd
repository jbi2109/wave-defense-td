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
	# 1. SETUP DUAL-GRID VISUAL TILESET (DirtLayer)
	var ts = TileSet.new()
	ts.tile_size = Vector2i(16, 16) # Dual grid is exactly half the logical 32x32 size
	
	ts.add_terrain_set(0)
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(0, 0) # Terrain 0: BG (Grass/Cliffs)
	ts.add_terrain(0, 1) # Terrain 1: FG (Dirt Path)
	
	var dual_tex = load("res://assets/shader/shader-tileset.png")
	var source = TileSetAtlasSource.new()
	source.texture = dual_tex
	source.texture_region_size = Vector2i(16, 16)
	
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
		
		if i == 0: td.terrain = 0
		elif i == 15: td.terrain = 1
		else: td.terrain = -1
		
		# In Match Corners, 0 is bg, 1 is fg
		var t_l = 1 if (i & 1) else 0
		var t_r = 1 if (i & 2) else 0
		var b_l = 1 if (i & 4) else 0
		var b_r = 1 if (i & 8) else 0
		
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, t_l)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, t_r)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, b_l)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, b_r)

	ts.add_source(source, 0)
	dirt_layer.tile_set = ts
	# The magic offset that makes dual-grid rounding work perfectly
	dirt_layer.position = Vector2(-8, -8) 
	
	# 2. SETUP PHYSICS TILESET (Invisible GrassLayer just for collisions)
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
	grass_layer.visible = false # Hide it so we only see the beautiful DirtLayer
	
	# 3. DEFINE LOGICAL MAP (32x32 cells)
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

	# 4. DRAW MAPS
	grass_layer.clear()
	dirt_layer.clear()
	
	var dual_path_cells = []
	var dual_grass_cells = []
	
	for x in range(-5, 65):
		for y in range(-5, 40):
			var logic_cell = Vector2i(x, y)
			var is_path = path_cells.has(logic_cell)
			
			# Map 1 logical 32x32 cell to 4 physical 16x16 dual-grid cells
			var cx = x * 2
			var cy = y * 2
			var q1 = Vector2i(cx, cy)
			var q2 = Vector2i(cx+1, cy)
			var q3 = Vector2i(cx, cy+1)
			var q4 = Vector2i(cx+1, cy+1)
			
			if is_path:
				dual_path_cells.append_array([q1, q2, q3, q4])
			else:
				# It's a wall. Set collision in GrassLayer.
				grass_layer.set_cell(logic_cell, 0, Vector2i(0, 0))
				dual_grass_cells.append_array([q1, q2, q3, q4])
				
	# Tell Godot to beautifully autotile the 16x16 dual grid!
	dirt_layer.set_cells_terrain_connect(dual_grass_cells, 0, 0, false)
	dirt_layer.set_cells_terrain_connect(dual_path_cells, 0, 1, false)

	# 5. UPDATE FLOW FIELD
	for x in range(-5, 80):
		for y in range(-5, 50):
			flow_field.set_obstacle(Vector2i(x, y), not path_cells.has(Vector2i(x, y)))
			
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
