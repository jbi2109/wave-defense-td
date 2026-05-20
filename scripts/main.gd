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
	await get_tree().process_frame
	_setup_map_logic()
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)

	# Wire wave manager dependency
	wave_manager.enemy_manager = enemy_manager

	# Signals
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	GlobalEvents.enemy_killed.connect(_on_enemy_killed)

	# HUD buttons (nodes exist in scene, may be null if HUD redesigned later)
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_pressed)
		$HUD/Overlay/NextWaveButton.visible = true
	if has_node("HUD/Overlay/GameOverContainer/RestartButton"):
		$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(
			func(): get_tree().reload_current_scene())
	if has_node("HUD/Overlay/StartEarlyButton"):
		$HUD/Overlay/StartEarlyButton.pressed.connect(
			func(): wave_manager.skip_inter_wave())

	# Start with starting gold
	Globals.reset_gold()

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
			var wp = Vector2(x + offset.x, y + offset.y) * cell_size + Vector2(cell_size * 0.5, cell_size * 0.5)
			var in_grass = path_rect.has_point(wp) and Geometry2D.is_point_in_polygon(wp, path_poly)
			var in_dirt  = false
			if in_grass:
				for i in range(obstacle_polys.size()):
					if obs_rects[i].has_point(wp) and Geometry2D.is_point_in_polygon(wp, obstacle_polys[i]):
						in_dirt = true
						break
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not (in_grass and not in_dirt))

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

	# Show "Next Wave" button when all enemies cleared and no wave running
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.visible = (
			not wave_manager.is_spawning and
			not wave_manager.is_inter_wave and
			enemy_manager.active_count == 0 and
			wave_manager.current_wave >= 0
		)

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
	var type   = _weighted_type_for_wave(wave_manager.current_wave)
	enemy_manager.spawn_enemy(pos, type)

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
	if enemy_manager.active_count > 0: return
	wave_manager.start_wave()
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.visible = false

func _on_enemy_killed(_type_idx: int, _position: Vector2, gold_yield: int):
	Globals.add_gold(gold_yield)

func _on_nexus_destroyed():
	is_game_over = true
	if has_node("HUD/Overlay/GameOverContainer"):
		$HUD/Overlay/GameOverContainer.visible = true
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.visible = false
