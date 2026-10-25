class_name FlightAudio
extends Node
## Native looping PCM voices avoid per-frame sample synthesis and buffer underruns.
const SAMPLE_RATE := 22050
const ROTOR_GAIN_DB := -12.5
const ROTOR_BASE_HZ := 200.0
var drone: FPVDrone
var motors: Array[AudioStreamPlayer] = []
var shutter: AudioStreamPlayer
var gate_chime: AudioStreamPlayer
var finish_chime: AudioStreamPlayer
var levels := PackedFloat32Array([0, 0, 0, 0])
var pitches := PackedFloat32Array([1, 1, 1, 1])
var pops: Array[AudioStreamPlayer3D] = []
var next_pop := 0

func _ready() -> void:
	for index in 4:
		var player := AudioStreamPlayer.new()
		# Independent airflow/phase texture prevents identical phase-locked tones.
		player.stream = rotor_stream(30491 + index * 787)
		player.bus = "Motors" if AudioServer.get_bus_index("Motors") >= 0 else "Master"
		player.volume_db = -80
		add_child(player)
		motors.append(player)
		# Headless validates synthesis/control mapping without opening audio playback.
		if DisplayServer.get_name() != "headless":
			player.play(index * 0.173)
	shutter = AudioStreamPlayer.new()
	shutter.stream = shutter_stream()
	shutter.bus = "Shutter" if AudioServer.get_bus_index("Shutter") >= 0 else "Master"
	shutter.volume_db = -9
	add_child(shutter)
	gate_chime = _make_cue(race_stream(false))
	finish_chime = _make_cue(race_stream(true))
	for index in 6:
		var pop := AudioStreamPlayer3D.new()
		pop.stream = balloon_stream()
		pop.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
		pop.volume_db = -9
		pop.unit_size = 10
		pop.max_distance = 90
		add_child(pop)
		pops.append(pop)

func _exit_tree() -> void:
	for player in motors:
		player.stop()
	if is_instance_valid(shutter):
		shutter.stop()
	for cue: AudioStreamPlayer in [gate_chime, finish_chime]:
		if is_instance_valid(cue):
			cue.stop()
	for pop in pops:
		pop.stop()

func _process(delta: float) -> void:
	if not is_instance_valid(drone):
		return
	for index in 4:
		var force := float(drone.motor_forces[index]) / maxf(0.01, float(drone.spec.get("max_thrust", 4)))
		var audible := not drone.freeze and not drone.altitude_cutoff and force > 0.0001
		var rpm := sqrt(clampf(force, 0, 1))
		# Individual motor mixing carries roll/pitch/yaw into the sound.
		# Avoid synthetic detuning/beating and excessive high-throttle pitch.
		var pitch := 0.65 + rpm * 1.75
		pitches[index] = lerpf(pitches[index], pitch, 1.0 - exp(-delta * 12))
		levels[index] = lerpf(levels[index], 0.12 + rpm * 0.70, 1.0 - exp(-delta * 18)) if audible else 0.0
		motors[index].pitch_scale = pitches[index]
		motors[index].volume_db = linear_to_db(levels[index]) + ROTOR_GAIN_DB if audible else -80.0

func play_shutter() -> void:
	shutter.play()

func _make_cue(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Effects" if AudioServer.get_bus_index("Effects") >= 0 else "Master"
	player.volume_db = -7
	add_child(player)
	return player

func play_race_gate() -> void:
	if DisplayServer.get_name() != "headless":
		gate_chime.play()

func play_race_finish() -> void:
	if DisplayServer.get_name() != "headless":
		finish_chime.play()

func play_balloon(point: Vector3) -> void:
	var pop := pops[next_pop]
	next_pop = (next_pop + 1) % pops.size()
	pop.global_position = point
	if DisplayServer.get_name() != "headless":
		pop.play()

static func _pcm(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size():
		bytes.encode_s16(index * 2, int(clampf(samples[index], -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream

static func rotor_stream(seed_value: int = 30491) -> AudioStreamWAV:
	# Do not integrate independent random RPM into the four loop phases: those
	# phases periodically converge, producing a repeating beat/tick as pitch rises.
	# Thrust still controls native playback RPM. Bounded phase texture and an
	# eight-second circular airflow bed keep the blade buzz without that drift beat.
	var samples := PackedFloat32Array()
	samples.resize(SAMPLE_RATE * 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := PackedFloat32Array()
	noise.resize(samples.size())
	for index in samples.size():
		noise[index] = rng.randf_range(-1, 1)
	var low_alpha := 1.0 - exp(-TAU * 900 / SAMPLE_RATE)
	var dc_alpha := 1.0 - exp(-TAU * 150 / SAMPLE_RATE)
	var dc := 0.0
	var low := 0.0
	var smooth := 0.0
	var body := 0.0
	var air := 0.0
	var drift := 0.0
	var drift_alpha := 1.0 - exp(-TAU * 18 / SAMPLE_RATE)
	var deviations := PackedFloat32Array()
	deviations.resize(samples.size())
	var peak := 0.0
	for pass_index in 2:
		for index in samples.size():
			dc += dc_alpha * (noise[index] - dc)
			low += low_alpha * (noise[index] - dc - low)
			smooth += low_alpha * (low - smooth)
			body += low_alpha * (smooth - body)
			air += low_alpha * (body - air)
			drift += drift_alpha * (noise[index] - drift)
			if pass_index == 0:
				continue
			deviations[index] = drift
			samples[index] = air * 1.25
	for index in samples.size():
		var phase := PI / 2.0 + TAU * ROTOR_BASE_HZ * index / SAMPLE_RATE + deviations[index] * 28.0
		var blades := sin(phase) * 0.18 + sin(phase * 2) * 0.14 + sin(phase * 3) * 0.07 + sin(phase * 4) * 0.025
		samples[index] += blades
		peak = maxf(peak, absf(samples[index]))
	for index in samples.size():
		samples[index] *= 0.70 / maxf(peak, 0.001)
	return _pcm(samples, true)

static func race_stream(finished: bool) -> AudioStreamWAV:
	var duration := 0.58 if finished else 0.13
	var samples := PackedFloat32Array()
	samples.resize(roundi(SAMPLE_RATE * duration))
	var notes := [784.0, 988.0, 1175.0, 1568.0]
	for index in samples.size():
		var time := float(index) / SAMPLE_RATE
		var slot := mini(3, int(time / 0.12)) if finished else 0
		var age := time - slot * 0.12
		var length := (0.22 if slot == 3 else 0.12) if finished else duration
		var envelope := minf(1, age / 0.008) * minf(1, maxf(0, length - age) / 0.035)
		var frequency: float = notes[slot] if finished else 740.0
		var phase := TAU * frequency * age
		samples[index] = (sin(phase) * 0.48 + sin(phase * 2) * 0.07) * envelope
	return _pcm(samples, false)

static func balloon_stream() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(SAMPLE_RATE * 0.16))
	var rng := RandomNumberGenerator.new()
	rng.seed = 72913
	var low := 0.0
	for index in samples.size():
		var time := float(index) / SAMPLE_RATE
		low = lerpf(low, rng.randf_range(-1, 1), 0.55)
		var envelope := minf(1, time / 0.001) * exp(-time * 42) * minf(1, (0.16 - time) / 0.02)
		samples[index] = (low * 0.8 + sin(TAU * (140 * time - 240 * time * time)) * 0.25) * envelope
	return _pcm(samples, false)

static func shutter_stream() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(SAMPLE_RATE * 0.16))
	var rng := RandomNumberGenerator.new()
	rng.seed = 17371
	var previous := 0.0
	for index in samples.size():
		var t := float(index) / SAMPLE_RATE
		var noise := rng.randf_range(-1, 1)
		var high := noise - previous
		previous = noise
		var attack := minf(1, t / 0.0008)
		var click := (high * 0.26 + sin(TAU * 1700 * t) * 0.18) * exp(-t * 140) * attack
		var closing := maxf(0, t - 0.047)
		var second := (high * 0.17 + sin(TAU * 950 * closing) * 0.12) * exp(-closing * 95) * minf(1, closing / 0.001) if t > 0.047 else 0.0
		samples[index] = (click + second) * minf(1, (0.16 - t) / 0.01)
	return _pcm(samples, false)
