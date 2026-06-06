extends Node

const POOL_SIZE: int = 24
const THROTTLE_MS: int = 50

var _players: Array[AudioStreamPlayer] = []
var _next_player_idx: int = 0
var _sfx_cache: Dictionary = {}
var _last_play_time: Dictionary = {}

func _ready():
	# Generate procedural sounds
	var sound_keys = [
		"shoot_gatling",
		"shoot_laser",
		"shoot_ray",
		"shoot_melee",
		"shoot_slow",
		"build",
		"sell",
		"hit",
		"wave_start",
		"wave_clear",
		"defeat"
	]
	
	for key in sound_keys:
		_sfx_cache[key] = _generate_synth_sfx(key)
		_last_play_time[key] = 0
		
	# Create pool of players
	for i in range(POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)

func play_sfx(key: String, custom_pitch: float = 0.0):
	if not _sfx_cache.has(key):
		return
		
	var now = Time.get_ticks_msec()
	if now - _last_play_time[key] < THROTTLE_MS:
		return
		
	_last_play_time[key] = now
	
	var player = _find_idle_player()
	player.stream = _sfx_cache[key]
	player.pitch_scale = custom_pitch if custom_pitch > 0.0 else randf_range(0.9, 1.1)
	player.play()

func _find_idle_player() -> AudioStreamPlayer:
	# Try to find a player that is not currently playing
	for i in range(POOL_SIZE):
		var idx = (_next_player_idx + i) % POOL_SIZE
		if not _players[idx].playing:
			_next_player_idx = (idx + 1) % POOL_SIZE
			return _players[idx]
			
	# Fallback: steal the next player in round-robin fashion
	var player = _players[_next_player_idx]
	_next_player_idx = (_next_player_idx + 1) % POOL_SIZE
	return player

func _generate_synth_sfx(type: String) -> AudioStreamWAV:
	var sample = AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.loop_mode = AudioStreamWAV.LOOP_DISABLED
	
	var mix_rate = 22050
	sample.mix_rate = mix_rate
	
	var data = PackedByteArray()
	
	match type:
		"shoot_gatling":
			var duration = 0.08
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 40.0)
				var noise = randf_range(-1.0, 1.0) * env
				var click = sin(2.0 * PI * 1200.0 * t) * env
				var s = clampf(noise * 0.4 + click * 0.6, -1.0, 1.0)
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"shoot_laser":
			var duration = 0.15
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 15.0)
				var freq = lerpf(1800.0, 400.0, t / duration)
				phase += (2.0 * PI * freq) / mix_rate
				var s = sin(phase) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"shoot_ray":
			var duration = 0.12
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 20.0)
				var freq = 1500.0
				phase += (2.0 * PI * freq) / mix_rate
				var s = sin(phase) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"shoot_melee":
			var duration = 0.35
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 8.0)
				var noise = randf_range(-1.0, 1.0)
				var rumble = sin(2.0 * PI * 80.0 * t)
				var s = clampf((noise * 0.5 + rumble * 0.5) * env, -1.0, 1.0)
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"shoot_slow":
			var duration = 0.2
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase1 = 0.0
			var phase2 = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 12.0)
				var freq1 = lerpf(800.0, 1200.0, t / duration)
				var freq2 = freq1 * 1.5
				phase1 += (2.0 * PI * freq1) / mix_rate
				phase2 += (2.0 * PI * freq2) / mix_rate
				var s = (sin(phase1) * 0.5 + sin(phase2) * 0.3) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"build":
			var duration = 0.25
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 8.0)
				var freq = 440.0
				if t > 0.08:
					freq = 554.37
				if t > 0.16:
					freq = 659.25
				phase += (2.0 * PI * freq) / mix_rate
				var s = sin(phase) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"sell":
			var duration = 0.25
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 8.0)
				var freq = 659.25
				if t > 0.08:
					freq = 554.37
				if t > 0.16:
					freq = 440.0
				phase += (2.0 * PI * freq) / mix_rate
				var s = sin(phase) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"hit":
			var duration = 0.04
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 80.0)
				var s = randf_range(-0.5, 0.5) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"wave_start":
			var duration = 0.6
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase1 = 0.0
			var phase2 = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = clampf(t / 0.1, 0.0, 1.0) * exp(-(t - 0.1) * 3.0) if t > 0.1 else t / 0.1
				var freq = lerpf(220.0, 440.0, t / duration)
				phase1 += (2.0 * PI * freq) / mix_rate
				phase2 += (2.0 * PI * (freq * 1.01)) / mix_rate
				var s = (sin(phase1) * 0.4 + sin(phase2) * 0.4) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"wave_clear":
			var duration = 0.5
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase1 = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 5.0)
				var freq1 = 523.25
				if t > 0.1: freq1 = 659.25
				if t > 0.2: freq1 = 783.99
				if t > 0.3: freq1 = 1046.50
				phase1 += (2.0 * PI * freq1) / mix_rate
				var s = sin(phase1) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF
				
		"defeat":
			var duration = 1.0
			var num_samples = int(mix_rate * duration)
			data.resize(num_samples * 2)
			var phase = 0.0
			for i in range(num_samples):
				var t = float(i) / mix_rate
				var env = exp(-t * 2.0)
				var freq = lerpf(300.0, 80.0, t / duration)
				phase += (2.0 * PI * freq) / mix_rate
				var s = sin(phase) * env
				var val = int(s * 32767.0)
				data[i * 2] = val & 0xFF
				data[i * 2 + 1] = (val >> 8) & 0xFF

	sample.data = data
	return sample
