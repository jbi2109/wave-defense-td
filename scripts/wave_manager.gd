extends Node
class_name WaveManager

# ─────────────────────────────────────────────────────────────
#  Exports
# ─────────────────────────────────────────────────────────────
@export var base_enemies_per_wave: int   = 100
@export var wave_scaler: float           = 1.1
@export var spawn_rate: float            = 0.001   ## Seconds between individual spawns
@export var inter_wave_duration: float   = 10.0    ## Seconds between waves

# ─────────────────────────────────────────────────────────────
#  State
# ─────────────────────────────────────────────────────────────
var current_wave: int     = 0
var enemies_to_spawn: int = 0
var enemies_spawned: int  = 0
var is_spawning: bool     = false
var is_inter_wave: bool   = false

var _spawn_timer: float      = 0.0
var _inter_wave_timer: float = 0.0

# ─────────────────────────────────────────────────────────────
#  Dependencies (set by Main after ready)
# ─────────────────────────────────────────────────────────────
var enemy_manager: EnemyManager = null

# ─────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────
func enemies_for_wave(wave: int) -> int:
	return int(base_enemies_per_wave * pow(wave_scaler, wave - 1))

func start_wave():
	if is_spawning: return
	current_wave   += 1
	enemies_to_spawn = enemies_for_wave(current_wave)
	enemies_spawned  = 0
	is_spawning      = true
	is_inter_wave    = false
	_spawn_timer     = 0.0
	GlobalEvents.wave_started.emit(current_wave, enemies_to_spawn)
	print("--- WAVE %d STARTED | Spawning %d enemies ---" % [current_wave, enemies_to_spawn])

func start_inter_wave():
	is_spawning        = false
	is_inter_wave      = true
	_inter_wave_timer  = inter_wave_duration
	GlobalEvents.wave_cleared.emit(current_wave)

## Called externally (e.g. HUD "Start Early" button)
func skip_inter_wave():
	if not is_inter_wave: return
	_inter_wave_timer = 0.0

# ─────────────────────────────────────────────────────────────
#  Process
# ─────────────────────────────────────────────────────────────
func tick(delta: float, spawn_callback: Callable):
	if is_spawning:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_timer = spawn_rate
			while _spawn_timer <= 0.0 and enemies_spawned < enemies_to_spawn:
				spawn_callback.call()
				_spawn_timer += spawn_rate
			spawn_callback.call()
			enemies_spawned += 1

		if enemies_spawned >= enemies_to_spawn:
			is_spawning = false

	elif is_inter_wave:
		_inter_wave_timer -= delta
		GlobalEvents.inter_wave_tick.emit(_inter_wave_timer)
		if _inter_wave_timer <= 0.0:
			is_inter_wave = false
			start_wave()
