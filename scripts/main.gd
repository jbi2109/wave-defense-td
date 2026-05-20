extends Node2D

@onready var flow_field = $FlowFieldManager
@onready var enemy_manager = $EnemyManager
@onready var nexus = $Nexus
@onready var wave_manager = $WaveManager

var current_wave: int = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int = 0
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

	var t_start = Time.get_ticks_msec()
	
	# Convert local vertices to global coordinates for collision checks
	var path_poly = PackedVector2Array()
	for v in grass_path.get_point_array().get_vertices():
		path_poly.append(grass_path.to_global(v))
	
	var obstacle_polys = []
	if dirt_mound:
		var poly = PackedVector2Array()
		for v in dirt_mound.get_point_array().get_vertices():
			poly.append(dirt_mound.to_global(v))
		obstacle_polys.append(poly)
	if top_dirt:
		var poly = PackedVector2Array()
		for v in top_dirt.get_point_array().get_vertices():
			poly.append(top_dirt.to_global(v))
		obstacle_polys.append(poly)
	if bottom_dirt:
		var poly = PackedVector2Array()
		for v in bottom_dirt.get_point_array().get_vertices():
			poly.append(bottom_dirt.to_global(v))
		obstacle_polys.append(poly)
	
	var t_poly = Time.get_ticks_msec()
	print("Main: Polygon conversion took ", t_poly - t_start, "ms.")
	print("Main: Grass Path Vertices = ", path_poly.size())
	for i in range(obstacle_polys.size()):
		print("Main: Obstacle ", i, " Vertices = ", obstacle_polys[i].size())
		
	# Calculate bounding boxes for ultra-fast early out
	var path_rect = _calculate_bounds(path_poly)
	var obstacle_rects = []
	for p in obstacle_polys:
		obstacle_rects.append(_calculate_bounds(p))
	
	var cell_size = float(flow_field.cell_size)
	var offset = flow_field.grid_offset
	
	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			# Calculate world position for this cell center
			var world_pos = Vector2(x + offset.x, y + offset.y) * cell_size + Vector2(cell_size/2, cell_size/2)
			
			# A cell is a path ONLY if it is inside Grass_Path AND NOT inside any dirt area
			var is_in_grass = false
			if path_rect.has_point(world_pos):
				is_in_grass = Geometry2D.is_point_in_polygon(world_pos, path_poly)
				
			var is_in_dirt = false
			if is_in_grass: # No need to check dirt if it isn't even in grass
				for i in range(obstacle_polys.size()):
					if obstacle_rects[i].has_point(world_pos):
						if Geometry2D.is_point_in_polygon(world_pos, obstacle_polys[i]):
							is_in_dirt = true
							break
			
			var is_walkable = is_in_grass and not is_in_dirt
			
			# set_obstacle expects absolute grid coords, but flow_field.set_obstacle subtracts offset
			# So we pass (x + offset.x, y + offset.y)
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not is_walkable)
			
	var t_end = Time.get_ticks_msec()
	print("Main: Grid scan took ", t_end - t_poly, "ms.")

func _calculate_bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var min_p = poly[0]
	var max_p = poly[0]
	for p in poly:
		min_p.x = min(min_p.x, p.x)
		min_p.y = min(min_p.y, p.y)
		max_p.x = max(max_p.x, p.x)
		max_p.y = max(max_p.y, p.y)
	return Rect2(min_p, max_p - min_p)

func _on_restart_button_pressed():
	get_tree().reload_current_scene()

func _process(delta):
	# Update HUD label
	if has_node("HUD/Overlay/EnemyCountLabel"):
		$HUD/Overlay/EnemyCountLabel.text = "Enemies: " + str(enemy_manager.active_count)
	
	if is_game_over: return
	if is_spawning:
		spawn_timer -= delta
		if spawn_timer <= 0:
			# Stream 2 enemies every timer tick to reduce lag
			var stream_batch_size = 2
			var spawned_this_tick = 0
			while spawned_this_tick < stream_batch_size and enemies_spawned < enemies_to_spawn:
				_spawn_single_enemy()
				spawned_this_tick += 1
			spawn_timer = wave_manager.spawn_rate
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
	# Scale total enemies exponentially based on wave number, as requested by the user
	enemies_to_spawn = int(wave_manager.base_enemies_per_wave * pow(wave_manager.wave_scaler, current_wave - 1))
	enemies_spawned = 0
	is_spawning = true
	spawn_timer = 0
	print("--- WAVE ", current_wave, " STARTED! Spawning ", enemies_to_spawn, " enemies ---")

func _spawn_single_enemy():
	var spawners = get_tree().get_nodes_in_group("spawner")
	if spawners.is_empty():
		printerr("No spawners found!")
		return
	
	# Round-robin selection ensures an exact even split across all spawners
	var chosen_spawner = spawners[enemies_spawned % spawners.size()]
	var spawn_pos = chosen_spawner.get_random_spawn_point()
	var type_idx = _get_random_enemy_type()
	enemy_manager.spawn_enemy(spawn_pos, type_idx)
	enemies_spawned += 1

func _get_random_enemy_type() -> int:
	var types = enemy_manager.enemy_types
	if types.is_empty(): return 0
	
	var total_weight = 0.0
	for t in types:
		total_weight += t.spawn_weight
		
	var roll = randf_range(0.0, total_weight)
	var current = 0.0
	for i in range(types.size()):
		current += types[i].spawn_weight
		if roll <= current:
			return i
			
	return 0
