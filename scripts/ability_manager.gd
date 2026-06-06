extends Node2D
class_name AbilityManager

@onready var mana_bar: ProgressBar = get_node("/root/Battle/HUD/Overlay/ManaBar")
@onready var ability_container: HBoxContainer = get_node("/root/Battle/HUD/Overlay/AbilityContainer")


@export var ability_configs: Array[AbilityConfig] = []

var all_abilities = {}

func _initialize_abilities():
	if not ability_configs.is_empty():
		for config in ability_configs:
			if not config: continue
			all_abilities[config.name] = {
				"name": config.name,
				"cost": config.cost,
				"cooldown": config.cooldown,
				"radius": config.radius,
				"damage": config.damage,
				"type": config.type,
				"duration": config.duration,
				"bounces": config.bounces,
				"bounce_range": config.bounce_range,
				"multiplier": config.multiplier,
				"slow_factor": config.slow_factor,
				"current_cooldown": 0.0,
				"button": null
			}
	else:
		all_abilities = {
			"Orbital Strike": { "name": "Orbital Strike", "cost": 50.0, "cooldown": 5.0, "radius": 50.0, "damage": 150.0, "type": "target", "current_cooldown": 0.0, "button": null },
			"Frost Nova": { "name": "Frost Nova", "cost": 30.0, "cooldown": 4.0, "radius": 38.0, "duration": 3.0, "type": "target", "current_cooldown": 0.0, "button": null },
			"Chain Lightning": { "name": "Chain Lightning", "cost": 40.0, "cooldown": 3.0, "damage": 40.0, "bounces": 5, "bounce_range": 180.0, "radius": 45.0, "type": "target", "current_cooldown": 0.0, "button": null },
			"Overdrive": { "name": "Overdrive", "cost": 60.0, "cooldown": 12.0, "duration": 5.0, "multiplier": 1.5, "type": "instant", "current_cooldown": 0.0, "button": null },
			"Acid Pool": { "name": "Acid Pool", "cost": 35.0, "cooldown": 6.0, "radius": 30.0, "damage": 15.0, "duration": 4.0, "slow_factor": 0.8, "type": "target", "current_cooldown": 0.0, "button": null },
			"Dynamite": { "name": "Dynamite", "cost": 25.0, "cooldown": 4.0, "radius": 60.0, "damage": 80.0, "duration": 1.5, "type": "target", "current_cooldown": 0.0, "button": null }
		}

var abilities = []
var active_ability_index: int = -1
var aoe_ring: Node2D = null

const RangeIndicatorScript = preload("res://scripts/range_indicator.gd")

func _ready():
	GlobalEvents.mana_changed.connect(_on_mana_changed)
	GlobalEvents.wave_started.connect(_on_wave_started)
	
	_initialize_abilities()
	
	# Load equipped abilities from Globals
	abilities = []
	for ability_name in Globals.equipped_abilities:
		if all_abilities.has(ability_name):
			abilities.append(all_abilities[ability_name].duplicate())
	
	if mana_bar:
		mana_bar.max_value = Globals.max_mana
		mana_bar.value = Globals.mana
		mana_bar.visible = true
		
	if ability_container:
		ability_container.visible = true
		
	_setup_ui()

func _on_wave_started(_wave_num: int, _enemy_count: int):
	# Keep visible
	pass

func _process(delta):
	for i in range(abilities.size()):
		var ability = abilities[i]
		if ability.current_cooldown > 0.0:
			ability.current_cooldown -= delta
			if ability.current_cooldown <= 0.0:
				ability.current_cooldown = 0.0
		
		_update_button_state(i)
	
	_update_aoe_ring_position()

func _unhandled_input(event):
	if active_ability_index == -1: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_cast_ability(active_ability_index, get_global_mouse_position())
		_clear_targeting()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_clear_targeting()
		get_viewport().set_input_as_handled()

func _clear_targeting():
	active_ability_index = -1
	if aoe_ring:
		aoe_ring.queue_free()
		aoe_ring = null

func _setup_ui():
	if not ability_container: return
	
	for child in ability_container.get_children():
		child.queue_free()
		
	for i in range(abilities.size()):
		var ability = abilities[i]
		var btn = Button.new()
		btn.text = ability.name + "\n(" + str(ability.cost) + " MP)"
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(func(): _on_ability_button_pressed(i))
		ability_container.add_child(btn)
		ability.button = btn

func _on_mana_changed(current: float, max_m: float):
	if mana_bar:
		mana_bar.max_value = max_m
		mana_bar.value = current

func _update_button_state(index: int):
	var ability = abilities[index]
	var btn: Button = ability.button
	if not btn: return
	
	var wave_manager = get_node_or_null("/root/Battle/WaveManager")
	var is_wave_active = wave_manager and wave_manager.current_wave > 0 and not wave_manager.is_inter_wave
	
	if not is_wave_active:
		btn.disabled = true
		btn.text = ability.name + "\n(" + str(ability.cost) + " MP)"
	elif ability.current_cooldown > 0.0:
		btn.disabled = true
		btn.text = ability.name + "\n(CD: " + str(snapped(ability.current_cooldown, 0.1)) + "s)"
	elif Globals.mana < ability.cost:
		btn.disabled = true
		btn.text = ability.name + "\n(" + str(ability.cost) + " MP)"
	else:
		btn.disabled = false
		if active_ability_index == index:
			btn.text = "[ " + ability.name + " ]"
		else:
			btn.text = ability.name + "\n(" + str(ability.cost) + " MP)"

func _on_ability_button_pressed(index: int):
	var wave_manager = get_node_or_null("/root/Battle/WaveManager")
	var is_wave_active = wave_manager and wave_manager.current_wave > 0 and not wave_manager.is_inter_wave
	if not is_wave_active: return

	var ability = abilities[index]
	if ability.current_cooldown <= 0.0 and Globals.mana >= ability.cost:
		if ability.type == "instant":
			_cast_ability(index, Vector2.ZERO)
		else:
			if active_ability_index == index:
				_clear_targeting()
			else:
				active_ability_index = index
				_show_aoe_ring(ability)

func _cast_ability(index: int, pos: Vector2):
	var ability = abilities[index]
	
	if Globals.spend_mana(ability.cost):
		ability.current_cooldown = ability.cooldown
		
		# Execute Ability Effect
		match ability.name:
			"Orbital Strike":
				_do_orbital_strike(pos, ability.radius, ability.damage)
			"Frost Nova":
				_do_frost_nova(pos, ability.radius, ability.duration)
			"Chain Lightning":
				_do_chain_lightning(pos, ability.damage, ability.bounces, ability.bounce_range, ability.radius, ability)
			"Overdrive":
				_do_overdrive(ability.duration, ability.multiplier)
			"Acid Pool":
				_do_acid_pool(pos, ability.radius, ability.damage, ability.duration, ability.slow_factor)
			"Dynamite":
				_do_dynamite(pos, ability.damage, ability.radius, ability.duration)

func _do_orbital_strike(pos: Vector2, radius: float, damage: float):
	GlobalEvents.aoe_damage_requested.emit(pos, radius, damage, false)
		
	# Visuals
	var beam_script = load("res://scripts/orbital_beam_effect.gd")
	if beam_script:
		var beam = Node2D.new()
		beam.set_script(beam_script)
		get_parent().add_child(beam)
		beam.init(pos, radius)
		
	SoundManager.play_sfx("shoot_mortar")
	
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(0.5, 15.0)

func _do_frost_nova(pos: Vector2, radius: float, duration: float):
	GlobalEvents.aoe_freeze_requested.emit(pos, radius, duration)
		
	# Visuals
	var fn_script = load("res://scripts/frost_nova_effect.gd")
	if fn_script:
		var fn = Node2D.new()
		fn.set_script(fn_script)
		get_parent().add_child(fn)
		fn.init(pos, radius)
		
	SoundManager.play_sfx("shoot_laser")
	
	var camera = get_viewport().get_camera_2d()
	if camera and camera.has_method("shake"):
		camera.shake(0.3, 8.0)

func _do_chain_lightning(pos: Vector2, damage: float, bounces: int, bounce_range: float, radius: float, ability: Dictionary):
	
	
	GPUSim.get_agent_data_async(func(positions: PackedVector2Array, healths: PackedFloat32Array):
		var count = positions.size()
		if count == 0:
			Globals.mana = minf(Globals.mana + ability.cost, Globals.max_mana)
			GlobalEvents.mana_changed.emit(Globals.mana, Globals.max_mana)
			ability.current_cooldown = 0.0
			return
			
		# Find first target
		var target_idx = -1
		var min_dist = radius
		for i in range(count):
			if healths[i] > 0.0:
				var d = positions[i].distance_to(pos)
				if d < min_dist:
					min_dist = d
					target_idx = i
					
		if target_idx == -1:
			Globals.mana = minf(Globals.mana + ability.cost, Globals.max_mana)
			GlobalEvents.mana_changed.emit(Globals.mana, Globals.max_mana)
			ability.current_cooldown = 0.0
			return
			
		# Bouncing sequence
		var hit_indices = [target_idx]
		var current_pos = positions[target_idx]
		
		for bounce in range(bounces - 1):
			var next_idx = -1
			var next_min_dist = bounce_range
			for i in range(count):
				if healths[i] > 0.0 and not hit_indices.has(i):
					var d = positions[i].distance_to(current_pos)
					if d < next_min_dist:
						next_min_dist = d
						next_idx = i
			if next_idx != -1:
				hit_indices.append(next_idx)
				current_pos = positions[next_idx]
			else:
				break
				
		# Apply damage
		for idx in hit_indices:
			GlobalEvents.aoe_damage_requested.emit(positions[idx], 10.0, damage, false)
			
		# Visuals: vertical bolts from sky onto each hit enemy
		var cl_script = load("res://scripts/chain_lightning_effect.gd")
		if cl_script:
			var cl = Node2D.new()
			cl.set_script(cl_script)
			get_parent().add_child(cl)
			var hit_positions: Array[Vector2] = []
			for idx in hit_indices:
				hit_positions.append(positions[idx])
			cl.init_bolts_from_above(hit_positions)
			
		SoundManager.play_sfx("shoot_gatling")
	)

func _do_overdrive(duration: float, multiplier: float):
	var turrets = get_tree().get_nodes_in_group("turret")
	var actual_turrets: Array = []
	for t in turrets:
		if t is Turret:
			actual_turrets.append(t)
	
	# Only activate if turrets are placed
	if actual_turrets.is_empty():
		# Refund mana since no turrets to boost
		Globals.mana = minf(Globals.mana + 60.0, Globals.max_mana)
		GlobalEvents.mana_changed.emit(Globals.mana, Globals.max_mana)
		return
	
	for t in actual_turrets:
		t.overdrive_timer = duration
		t.overdrive_multiplier = multiplier
		
	SoundManager.play_sfx("sell")

func _do_acid_pool(pos: Vector2, radius: float, damage: float, duration: float, slow_factor: float):
	var pool_script = load("res://scripts/acid_pool_effect.gd")
	if pool_script:
		var pool = Node2D.new()
		pool.set_script(pool_script)
		get_parent().add_child(pool)
		pool.init(pos, radius, damage, duration, slow_factor, )
		
	SoundManager.play_sfx("shoot_plasma")

func _do_dynamite(pos: Vector2, damage: float, radius: float, duration: float):
	var dyn_script = load("res://scripts/dynamite_effect.gd")
	if dyn_script:
		var dyn = Node2D.new()
		dyn.set_script(dyn_script)
		get_parent().add_child(dyn)
		dyn.init(pos, damage, radius, duration)
		
	SoundManager.play_sfx("sell") # placement sound

func _show_aoe_ring(ability: Dictionary):
	# Remove old ring
	if aoe_ring:
		aoe_ring.queue_free()
		aoe_ring = null
	
	var r = ability.get("radius", 0.0)
	if r <= 0.0: return
	
	aoe_ring = RangeIndicatorScript.new()
	aoe_ring.radius = r
	aoe_ring.fill_color = Color(1.0, 0.8, 0.2, 0.1)
	aoe_ring.line_color = Color(1.0, 0.8, 0.2, 0.5)
	aoe_ring.z_index = 11
	get_parent().add_child(aoe_ring)

func _update_aoe_ring_position():
	if aoe_ring and active_ability_index != -1:
		aoe_ring.global_position = get_global_mouse_position()
