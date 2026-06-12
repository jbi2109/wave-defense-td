extends Node2D
class_name Battle

# World rect of the CURRENT map (mask domain + camera fit). Per-map: set in
# _apply_map_config from the map root's `world_size` export, else 1920×1080
# (map1/map2 keep the original fixed size).
var map_world_size := Vector2(1920, 1080)

@onready var flow_field    : FlowFieldManager = $FlowFieldManager
@onready var enemy_config  : EnemyConfig      = $EnemyManager
@onready var nexus         : Node2D           = $Nexus
@onready var wave_manager  : WaveManager      = $WaveManager

@onready var rb_texture_rect: TextureRect = $AgentLayer/RigidbodiesDebug/RigidbodiesTexture
@onready var camera: Camera2D = $Camera2D

var is_game_over: bool = false
var _min_zoom: float = 1.0  # cover-fit zoom; camera may zoom in but never out past it
var _panning: bool = false       # middle-mouse drag
var _lmb_down: bool = false      # left button held (candidate for drag-pan)
var _lmb_pan: bool = false       # left-drag pan engaged (moved past threshold)
var _lmb_press: Vector2 = Vector2.ZERO
const PAN_DRAG_THRESHOLD: float = 6.0  # px the cursor must move before a left-drag pans
var _last_gold: int = -1
var _last_wave: int = -1
var _last_enemy_count: int = -1
var _dbg_timer: float = 0.0
var _dbg_last_pos: PackedVector2Array = PackedVector2Array()
var _drift_zero_samples: int = 0
var _exiting: bool = false

func _ready():
	# GPUSim is an autoload: agents from a previous battle survive the scene change.
	# Zero the slot counters so the new battle starts empty (stale slots are inert —
	# nothing processes ids >= active_count — and get overwritten by new spawns).
	GPUSim.reset_wave_slots()

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
			_apply_map_config(map_inst)

	await get_tree().process_frame
	_setup_map_logic()
	flow_field.generate_field_for_rect(nexus.global_position, nexus.extents)
	flow_field.save_static_grid()

	# Wire wave manager dependency
	wave_manager.enemy_config = enemy_config

	# Feed per-type gold/nexus-damage tables to the GPU sim (used by the death
	# readback to award kill gold and by the nexus push constants).
	GPUSim.set_enemy_type_data(enemy_config.type_golds, enemy_config.type_nexus_dmg)

	# Signals
	GlobalEvents.nexus_destroyed.connect(_on_nexus_destroyed)
	GlobalEvents.enemy_killed.connect(_on_enemy_killed)

	# HUD buttons
	if has_node("HUD/Overlay/NextWaveButton"):
		$HUD/Overlay/NextWaveButton.pressed.connect(_on_next_wave_pressed)
		$HUD/Overlay/NextWaveButton.visible = true
	if has_node("HUD/Overlay/GameOverContainer/RestartButton"):
		$HUD/Overlay/GameOverContainer/RestartButton.pressed.connect(exit_to_selector)
	if has_node("HUD/Overlay/VictoryContainer/PlayAgainButton"):
		$HUD/Overlay/VictoryContainer/PlayAgainButton.pressed.connect(exit_to_selector)

	Globals.reset_gold()
	if Globals.auto_test_active:
		_run_auto_test_gameplay()
		
	if GPUSim.draw_texture:
		rb_texture_rect.texture = GPUSim.draw_texture

# Apply optional per-map world config from the map root (all reads fall back to
# the current battle.tscn defaults, so map1/map2 — which expose none of these —
# are unaffected). Larger maps (map3) ship a bigger world_size + relocated
# spawn/nexus, and the camera zooms out to fit.
func _apply_map_config(map_root: Node) -> void:
	# Gameplay config (waves, base HP, starting gold) travels WITH the map scene
	# as a MapConfig resource on its root — battle.tscn needs no per-map edits.
	var cfg = map_root.get("config")
	if not (cfg is MapConfig):
		cfg = MapConfig.new()
		push_warning("BATTLE: map '%s' has no MapConfig — using defaults." % map_root.name)
	wave_manager.apply_config(cfg)
	Globals.starting_gold = cfg.starting_gold
	if nexus and nexus.has_method("set_base_hp"):
		nexus.set_base_hp(cfg.base_hp)

	var ws = map_root.get("world_size")
	if ws is Vector2 and ws.x > 0.0 and ws.y > 0.0:
		map_world_size = ws

	# Grow the flow-field grid to cover the world if needed (grow-only, so
	# map1/map2 keep the tuned default grid). Margin matches the default offset.
	var margin := 10
	var cs := float(flow_field.cell_size)
	var need := Vector2i(
		int(ceil(map_world_size.x / cs)) + 2 * margin,
		int(ceil(map_world_size.y / cs)) + 2 * margin)
	if need.x > flow_field.grid_size.x or need.y > flow_field.grid_size.y:
		var target := Vector2i(maxi(need.x, flow_field.grid_size.x), maxi(need.y, flow_field.grid_size.y))
		flow_field.resize_grid(target, Vector2i(-margin, -margin))

	# Spawn/nexus placement: prefer a draggable NexusMarker/SpawnMarker child of the map
	# (editable in the 2D editor), else the map root's nexus_pos/spawn_pos exports, else the
	# battle.tscn defaults.
	if nexus:
		var nmk = map_root.get_node_or_null("NexusMarker")
		if nmk:
			nexus.global_position = nmk.global_position
			if "extents" in nmk and nmk.extents != Vector2.ZERO:
				nexus.extents = nmk.extents
		else:
			var np = map_root.get("nexus_pos")
			if np is Vector2 and np != Vector2.ZERO:
				nexus.position = np
			var nx = map_root.get("nexus_extents")
			if nx is Vector2 and nx != Vector2.ZERO:
				nexus.extents = nx

	var spawner = get_node_or_null("EnemySpawner")
	if spawner:
		var smk = map_root.get_node_or_null("SpawnMarker")
		if smk:
			spawner.global_position = smk.global_position
			if "extents" in smk and smk.extents != Vector2.ZERO:
				spawner.extents = smk.extents
		else:
			var sp = map_root.get("spawn_pos")
			if sp is Vector2 and sp != Vector2.ZERO:
				spawner.position = sp
			var sx = map_root.get("spawn_extents")
			if sx is Vector2 and sx != Vector2.ZERO:
				spawner.extents = sx

	_fit_camera()

# Cover-fit: zoom so the world FILLS the viewport (no letterbox bars). Wider-than-
# screen worlds (map3) overflow horizontally and are explored by panning
# (middle-mouse drag) / zooming (wheel) — see _unhandled_input. The camera keeps
# its FIXED_TOP_LEFT anchor; the GPU agent draw reads the live camera position +
# zoom every frame (see _process), so pan/zoom stay registered.
# map1/map2 (1920×1080, exact 16:9) → cover == fit == 1.0, unchanged.
func _fit_camera() -> void:
	if not camera:
		return
	var vp := get_viewport_rect().size
	_min_zoom = max(vp.x / map_world_size.x, vp.y / map_world_size.y)
	camera.zoom = Vector2(_min_zoom, _min_zoom)
	camera.position = Vector2.ZERO
	_clamp_camera()

# Keep the visible rect inside the world so nothing outside the map ever shows.
func _clamp_camera() -> void:
	if not camera:
		return
	var vp := get_viewport_rect().size
	var view := vp / camera.zoom.x
	camera.position = camera.position.clamp(Vector2.ZERO, (map_world_size - view).max(Vector2.ZERO))

func _unhandled_input(event: InputEvent) -> void:
	if not camera:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# Left-drag also pans (so the wide map is reachable without the middle
			# mouse). Only a candidate while idle — _process_motion gates the actual
			# pan on the placement manager + a small drag threshold so a stationary
			# click still places turrets / edits cones normally.
			_lmb_down = event.pressed
			if event.pressed:
				_lmb_press = event.position
				_lmb_pan = false
			else:
				_lmb_pan = false
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(1.1, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(1.0 / 1.1, event.position)
	elif event is InputEventMouseMotion:
		if _panning:
			camera.position -= event.relative / camera.zoom.x
			_clamp_camera()
		elif _lmb_down and not _is_placing_turret():
			if not _lmb_pan and event.position.distance_to(_lmb_press) > PAN_DRAG_THRESHOLD:
				_lmb_pan = true
			if _lmb_pan:
				camera.position -= event.relative / camera.zoom.x
				_clamp_camera()

# Whether the turret placement manager is mid-placement / cone-edit. Left-drag pan
# yields to it so a placement click is never hijacked by the camera.
func _is_placing_turret() -> bool:
	var tpm = get_node_or_null("TurretPlacementManager")
	return tpm != null and tpm.has_method("is_placing") and tpm.is_placing()

# The ONLY safe way to leave a battle. Changing scene while the GPU sim is
# dispatching segfaults the process (signal 11 inside compute_list_dispatch —
# the queued compute races the scene teardown freeing the flow textures), so
# stop our per-frame GPU work, let one frame drain, then change scene.
func exit_to_selector() -> void:
	if _exiting:
		return
	_exiting = true
	set_process(false)
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://ui/level_selector.tscn")

func _exit_tree() -> void:
	set_process(false)
	# Drain in-flight render work first: dispatch/draw lambdas queued this frame
	# still reference this battle's flow-field textures, and the scene teardown
	# frees those textures concurrently — executing the queued compute after the
	# free segfaults the process (signal 11 in compute_list_dispatch).
	RenderingServer.force_sync()
	# GPUSim (autoload) binds this battle's flow-field textures in its physics uniform set.
	# Release that set now, before the flow field frees those textures on teardown, to avoid
	# a double-free of an auto-invalidated RID.
	if GPUSim and GPUSim.has_method("release_flow_bindings"):
		GPUSim.release_flow_bindings()

# Zoom about the cursor so the point under the mouse stays put.
func _zoom_camera(factor: float, screen_pos: Vector2) -> void:
	var old_z: float = camera.zoom.x
	var new_z: float = clampf(old_z * factor, _min_zoom, _min_zoom * 2.5)
	if is_equal_approx(new_z, old_z):
		return
	var world_at_mouse := camera.position + screen_pos / old_z
	camera.zoom = Vector2(new_z, new_z)
	camera.position = world_at_mouse - screen_pos / new_z
	_clamp_camera()

func _setup_map_logic():
	var map_root = $SmartShapeMap
	if not map_root: return

	# Walkability source, in priority order:
	#  1) get_mask_image()  — mask-driven maps (map1/map2).
	#  2) group pieces      — kit maps: Polygon2D in group "map_path" (walkable) minus
	#                         group "map_wall" (dirt islands); walkability = the union.
	#  3) legacy single     — a "Grass_Path" Polygon2D minus Dirt_Mound/Top_Dirt/Bottom_Dirt.
	# All three feed the same obstacle grid / hi-res mask / SDF / flow pipeline.
	var mask_img: Image = null
	if map_root.has_method("get_mask_image"):
		mask_img = map_root.get_mask_image()

	var path_polys: Array[PackedVector2Array] = []
	var path_aabbs: Array[Rect2] = []
	var obstacle_polys: Array[PackedVector2Array] = []
	var obstacle_aabbs: Array[Rect2] = []
	if not mask_img:
		_gather_map_polys(map_root, path_polys, path_aabbs, obstacle_polys, obstacle_aabbs)

	# Need a mask OR at least one walkable polygon to define the map.
	if not mask_img and path_polys.is_empty():
		return

	var cell_size: float  = float(flow_field.cell_size)
	var offset: Vector2i  = flow_field.grid_offset
	var obs_sub: int      = flow_field.obs_sub

	# --- Flow-field tile grid (coarse 32px): 3×3-multisample, walkable if ANY sub-point
	# is grass-and-not-obstacle, so path-edge cells get flow. ---
	for x in range(flow_field.grid_size.x):
		for y in range(flow_field.grid_size.y):
			var cell_origin = Vector2(x + offset.x, y + offset.y) * cell_size
			var walkable = false
			for sx in range(3):
				for sy in range(3):
					var wp = cell_origin + Vector2((sx + 0.5) / 3.0, (sy + 0.5) / 3.0) * cell_size
					if _point_walkable(wp, mask_img, path_polys, path_aabbs, obstacle_polys, obstacle_aabbs):
						walkable = true
						break
				if walkable:
					break
			flow_field.set_obstacle(Vector2i(x + offset.x, y + offset.y), not walkable)

	# Commit the coarse grid (pushes obstacle texture, regenerates flow if targeted).
	flow_field.commit_obstacles()

	# --- High-res obstacle image (obs_sub pixels per tile) for GPU wall collision + SDF ---
	var img_w = flow_field.grid_size.x * obs_sub
	var img_h = flow_field.grid_size.y * obs_sub

	# Build lookup data (copy to locals for thread safety)
	var _cell_size: float = cell_size
	var _offset: Vector2i = offset
	var _obs_sub: float   = float(obs_sub)
	var _sub_size2: float = _cell_size / _obs_sub
	var _path_polys := path_polys
	var _path_aabbs := path_aabbs
	var _obstacle_polys := obstacle_polys
	var _obstacle_aabbs := obstacle_aabbs
	var _mask_img := mask_img

	# Rasterise each row in parallel (each row writes unique indices, no lock needed)
	var pixel_data := PackedByteArray()
	pixel_data.resize(img_w * img_h)
	var _rasterise_row := func(row: int) -> void:
		for col in range(img_w):
			var wp := Vector2(
				(float(col) / _obs_sub + _offset.x) * _cell_size + _sub_size2 * 0.5,
				(float(row) / _obs_sub + _offset.y) * _cell_size + _sub_size2 * 0.5
			)
			pixel_data[row * img_w + col] = 0 if _point_walkable(wp, _mask_img, _path_polys, _path_aabbs, _obstacle_polys, _obstacle_aabbs) else 255
	var group_id := WorkerThreadPool.add_group_task(_rasterise_row, img_h, true)
	WorkerThreadPool.wait_for_group_task_completion(group_id)

	# Upload the fine mask for physics wall collision.
	var hi_res := Image.create_from_data(img_w, img_h, false, Image.FORMAT_L8, pixel_data)
	flow_field.hi_res_obs_image = hi_res
	flow_field.hi_res_obs_texture.update(hi_res)

	_build_wall_sdf(pixel_data, img_w, img_h, _sub_size2)

# Walkability test shared by the coarse grid and the hi-res raster. When a mask image is
# supplied (map1/map2), sample it (white = walkable); points outside the world rect are
# walls. Otherwise (kit/legacy maps) walkable = inside ANY path polygon AND NOT inside any
# obstacle polygon. AABB-culled so each point only tests the few pieces it overlaps.
# Read-only; safe to call from WorkerThreadPool row tasks.
func _point_walkable(wp: Vector2, mask_img: Image, path_polys: Array, path_aabbs: Array,
		obstacle_polys: Array, obstacle_aabbs: Array) -> bool:
	if mask_img:
		if wp.x < 0.0 or wp.y < 0.0 or wp.x >= map_world_size.x or wp.y >= map_world_size.y:
			return false
		var px := clampi(int(wp.x / map_world_size.x * mask_img.get_width()), 0, mask_img.get_width() - 1)
		var py := clampi(int(wp.y / map_world_size.y * mask_img.get_height()), 0, mask_img.get_height() - 1)
		return mask_img.get_pixel(px, py).r > 0.5
	var in_path := false
	for i in range(path_polys.size()):
		if path_aabbs[i].has_point(wp) and Geometry2D.is_point_in_polygon(wp, path_polys[i]):
			in_path = true
			break
	if not in_path:
		return false
	for i in range(obstacle_polys.size()):
		if obstacle_aabbs[i].has_point(wp) and Geometry2D.is_point_in_polygon(wp, obstacle_polys[i]):
			return false
	return true

# Collect world-space walkable/obstacle polygons (+ AABBs) for a kit or legacy map. Kit maps
# tag Polygon2D pieces with groups "map_path"/"map_wall"; legacy maps expose a single
# "Grass_Path" plus "Dirt_Mound"/"Top_Dirt"/"Bottom_Dirt".
func _gather_map_polys(map_root: Node, path_polys: Array, path_aabbs: Array,
		obstacle_polys: Array, obstacle_aabbs: Array) -> void:
	var all_polys := map_root.find_children("*", "Polygon2D", true, false)
	var path_nodes := all_polys.filter(func(n): return n.is_in_group("map_path"))
	var wall_nodes := all_polys.filter(func(n): return n.is_in_group("map_wall"))
	if path_nodes.is_empty():  # legacy single-Grass_Path fallback
		var gp = map_root.get_node_or_null("Grass_Path")
		if gp:
			path_nodes = [gp]
		for nm in ["Dirt_Mound", "Top_Dirt", "Bottom_Dirt"]:
			var d = map_root.get_node_or_null(nm)
			if d:
				wall_nodes.append(d)
	for n in path_nodes:
		var wp := _poly_to_world(n)
		if wp.size() >= 3:
			path_polys.append(wp)
			path_aabbs.append(_poly_aabb(wp))
	for n in wall_nodes:
		var wp := _poly_to_world(n)
		if wp.size() >= 3:
			obstacle_polys.append(wp)
			obstacle_aabbs.append(_poly_aabb(wp))

func _poly_to_world(node: Polygon2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in node.polygon:
		out.append(node.to_global(v))
	return out

func _poly_aabb(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for i in range(1, poly.size()):
		r = r.expand(poly[i])
	return r

# Build a fine signed-distance field (free-space distance to nearest wall, in WORLD
# units) from the hi-res obstacle mask, via a two-pass chamfer distance transform.
# Same resolution as the hi-res obstacle texture. Used by the physics compute for
# continuous wall-avoidance steering (agents ride path centers, no edge-cell pins).
# One-time at map load. (The GPU JFA SDF generator is unavailable — its shader
# sources are missing — so this runs on the CPU.)
func _build_wall_sdf(pixel_data: PackedByteArray, img_w: int, img_h: int, sub_world: float) -> void:
	var INF := 1.0e9
	var DIAG := 1.4142135623730951
	var dist := PackedFloat32Array()
	dist.resize(img_w * img_h)
	# Seed: walls (and out-of-grass, both encoded as 255) = 0, free space = INF.
	for i in range(img_w * img_h):
		dist[i] = 0.0 if pixel_data[i] == 255 else INF
	# Forward pass: up, left, up-left, up-right.
	for y in range(img_h):
		for x in range(img_w):
			var idx := y * img_w + x
			var d := dist[idx]
			if d == 0.0:
				continue
			if y > 0:
				d = min(d, dist[idx - img_w] + 1.0)
				if x > 0:
					d = min(d, dist[idx - img_w - 1] + DIAG)
				if x < img_w - 1:
					d = min(d, dist[idx - img_w + 1] + DIAG)
			if x > 0:
				d = min(d, dist[idx - 1] + 1.0)
			dist[idx] = d
	# Backward pass: down, right, down-right, down-left.
	for y in range(img_h - 1, -1, -1):
		for x in range(img_w - 1, -1, -1):
			var idx := y * img_w + x
			var d := dist[idx]
			if d == 0.0:
				continue
			if y < img_h - 1:
				d = min(d, dist[idx + img_w] + 1.0)
				if x < img_w - 1:
					d = min(d, dist[idx + img_w + 1] + DIAG)
				if x > 0:
					d = min(d, dist[idx + img_w - 1] + DIAG)
			if x < img_w - 1:
				d = min(d, dist[idx + 1] + 1.0)
			dist[idx] = d
	# Convert pixel distances to world units in place.
	for i in range(img_w * img_h):
		dist[i] = dist[i] * sub_world
	var sdf_img := Image.create_from_data(img_w, img_h, false, Image.FORMAT_RF, dist.to_byte_array())
	flow_field.wall_sdf_image = sdf_img
	flow_field.wall_sdf_texture = ImageTexture.create_from_image(sdf_img)

func is_point_walkable(pos: Vector2) -> bool:
	var gp = Vector2i((pos / float(flow_field.cell_size)).floor()) - flow_field.grid_offset
	if gp.x >= 0 and gp.x < flow_field.grid_size.x and gp.y >= 0 and gp.y < flow_field.grid_size.y:
		if flow_field.obs_image:
			return flow_field.obs_image.get_pixel(gp.x, gp.y).r < 0.5
	return false

func _process(delta):
	# The dying scene runs one more _process during change_scene; get_viewport_rect()
	# and the GPU dispatch are invalid once we've left the tree.
	if not is_inside_tree():
		return
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
		"radius": 64.0, # legacy; arrival now uses the full box (extents) below
		"extents": nexus.extents if nexus else Vector2(10.0, 130.0),
		"valid": 1 if nexus else 0
	}
	
	if flow_field.ff_texture and flow_field.obs_texture:
		# obs_texture (100x60) is used by the flow field GPU compute
		# hi_res_obs_texture (400x240) is used by the physics GPU for accurate wall collision
		var phys_obs = flow_field.hi_res_obs_texture if flow_field.hi_res_obs_texture else flow_field.obs_texture
		GPUSim.update_flow_field_textures(flow_field.ff_texture, phys_obs, flow_field.wall_sdf_texture)
		
	GPUSim.dispatch_physics(delta, current_ms, ff_data, nex_data, {})
	
	if camera:
		var viewport_size = get_viewport_rect().size
		var cam_pos = camera.global_position
		var zoom = camera.zoom.x
		RenderingServer.call_on_render_thread(func():
			GPUSim.draw_agents(cam_pos, viewport_size, zoom)
		)

	# Congestion repath: converge the in-flight flow rebuild a bit each frame.
	flow_field.tick_flow_rebuild()

	_dbg_timer += delta
	if _dbg_timer >= 2.0:
		_dbg_timer = 0.0
		var dbg_nexus_pos = nexus.global_position if nexus else Vector2.ZERO
		var dbg_prev = _dbg_last_pos
		GPUSim.get_agent_data_async(func(positions: PackedVector2Array, healths: PackedFloat32Array):
			var alive := 0
			var stuck := 0
			for i in range(positions.size()):
				if healths[i] > 0.0:
					alive += 1
					if dbg_prev.size() > i and positions[i].distance_to(dbg_prev[i]) < 2.0 and positions[i].distance_to(dbg_nexus_pos) > 100.0:
						stuck += 1
			_dbg_last_pos = positions
			print("[DBG] alive=%d stuck=%d counter=%d active=%d spawning=%s" % [alive, stuck, GPUSim.alive_count, GPUSim.active_count, str(wave_manager.is_spawning)])
			# Drift valve: if the exact readback says everything is dead but the
			# incremental counter disagrees (dead-record segment overflowed), force it
			# after two consecutive samples so the wave can clear.
			if alive == 0 and GPUSim.alive_count > 0 and not wave_manager.is_spawning:
				_drift_zero_samples += 1
				if _drift_zero_samples >= 2:
					push_warning("BATTLE: alive_count drift (counter=%d, actual=0) — forcing 0" % GPUSim.alive_count)
					GPUSim.alive_count = 0
					_drift_zero_samples = 0
			else:
				_drift_zero_samples = 0
			# Congestion repath (piggybacks on this readback): refresh the density
			# texture from live agents and kick an amortized flow rebuild so the
			# field steers new traffic around crowded lanes.
			if not is_game_over and is_instance_valid(flow_field) and not flow_field.is_flow_rebuilding() and alive > 0:
				flow_field.update_density(positions, healths)
				flow_field.start_flow_rebuild()
		)

	if is_game_over: return
	wave_manager.tick(delta, _spawn_single_enemy)

	if (not wave_manager.is_spawning and
		not wave_manager.is_inter_wave and
		wave_manager.current_wave > 0 and
		GPUSim.alive_count == 0):

		GPUSim.reset_wave_slots()
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
			
	if GPUSim.alive_count != _last_enemy_count:
		_last_enemy_count = GPUSim.alive_count
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
