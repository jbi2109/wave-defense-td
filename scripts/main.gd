extends Node2D

@onready var flow_field    : FlowFieldManager = $FlowFieldManager
@onready var enemy_manager : EnemyManager     = $EnemyManager
@onready var nexus         : Node2D           = $Nexus
@onready var wave_manager  : WaveManager      = $WaveManager

var is_game_over: bool = false
var _particle_pools: Array[Array] = [[], [], [], [], [], [], [], []]
var _last_gold: int = -1
var _last_wave: int = -1
var _last_enemy_count: int = -1

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
			move_child(map_inst, 0)
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

	var cell_size = float(flow_field.cell_size)
	var offset    = flow_field.grid_offset

	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			var cell_pos = Vector2(x + offset.x, y + offset.y) * cell_size
			var wp = cell_pos + Vector2(cell_size * 0.5, cell_size * 0.5)
			
			var in_grass = Geometry2D.is_point_in_polygon(wp, path_poly)
			var in_obs = false
			for poly in obstacle_polys:
				if Geometry2D.is_point_in_polygon(wp, poly):
					in_obs = true
					break
			var is_walkable = in_grass and not in_obs
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not is_walkable)
			
	flow_field.commit_obstacles()

func is_point_walkable(pos: Vector2) -> bool:
	var gp = Vector2i((pos / float(flow_field.cell_size)).floor()) - flow_field.grid_offset
	if gp.x >= 0 and gp.x < flow_field.grid_size.x and gp.y >= 0 and gp.y < flow_field.grid_size.y:
		if flow_field.obs_image:
			return flow_field.obs_image.get_pixel(gp.x, gp.y).r < 0.5
	return false

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
func _update_hud() -> void:
	if Globals.gold != _last_gold:
		_last_gold = Globals.gold
		if has_node("HUD/Overlay/GoldLabel"):
			$HUD/Overlay/GoldLabel.text = "Gold: %d" % _last_gold
			
	if wave_manager.current_wave != _last_wave:
		_last_wave = wave_manager.current_wave
		if has_node("HUD/Overlay/WaveLabel"):
			$HUD/Overlay/WaveLabel.text = "Wave: %d" % _last_wave
			
	if enemy_manager.active_count != _last_enemy_count:
		_last_enemy_count = enemy_manager.active_count
		if has_node("HUD/Overlay/EnemyCountLabel"):
			$HUD/Overlay/EnemyCountLabel.text = "Enemies: %d" % _last_enemy_count

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
	
	if type_idx >= 0 and type_idx < enemy_manager.enemy_types.size():
		var split_count = enemy_manager.type_split_count[type_idx]
		if split_count > 0:
			var split_type = enemy_manager.type_split_type[type_idx]
			for i in range(split_count):
				var offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
				enemy_manager.spawn_enemy(pos + offset, split_type)

func _spawn_death_particles(pos: Vector2, type_idx: int) -> void:
	if type_idx < 0 or type_idx >= _particle_pools.size():
		return
		
	var pool = _particle_pools[type_idx]
	var p: CPUParticles2D = null
	
	# Find an inactive emitter
	for emitter in pool:
		if is_instance_valid(emitter) and not emitter.emitting:
			p = emitter
			break
			
	if p:
		p.global_position = pos
		p.emitting = true
		return
		
	# Create new one if none found
	p = CPUParticles2D.new()
	p.global_position = pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.spread = 180.0
	p.gravity = Vector2(0, 300)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 140.0
	
	# Custom properties by type
	# 0: Ghoul, 1: Abomination, 2: Hound, 3: Draugr, 4: Dullahan, 5: Lich King, 6: Banshee Bat, 7: Crypt Sludge
	match type_idx:
		0: # Drowned Ghoul: decaying meat splash
			p.amount = 12
			p.color = Color(0.18, 0.35, 0.22) # Slime green
			p.gravity = Vector2(0, 350)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 5.0
		1: # Flesh Abomination: massive blood splash
			p.amount = 24
			p.color = Color(0.45, 0.08, 0.08) # Dried blood red
			p.gravity = Vector2(0, 500) # Heavy fall
			p.scale_amount_min = 4.0
			p.scale_amount_max = 8.0
		2: # Plague Hound: toxic spores explode and float
			p.amount = 14
			p.color = Color(0.3, 0.7, 0.1) # Toxic lime green
			p.gravity = Vector2(0, -30) # Drift upwards slightly
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.5
		3: # Draugr Warrior: skeleton bones fall to ground
			p.amount = 18
			p.color = Color(0.85, 0.82, 0.76) # Bone white
			p.gravity = Vector2(0, 500) # Fall down
			p.initial_velocity_min = 80.0
			p.initial_velocity_max = 180.0
			p.scale_amount_min = 1.5
			p.scale_amount_max = 4.0
		4: # Dullahan: dark shadowy fire
			p.amount = 35
			p.color = Color(0.5, 0.1, 0.7) # Shadowy purple
			p.gravity = Vector2(0, 100)
			p.initial_velocity_min = 100.0
			p.initial_velocity_max = 240.0
			p.scale_amount_min = 3.5
			p.scale_amount_max = 8.5
		5: # Lich King: radial frost explosion
			p.amount = 70
			p.color = Color(0.4, 0.85, 1.0) # Frost cyan
			p.gravity = Vector2(0, 0) # Radial, no gravity!
			p.initial_velocity_min = 120.0
			p.initial_velocity_max = 320.0
			p.scale_amount_min = 5.0
			p.scale_amount_max = 11.0
		6: # Banshee Bat: ectoplasmic dust floats UP
			p.amount = 16
			p.color = Color(0.4, 0.9, 0.6) # Spectral mint green
			p.gravity = Vector2(0, -150) # Float up!
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 150.0
			p.scale_amount_min = 2.5
			p.scale_amount_max = 6.0
		7: # Crypt Sludge: dark slime splash
			p.amount = 25
			p.color = Color(0.2, 0.5, 0.15) # Dark bile green
			p.gravity = Vector2(0, 300)
			p.initial_velocity_min = 80.0
			p.initial_velocity_max = 200.0
			p.scale_amount_min = 3.0
			p.scale_amount_max = 7.0
			
	add_child(p)
	p.emitting = true
	pool.append(p)

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
