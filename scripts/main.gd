extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var grass_layer = $GrassLayer
@onready var dirt_layer = $DirtLayer

var enemy_scene = preload("res://prefabs/enemy.tscn")
var spawn_point: Vector2 = Vector2(-200, 832) # Left entrance

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
var spawn_rate: float = 0.02
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
	
	# Dual-grid bitmask mapping (Standard 16-tile set)
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
		
		# In Match Corners, 0 is bg, 1 is fg
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, 1 if (i & 1) else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, 1 if (i & 2) else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, 1 if (i & 4) else 0)
		td.set_terrain_peering_bit(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, 1 if (i & 8) else 0)

	ts.add_source(source, 0)
	dirt_layer.tile_set = ts
	dirt_layer.material = load("res://assets/shader/shader-material.tres")
	# Offset to align 16x16 grid vertices with 32x32 logical centers
	dirt_layer.position = Vector2(-8, -8) 
	
	# 2. SETUP PHYSICS TILESET (Invisible GrassLayer for collisions)
	var physics_ts = TileSet.new()
	physics_ts.tile_size = Vector2i(32, 32)
	physics_ts.add_physics_layer(0)
	physics_ts.set_physics_layer_collision_layer(0, 1)
	
	var phys_source = TileSetAtlasSource.new()
	phys_source.texture = load("res://assets/shader/Shader_cliff.png")
	phys_source.texture_region_size = Vector2i(32, 32)
	phys_source.create_tile(Vector2i(0, 0))
	physics_ts.add_source(phys_source, 0)
	var ptd = phys_source.get_tile_data(Vector2i(0,0), 0)
	ptd.add_collision_polygon(0)
	ptd.set_collision_polygon_points(0, 0, PackedVector2Array([Vector2(-16,-16), Vector2(16,-16), Vector2(16,16), Vector2(-16,16)]))
	
	grass_layer.tile_set = physics_ts
	grass_layer.visible = false 
	
	# 3. DEFINE LOGICAL MAP (Serpentine Blueprint)
	var path_cells = []
	
	# Row 1: Bottom (Left to Right)
	for x in range(-10, 52):
		for y in range(24, 28): path_cells.append(Vector2i(x, y))
	
	# Connector 1: UP
	for x in range(48, 52):
		for y in range(16, 24): path_cells.append(Vector2i(x, y))
		
	# Row 2: Middle (Right to Left)
	for x in range(6, 52):
		for y in range(16, 20): path_cells.append(Vector2i(x, y))
		
	# Connector 2: UP
	for x in range(6, 10):
		for y in range(8, 16): path_cells.append(Vector2i(x, y))
		
	# Row 3: Top (Left to Right)
	for x in range(6, 65):
		for y in range(8, 12): path_cells.append(Vector2i(x, y))

	# 4. DRAW MAPS WITH SMART CHAMFER
	grass_layer.clear()
	dirt_layer.clear()
	
	var dual_path_cells = []
	var dual_grass_cells = []
	
	# We iterate at the 16x16 dual-grid level
	# Each 16x16 cell q is part of logic cell L = (q.x/2, q.y/2)
	for x in range(-20, 140):
		for y in range(-20, 80):
			var q = Vector2i(x, y)
			var lx = floor(x / 2.0)
			var ly = floor(y / 2.0)
			var L = Vector2i(lx, ly)
			
			var is_p = path_cells.has(L)
			
			# CHAMFER LOGIC: Shave corners to 45 degrees
			# If a logic cell is a corner, one of its 4 quadrants should be flipped
			var off_x = x % 2 # 0 is Left quadrant, 1 is Right
			var off_y = y % 2 # 0 is Top quadrant, 1 is Bottom
			
			# Check neighbors of logic cell L
			var n_u = path_cells.has(L + Vector2i(0, -1))
			var n_d = path_cells.has(L + Vector2i(0, 1))
			var n_l = path_cells.has(L + Vector2i(-1, 0))
			var n_r = path_cells.has(L + Vector2i(1, 0))
			
			if is_p:
				# Convex corners: Shave the outer quadrant
				var shave = false
				if not n_u and not n_l and off_x == 0 and off_y == 0: shave = true # Top-Left
				if not n_u and not n_r and off_x == 1 and off_y == 0: shave = true # Top-Right
				if not n_d and not n_l and off_x == 0 and off_y == 1: shave = true # Bottom-Left
				if not n_d and not n_r and off_x == 1 and off_y == 1: shave = true # Bottom-Right
				
				if shave: dual_grass_cells.append(q)
				else: dual_path_cells.append(q)
			else:
				# Concave corners: Fill the inner quadrant
				var fill = false
				if n_u and n_l and off_x == 0 and off_y == 0: fill = true # Top-Left
				if n_u and n_r and off_x == 1 and off_y == 0: fill = true # Top-Right
				if n_d and n_l and off_x == 0 and off_y == 1: fill = true # Bottom-Left
				if n_d and n_r and off_x == 1 and off_y == 1: fill = true # Bottom-Right
				
				if fill: dual_path_cells.append(q)
				else:
					dual_grass_cells.append(q)
					# Add collision only for logic cells
					if off_x == 0 and off_y == 0:
						grass_layer.set_cell(L, 0, Vector2i(0, 0))
				
	dirt_layer.set_cells_terrain_connect(dual_grass_cells, 0, 0, false)
	dirt_layer.set_cells_terrain_connect(dual_path_cells, 0, 1, false)

	# 5. UPDATE FLOW FIELD
	for x in range(-10, 80):
		for y in range(-10, 50):
			flow_field.set_obstacle(Vector2i(x, y), not path_cells.has(Vector2i(x, y)))
			
	nexus.global_position = Vector2(1900, 320) # End of Row 3
	var t1 = get_node_or_null("Turret1")
	if t1: t1.global_position = Vector2(800, 480) # In the middle of the snake
	var t2 = get_node_or_null("Turret2")
	if t2: t2.global_position = Vector2(1100, 480)

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
