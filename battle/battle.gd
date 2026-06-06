extends Node2D
class_name Battle

@onready var flow_field    : FlowFieldManager = $FlowFieldManager
@onready var enemy_config  : EnemyConfig      = $EnemyManager
@onready var nexus         : Node2D           = $Nexus
@onready var wave_manager  : WaveManager      = $WaveManager

@onready var rb_texture_rect: TextureRect = $HUD/RigidbodiesDebug/RigidbodiesTexture
@onready var camera: Camera2D = $Camera2D

var is_game_over: bool = false
var _last_gold: int = -1
var _last_wave: int = -1
var _last_enemy_count: int = -1

func _ready():
	var map_id = Globals.selected_map
	if map_id == "":
		map_id = "map1"
		Globals.selected_map = "map1"
		
	var default_map = get_node_or_null("SmartShapeMap")
	if default_map:
		remove_child(default_map)
		default_map.queue_free()
		
	var map_data = Data.maps.get(map_id)
	if map_data:
		var map_scene = load(map_data.scene)
		if map_scene:
			var map_inst = map_scene.instantiate()
			map_inst.name = "SmartShapeMap"
			add_child(map_inst)
			move_child(map_inst, 0)
			Globals.currentMap = map_inst

	await get_tree().process_frame
	_setup_map_logic()
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
	flow_field.save_static_grid()

	# Wire wave manager dependency
	wave_manager.enemy_config = enemy_config

	# Signals
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	GlobalEvents.enemy_killed.connect(_on_enemy_killed)

	# HUD buttons
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_pressed)
		$HUD/Overlay/NextWaveButton.visible = true
	if has_node("HUD/Overlay/GameOverContainer/RestartButton"):
		$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(
			func(): get_tree().change_scene_to_file("res://scenes/ui/level_selector.tscn"))
	if has_node("HUD/Overlay/VictoryContainer/PlayAgainButton"):
		$HUD/Overlay/VictoryContainer/PlayAgainButton.pressed.connect(
			func(): get_tree().change_scene_to_file("res://scenes/ui/level_selector.tscn"))

	Globals.reset_gold()
	if Globals.auto_test_active:
		_run_auto_test_gameplay()
		
	if GPUSim.draw_texture:
		rb_texture_rect.texture = GPUSim.draw_texture

func _setup_map_logic():
	var map_root = $SmartShapeMap
	if not map_root: return

	var grass_path  = map_root.get_node_or_null("Grass_Path")
	var dirt_mound  = map_root.get_node_or_null("Dirt_Mound")
	var top_dirt    = map_root.get_node_or_null("Top_Dirt")
	var bottom_dirt = map_root.get_node_or_null("Bottom_Dirt")

	if not grass_path: return

	var path_poly = PackedVector2Array()
	for v in grass_path.get_point_array().get_vertices():
		path_poly.append(grass_path.to_global(v))

	var obstacle_polys: Array[PackedVector2Array] = []
	for shape in [dirt_mound, top_dirt, bottom_dirt]:
		if shape:
			var poly = PackedVector2Array()
			for v in shape.get_point_array().get_vertices():
				poly.append(shape.to_global(v))
			obstacle_polys.append(poly)

	var cell_size: float  = float(flow_field.cell_size)
	var offset: Vector2i  = flow_field.grid_offset
	var obs_sub: int      = flow_field.obs_sub
	var _sub_size: float  = cell_size / float(obs_sub)  # world units per obs pixel

	# --- Flow-field tile grid (coarse, one sample per tile centre) ---
	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			var wp = Vector2(x + offset.x, y + offset.y) * cell_size + Vector2(cell_size * 0.5, cell_size * 0.5)
			var in_grass = Geometry2D.is_point_in_polygon(wp, path_poly)
			var in_obs = false
			for poly in obstacle_polys:
				if Geometry2D.is_point_in_polygon(wp, poly):
					in_obs = true
					break
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not (in_grass and not in_obs))

	# Commit the coarse grid (updates wall penalties, flow field etc.)
	flow_field.commit_obstacles()

	# --- High-res obstacle image (obs_sub pixels per tile) for GPU wall collision ---
	# obs_sub=8 means 4px blocks (32/8=4 world px per pixel) for smooth curve approximation.
	var img_w = flow_field.grid_size.x * obs_sub
	var img_h = flow_field.grid_size.y * obs_sub
	var hi_res := Image.create(img_w, img_h, false, Image.FORMAT_L8)

	# Build lookup data (copy to locals for thread safety)
	var _cell_size: float = cell_size
	var _offset: Vector2i = offset
	var _obs_sub: float   = float(obs_sub)
	var _sub_size2: float = _cell_size / _obs_sub
	var _path_poly := PackedVector2Array(path_poly)
	var _obstacle_polys : Array[PackedVector2Array] = []
	for p in obstacle_polys:
		_obstacle_polys.append(PackedVector2Array(p))

	# Rasterise each row in parallel (each row writes to unique indices, no lock needed)
	var pixel_data := PackedByteArray()
	pixel_data.resize(img_w * img_h)
	var _rasterise_row := func(row: int) -> void:
		for col in range(img_w):
			var wp := Vector2(
				(float(col) / _obs_sub + _offset.x) * _cell_size + _sub_size * 0.5,
				(float(row) / _obs_sub + _offset.y) * _cell_size + _sub_size * 0.5
			)
			var in_grass := Geometry2D.is_point_in_polygon(wp, _path_poly)
			var in_obs := false
			for poly in _obstacle_polys:
				if Geometry2D.is_point_in_polygon(wp, poly):
					in_obs = true
					break
			pixel_data[row * img_w + col] = 255 if not (in_grass and not in_obs) else 0
	var group_id := WorkerThreadPool.add_group_task(_rasterise_row, img_h, true)
	WorkerThreadPool.wait_for_group_task_completion(group_id)

	# Write pixel data into the image
	for row in range(img_h):
		for col in range(img_w):
			hi_res.set_pixel(col, row, Color8(pixel_data[row * img_w + col], 0, 0))

	# Upload to GPU texture for physics collision
	flow_field.hi_res_obs_image = hi_res
	flow_field.hi_res_obs_texture.update(hi_res)

func is_point_walkable(pos: Vector2) -> bool:
	var gp = Vector2i((pos / float(flow_field.cell_size)).floor()) - flow_field.grid_offset
	if gp.x >= 0 and gp.x < flow_field.grid_size.x and gp.y >= 0 and gp.y < flow_field.grid_size.y:
		if flow_field.obs_image:
			return flow_field.obs_image.get_pixel(gp.x, gp.y).r < 0.5
	return false

func _process(delta):
	_update_hud()
	
	# Execute GPU logic
	var current_ms = Time.get_ticks_msec()
	var ff_data = {
		"offset_x": float(flow_field.grid_offset.x),
		"offset_y": float(flow_field.grid_offset.y),
		"cell_size": float(flow_field.cell_size)
	}
	var nex_data = {
		"pos": nexus.global_position if nexus else Vector2.ZERO,
		"radius": 64.0, # or nexus.extents if you prefer
		"valid": 1 if nexus else 0
	}
	
	if flow_field.ff_texture and flow_field.obs_texture:
		# obs_texture (100x60) is used by the flow field GPU compute
		# hi_res_obs_texture (400x240) is used by the physics GPU for accurate wall collision
		var phys_obs = flow_field.hi_res_obs_texture if flow_field.hi_res_obs_texture else flow_field.obs_texture
		GPUSim.update_flow_field_textures(flow_field.ff_texture, phys_obs, flow_field.final_sdf_tex)
		
	GPUSim.dispatch_physics(delta, current_ms, ff_data, nex_data, {})
	
	if camera:
		var viewport_size = get_viewport_rect().size
		var cam_pos = camera.global_position
		var zoom = camera.zoom.x
		RenderingServer.call_on_render_thread(func():
			GPUSim.draw_agents(cam_pos, viewport_size, zoom)
		)

	if is_game_over: return
	wave_manager.tick(delta, _spawn_single_enemy)

	if Engine.get_process_frames() % 60 == 0:
		print("DEBUG: Active:", GPUSim.active_count, " InterWave:", wave_manager.is_inter_wave, " Spawning:", wave_manager.is_spawning, " Mana:", Globals.mana)

	if (not wave_manager.is_spawning and 
		not wave_manager.is_inter_wave and 
		wave_manager.current_wave > 0 and 
		GPUSim.active_count == 0):
		
		if wave_manager.current_wave == wave_manager.max_waves:
			_on_victory()
		else:
			wave_manager.start_inter_wave()

	var next_btn = get_node_or_null("HUD/Overlay/NextWaveButton")
	var count_lbl = get_node_or_null("HUD/Overlay/CountdownLabel")
	
	if next_btn:
		if wave_manager.current_wave == 0:
			next_btn.visible = true
			next_btn.text = "Start Game"
		elif wave_manager.is_inter_wave:
			next_btn.visible = true
			next_btn.text = "Start Early"
		else:
			next_btn.visible = false
			
	if count_lbl:
		if wave_manager.is_inter_wave:
			count_lbl.visible = true
			count_lbl.text = "Next Wave in: %ds" % ceil(wave_manager._inter_wave_timer)
		else:
			count_lbl.visible = false

func _update_hud() -> void:
	if Globals.gold != _last_gold:
		_last_gold = Globals.gold
		if has_node("HUD/Overlay/GoldLabel"):
			$HUD/Overlay/GoldLabel.text = "Gold: %d" % _last_gold
			
	if wave_manager.current_wave != _last_wave:
		_last_wave = wave_manager.current_wave
		if has_node("HUD/Overlay/WaveLabel"):
			$HUD/Overlay/WaveLabel.text = "Wave: %d" % _last_wave
			
	if GPUSim.active_count != _last_enemy_count:
		_last_enemy_count = GPUSim.active_count
		if has_node("HUD/Overlay/EnemyCountLabel"):
			$HUD/Overlay/EnemyCountLabel.text = "Enemies: %d" % _last_enemy_count

func _spawn_single_enemy():
	var spawners = get_tree().get_nodes_in_group("spawner")
	if spawners.is_empty():
		push_warning("BATTLE: Spawners is empty!")
		return
	
	var chosen = spawners[wave_manager.enemies_spawned % spawners.size()]
	if chosen == null or not chosen.has_method("get_random_spawn_point"):
		push_warning("BATTLE: Chosen spawner invalid!")
		return
		
	var pos = chosen.get_random_spawn_point()
	
	if enemy_config == null or enemy_config.enemy_types.is_empty():
		push_warning("BATTLE: Enemy config is null or empty!")
		return
	
	var type = _determine_enemy_type_to_spawn(
		wave_manager.current_wave,
		wave_manager.enemies_spawned,
		wave_manager.enemies_to_spawn
	)
	
	if type < 0 or type >= enemy_config.type_healths.size():
		push_warning("BATTLE: Invalid enemy type: " + str(type))
		type = 0
		
	var hp = enemy_config.type_healths[type]
	GPUSim.spawn_enemy(pos, type, enemy_config.type_speeds, enemy_config.type_scales, hp, wave_manager.map_config.wave_scaler)

func _determine_enemy_type_to_spawn(wave: int, spawned_index: int, _total_to_spawn: int) -> int:
	if wave == wave_manager.max_waves: return 5
	if wave == 5 and spawned_index == 0: return 4
	if wave == 10 and (spawned_index == 0 or spawned_index == 1): return 4
	return _weighted_type_for_wave(wave)

func _weighted_type_for_wave(wave: int) -> int:
	var eligible: Array[int] = []
	var weights : Array[float] = []
	var total_w = 0.0
	for i in range(enemy_config.enemy_types.size()):
		var et = enemy_config.enemy_types[i]
		var min_w = et.min_wave if "min_wave" in et else 1
		if wave >= min_w:
			eligible.append(i)
			var w = et.spawn_weight
			weights.append(w)
			total_w += w
	if eligible.is_empty(): return 0
	var roll = randf_range(0.0, total_w)
	var accum = 0.0
	for j in range(eligible.size()):
		accum += weights[j]
		if roll <= accum:
			return eligible[j]
	return eligible[0]

func _on_next_wave_pressed():
	if wave_manager.is_spawning: return
	if wave_manager.current_wave == 0:
		wave_manager.start_wave()
	elif wave_manager.is_inter_wave:
		var bonus = int(wave_manager.enemies_to_spawn * 0.1)
		Globals.add_gold(bonus)
		wave_manager.skip_inter_wave()

func _on_enemy_killed(type_idx: int, pos: Vector2, gold_yield: int):
	Globals.add_gold(gold_yield)
	_spawn_death_particles(pos, type_idx)
	
	if type_idx >= 0 and type_idx < enemy_config.enemy_types.size():
		var split_count = enemy_config.type_split_count[type_idx]
		if split_count > 0:
			var split_type = enemy_config.type_split_type[type_idx]
			for i in range(split_count):
				var offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
				var hp = enemy_config.type_healths[split_type]
				GPUSim.spawn_enemy(pos + offset, split_type, enemy_config.type_speeds, enemy_config.type_scales, hp, 1.0)

func _spawn_death_particles(_pos: Vector2, _type_idx: int) -> void:
	pass

func _on_nexus_destroyed():
	is_game_over = true
	SaveManager.update_high_score(Globals.selected_map, wave_manager.current_wave - 1)
	if has_node("HUD/Overlay/GameOverContainer"):
		$HUD/Overlay/GameOverContainer.visible = true
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.visible = false

func _on_victory():
	is_game_over = true
	SaveManager.update_high_score(Globals.selected_map, 15)
	if has_node("HUD/Overlay/VictoryContainer"):
		$HUD/Overlay/VictoryContainer.visible = true
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.visible = false
	if has_node("HUD/Overlay/CountdownLabel"):
		$HUD/Overlay/CountdownLabel.visible = false

func _run_auto_test_gameplay():
	await get_tree().create_timer(2.0).timeout
	_on_next_wave_pressed()
	await get_tree().create_timer(3.0).timeout
