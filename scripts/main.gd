extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
var spawn_rate: float = 0.05
var spawn_timer: float = 0.0

var is_spawning: bool = false
var is_game_over: bool = false

func _ready():
	await get_tree().process_frame
	_setup_map_logic()
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
	
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_button_pressed)
	$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(_on_restart_button_pressed)
	
	$HUD/Overlay/NextWaveButton.visible = true

func _setup_map_logic():
	var map_root = $SmartShapeMap
	if not map_root:
		printerr("Main: SmartShapeMap node not found!")
		return
		
	# Find the path and dirt shapes
	var grass_path = map_root.get_node_or_null("Grass_Path")
	var dirt_mound = map_root.get_node_or_null("Dirt_Mound")
	var top_dirt = map_root.get_node_or_null("Top_Dirt")
	var bottom_dirt = map_root.get_node_or_null("Bottom_Dirt")
	
	if not grass_path:
		printerr("Main: Grass_Path not found in Map!")
		return

	# Convert local vertices to global coordinates for collision checks
	var path_poly = []
	for v in grass_path.get_point_array().get_vertices():
		path_poly.append(grass_path.to_global(v))
	
	var obstacle_polys = []
	if dirt_mound:
		var poly = []
		for v in dirt_mound.get_point_array().get_vertices():
			poly.append(dirt_mound.to_global(v))
		obstacle_polys.append(poly)
	if top_dirt:
		var poly = []
		for v in top_dirt.get_point_array().get_vertices():
			poly.append(top_dirt.to_global(v))
		obstacle_polys.append(poly)
	if bottom_dirt:
		var poly = []
		for v in bottom_dirt.get_point_array().get_vertices():
			poly.append(bottom_dirt.to_global(v))
		obstacle_polys.append(poly)
	
	var cell_size = float(flow_field.cell_size)
	var offset = flow_field.grid_offset
	
	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			# Calculate world position for this cell center
			# cell_index = world_pos / cell_size - offset => world_pos = (cell_index + offset) * cell_size
			var world_pos = Vector2(x + offset.x, y + offset.y) * cell_size + Vector2(cell_size/2, cell_size/2)
			
			# A cell is a path ONLY if it is inside Grass_Path AND NOT inside any dirt area
			var is_in_grass = Geometry2D.is_point_in_polygon(world_pos, path_poly)
			var is_in_dirt = false
			for poly in obstacle_polys:
				if Geometry2D.is_point_in_polygon(world_pos, poly):
					is_in_dirt = true
					break
			
			var is_walkable = is_in_grass and not is_in_dirt
			
			# set_obstacle expects absolute grid coords, but flow_field.set_obstacle subtracts offset
			# So we pass (x + offset.x, y + offset.y)
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not is_walkable)

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
		if enemy_manager.active_count == 0 and not is_game_over and current_wave > 0:
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
	enemies_to_spawn = 20 + (current_wave - 1) * 10 
	enemies_spawned = 0
	is_spawning = true
	spawn_timer = 0
	print("--- WAVE ", current_wave, " STARTED! ---")

func _spawn_single_enemy():
	var spawners = get_tree().get_nodes_in_group("spawner")
	if spawners.is_empty():
		printerr("No spawners found!")
		return
	
	var chosen_spawner = spawners[randi() % spawners.size()]
	var spawn_pos = chosen_spawner.get_random_spawn_point()
	enemy_manager.spawn_enemy(spawn_pos)
	enemies_spawned += 1
