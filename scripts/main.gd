extends Node2D

@onready var flow_field    : FlowFieldManager = $FlowFieldManager
@onready var enemy_manager : EnemyManager     = $EnemyManager
@onready var nexus         : Node2D           = $Nexus
@onready var wave_manager  : WaveManager      = $WaveManager

var is_game_over: bool = false

# ─────────────────────────────────────────────────────────────
#  READY
# ─────────────────────────────────────────────────────────────
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
			Globals.currentMap = map_inst

	await get_tree().process_frame
	_setup_map_logic()
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
	flow_field.save_static_grid()

	# Wire wave manager dependency
	wave_manager.enemy_manager = enemy_manager

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

	# Start with starting gold
	Globals.reset_gold()
	if Globals.auto_test_active:
		_run_auto_test_gameplay()
# ─────────────────────────────────────────────────────────────
#  MAP OBSTACLE SETUP
# ─────────────────────────────────────────────────────────────
func _setup_map_logic():
	var map_root = $SmartShapeMap
	if not map_root:
		printerr("Main: SmartShapeMap node not found!")
		return

	var grass_path  = map_root.get_node_or_null("Grass_Path")
	var dirt_mound  = map_root.get_node_or_null("Dirt_Mound")
	var top_dirt    = map_root.get_node_or_null("Top_Dirt")
	var bottom_dirt = map_root.get_node_or_null("Bottom_Dirt")

	if not grass_path:
		printerr("Main: Grass_Path not found in Map!")
		return

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

	var path_rect = _bounds(path_poly)
	var obs_rects: Array[Rect2] = []
	for p in obstacle_polys:
		obs_rects.append(_bounds(p))

	var cell_size = float(flow_field.cell_size)
	var offset    = flow_field.grid_offset

	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			var cell_pos = Vector2(x + offset.x, y + offset.y) * cell_size
			var wp = cell_pos + Vector2(cell_size * 0.5, cell_size * 0.5)
			
			var is_walkable = _is_point_walkable(wp, path_rect, path_poly, obs_rects, obstacle_polys)
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not is_walkable)
			
	flow_field.commit_obstacles()

func _is_point_walkable(pt: Vector2, path_rect: Rect2, path_poly: PackedVector2Array, obs_rects: Array[Rect2], obstacle_polys: Array[PackedVector2Array]) -> bool:
	var in_grass = path_rect.has_point(pt) and Geometry2D.is_point_in_polygon(pt, path_poly)
	if not in_grass:
		return false
	for i in range(obstacle_polys.size()):
		if obs_rects[i].has_point(pt) and Geometry2D.is_point_in_polygon(pt, obstacle_polys[i]):
			return false
	return true

func _bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty(): return Rect2()
	var mn = poly[0]; var mx = poly[0]
	for p in poly:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	return Rect2(mn, mx - mn)

# ─────────────────────────────────────────────────────────────
#  PROCESS
# ─────────────────────────────────────────────────────────────
func _process(delta):
	_update_hud()
	if is_game_over: return

	wave_manager.tick(delta, _spawn_single_enemy)

	# --- Wave Progression / Clear detection ---
	if (not wave_manager.is_spawning and 
		not wave_manager.is_inter_wave and 
		wave_manager.current_wave > 0 and 
		enemy_manager.active_count == 0):
		
		if wave_manager.current_wave == wave_manager.max_waves:
			_on_victory()
		else:
			wave_manager.start_inter_wave()

	# --- NextWaveButton / CountdownLabel update ---
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

# ─────────────────────────────────────────────────────────────
#  HUD UPDATE
# ─────────────────────────────────────────────────────────────
func _update_hud():
	if has_node("HUD/Overlay/EnemyCountLabel"):
		$HUD/Overlay/EnemyCountLabel.text = "Enemies: %d" % enemy_manager.active_count
	if has_node("HUD/Overlay/WaveLabel"):
		$HUD/Overlay/WaveLabel.text = "Wave: %d" % wave_manager.current_wave
	if has_node("HUD/Overlay/GoldLabel"):
		$HUD/Overlay/GoldLabel.text = "Gold: %d" % Globals.gold

# ─────────────────────────────────────────────────────────────
#  SPAWN CALLBACK
# ─────────────────────────────────────────────────────────────
func _spawn_single_enemy():
	var spawners = get_tree().get_nodes_in_group("spawner")
	if spawners.is_empty(): return
	var chosen = spawners[wave_manager.enemies_spawned % spawners.size()]
	var pos    = chosen.get_random_spawn_point()
	
	var type   = _determine_enemy_type_to_spawn(
		wave_manager.current_wave,
		wave_manager.enemies_spawned,
		wave_manager.enemies_to_spawn
	)
	enemy_manager.spawn_enemy(pos, type)

func _determine_enemy_type_to_spawn(wave: int, spawned_index: int, _total_to_spawn: int) -> int:
	# Last wave is Big Boss only
	if wave == wave_manager.max_waves:
		return 5 # Big Boss
		
	# Wave 5: 1 Mini Boss (spawned first)
	if wave == 5 and spawned_index == 0:
		return 4 # Mini Boss
		
	# Wave 10: 2 Mini Bosses (spawned as first and second)
	if wave == 10 and (spawned_index == 0 or spawned_index == 1):
		return 4 # Mini Boss
		
	return _weighted_type_for_wave(wave)

func _weighted_type_for_wave(wave: int) -> int:
	var eligible: Array[int] = []
	var weights : Array[float] = []
	var total_w = 0.0
	for i in range(enemy_manager.enemy_types.size()):
		var et = enemy_manager.enemy_types[i]
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

# ─────────────────────────────────────────────────────────────
#  SIGNALS
# ─────────────────────────────────────────────────────────────
func _on_next_wave_pressed():
	if wave_manager.is_spawning: return
	
	if wave_manager.current_wave == 0:
		wave_manager.start_wave()
	elif wave_manager.is_inter_wave:
		# Early start bonus: +10% of enemies count in gold!
		var bonus = int(wave_manager.enemies_to_spawn * 0.1)
		Globals.add_gold(bonus)
		print("Started early! Gained early start gold bonus of: ", bonus)
		wave_manager.skip_inter_wave()

func _on_enemy_killed(type_idx: int, pos: Vector2, gold_yield: int):
	Globals.add_gold(gold_yield)
	_spawn_death_particles(pos, type_idx)

func _spawn_death_particles(pos: Vector2, type_idx: int):
	var particles = CPUParticles2D.new()
	particles.global_position = pos
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = 0.6
	particles.spread = 180.0
	particles.gravity = Vector2(0, 300)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	
	# Custom properties by type
	# 0: Swarmer, 1: Tank, 2: Runner, 3: Armored, 4: MiniBoss, 5: BigBoss
	match type_idx:
		0: # Swarmer
			particles.amount = 12
			particles.color = Color(0.85, 0.3, 0.2) # Reddish orange
			particles.scale_amount_min = 2.0
			particles.scale_amount_max = 5.0
		1: # Tank
			particles.amount = 16
			particles.color = Color(0.2, 0.4, 0.9) # Blue
			particles.scale_amount_min = 3.0
			particles.scale_amount_max = 7.0
		2: # Runner
			particles.amount = 10
			particles.color = Color(0.9, 0.8, 0.2) # Yellow
			particles.scale_amount_min = 2.0
			particles.scale_amount_max = 4.0
		3: # Armored
			particles.amount = 15
			particles.color = Color(0.6, 0.6, 0.65) # Metallic gray sparks
			particles.gravity = Vector2(0, 500) # Spark gravity
			particles.initial_velocity_min = 100.0
			particles.initial_velocity_max = 200.0
			particles.scale_amount_min = 1.5
			particles.scale_amount_max = 3.5
		4: # Mini Boss
			particles.amount = 30
			particles.color = Color(0.9, 0.1, 0.1) # Bright red
			particles.initial_velocity_min = 100.0
			particles.initial_velocity_max = 250.0
			particles.scale_amount_min = 4.0
			particles.scale_amount_max = 9.0
		5: # Big Boss
			particles.amount = 60
			particles.color = Color(1.0, 0.2, 0.1) # Giant explosion
			particles.initial_velocity_min = 120.0
			particles.initial_velocity_max = 350.0
			particles.scale_amount_min = 5.0
			particles.scale_amount_max = 12.0
			
	particles.script = load("res://scripts/death_effect.gd")
	add_child(particles)

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
	print("--- VICTORY! GAME CLEARED ---")

func _run_auto_test_gameplay():
	print("[AUTO_TEST] Gameplay scene loaded. Map: ", Globals.selected_map)
	await get_tree().create_timer(2.0).timeout
	print("[AUTO_TEST] Starting wave...")
	_on_next_wave_pressed()
	await get_tree().create_timer(3.0).timeout
	print("[AUTO_TEST] Automated test completed successfully!")
