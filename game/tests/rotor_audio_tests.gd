extends SceneTree
## Audio-only regression; no world generation, flying or HUD layout traversal.
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/rotor-audio"
var capture: AudioEffectCapture
var mixer: GameAudioMixer
var audio: FlightAudio
var drone: FPVDrone
var music: BiomeMusic
var report: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func stats(values: PackedVector2Array) -> Dictionary:
	var peak := 0.0
	var energy := 0.0
	for value in values:
		peak = maxf(peak, maxf(absf(value.x), absf(value.y)))
		energy += value.length_squared()
	return {"peak": peak, "rms": sqrt(energy / maxf(1, values.size() * 2)), "frames": values.size()}

func envelope(values: PackedVector2Array) -> Dictionary:
	var width := roundi(AudioServer.get_mix_rate() * 0.02)
	var levels := PackedFloat32Array()
	for block in values.size() / width:
		var energy := 0.0
		for index in range(block * width, (block + 1) * width):
			energy += values[index].length_squared()
		levels.append(sqrt(energy / (width * 2)))
	var lag := (2.0 / 2.4) / 0.02
	var count := levels.size() - ceili(lag)
	var a := 0.0
	var b := 0.0
	var aa := 0.0
	var bb := 0.0
	var ab := 0.0
	for index in count:
		var x := levels[index]
		var y := lerpf(levels[index + floori(lag)], levels[index + ceili(lag)], fmod(lag, 1))
		a += x
		b += y
		aa += x * x
		bb += y * y
		ab += x * y
	var correlation := (ab - a * b / count) / maxf(0.0000001, sqrt(maxf(0, (aa - a * a / count) * (bb - b * b / count))))
	levels.sort()
	return {"p05": levels[int(levels.size() * 0.05)], "p95": levels[int(levels.size() * 0.95)], "ratio": levels[int(levels.size() * 0.95)] / maxf(0.0001, levels[int(levels.size() * 0.05)]), "old_cadence_correlation": correlation}

func record(seconds: float, settle: float = 0.15) -> PackedVector2Array:
	# Let parameter changes leave the server's output buffers before measuring.
	if settle > 0:
		await create_timer(settle).timeout
	capture.clear_buffer()
	await create_timer(seconds).timeout
	return capture.get_buffer(capture.get_frames_available())

func save_wave(name_text: String, values: PackedVector2Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(values.size() * 4)
	for index in values.size():
		bytes.encode_s16(index * 4, int(clampf(values[index].x, -1, 1) * 32767))
		bytes.encode_s16(index * 4 + 2, int(clampf(values[index].y, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.stereo = true
	stream.mix_rate = int(AudioServer.get_mix_rate())
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = bytes
	check(stream.save_to_wav(directory.path_join(name_text + ".wav")) == OK, "save native mix " + name_text)

func limiter_count() -> int:
	var count := 0
	for index in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, index).resource_name == GameAudioMixer.OUTPUT_LIMITER_NAME:
			count += 1
	return count

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var rotor := FlightAudio.rotor_stream()
	var values := PackedFloat32Array()
	var energy := 0.0
	var peak := 0.0
	var difference_energy := 0.0
	for index in rotor.data.size() / 2:
		var value := rotor.data.decode_s16(index * 2) / 32768.0
		values.append(value)
		energy += value * value
		peak = maxf(peak, absf(value))
		if index > 0:
			difference_energy += pow(value - values[index - 1], 2)
	var lag := roundi(rotor.mix_rate / FlightAudio.ROTOR_BASE_HZ)
	var correlation := 0.0
	for index in values.size():
		correlation += values[index] * values[(index + lag) % values.size()]
	correlation /= energy
	var seam := absf(values[0] - values[-1])
	report.waveform = {"peak": peak, "rms": sqrt(energy / values.size()), "one_revolution_correlation": correlation, "loop_seam": seam}
	check(rotor.loop_mode == AudioStreamWAV.LOOP_FORWARD and peak < 0.71 and peak > 0.6, "voiced blade loop has PCM headroom")
	check(correlation > 0.25 and correlation < 0.95, "blade revolutions remain audible alongside irregular airflow")
	check(seam < sqrt(difference_energy / values.size()) * 3, "blade phase and filtered airflow cross the loop boundary without an outlier step")
	check(rotor.data == FlightAudio.rotor_stream().data and rotor.data != FlightAudio.rotor_stream(31278).data, "synthesis is deterministic with distinct motor turbulence")
	check(rotor.save_to_wav(directory.path_join("rotor-base.wav")) == OK, "export voiced rotor PCM")
	mixer = GameAudioMixer.new()
	root.add_child(mixer)
	var maximum := GameAudioSettings.defaults()
	for key: String in GameAudioSettings.LABELS:
		maximum[key] = 1.0
	mixer.apply(maximum)
	check(limiter_count() == 1, "one native output limiter is installed")
	var duplicate := GameAudioMixer.new()
	duplicate.settings = maximum.duplicate(true)
	root.add_child(duplicate)
	check(limiter_count() == 1, "scene recreation does not stack gain stages")
	duplicate.queue_free()
	await process_frame
	var limiter := AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter
	check(limiter != null and limiter.pre_gain_db == 8 and limiter.ceiling_db == -1 and is_zero_approx(AudioServer.get_bus_volume_db(0)), "8dB gain precedes -1dB ceiling; Master remains an ordinary percentage")
	drone = FPVDrone.new()
	drone.spec = {"max_thrust": 4.0}
	drone.freeze = false
	drone.motor_forces.fill(4)
	audio = FlightAudio.new()
	audio.drone = drone
	root.add_child(audio)
	audio.set_process(false)
	audio._process(0.01)
	check(audio.levels[0] > 0 and audio.levels[0] < 0.2, "restored buzz retains smooth gain attack")
	audio._process(1)
	check(is_equal_approx(audio.pitches[0], 2.4) and is_equal_approx(audio.pitches[3], 2.4), "full thrust preserves propeller RPM without shrill upper harmonics")
	check(is_equal_approx(audio.motors[0].volume_db, linear_to_db(0.82) - 12.5), "motor trim preserves output loudness after removing drift beats")
	check(audio.motors[0].stream.data != audio.motors[1].stream.data, "real players use independent motor waveforms")
	drone.altitude_cutoff = true
	audio._process(0.001)
	check(audio.levels == PackedFloat32Array([0, 0, 0, 0]), "altitude cutoff mutes immediately")
	drone.altitude_cutoff = false
	drone.freeze = true
	audio._process(0.001)
	check(audio.levels == PackedFloat32Array([0, 0, 0, 0]), "paused motor sound mutes immediately")
	drone.freeze = false
	audio.set_process(true)
	var catalog := ContentCatalog.new()
	music = BiomeMusic.new()
	root.add_child(music)
	music.set_process(false)
	music.transition(catalog.biomes[0].music)
	music._process(2)
	check(is_equal_approx(music.players[0].volume_db, -6), "full music source gain rises 6dB from previous -12dB trim")
	if DisplayServer.get_name() != "headless":
		capture = AudioEffectCapture.new()
		capture.buffer_length = 10
		AudioServer.add_bus_effect(0, capture)
		maximum.music = 0.0
		maximum.motors = 0.5
		mixer.apply(maximum)
		var half := stats(await record(1.5))
		maximum.motors = 1.0
		mixer.apply(maximum)
		# Eight seconds cross many PCM wraps at maximum RPM, exposing repeat beats
		# that the former 1.5-second loudness capture could not characterize.
		var full_buffer := await record(8)
		var full := stats(full_buffer)
		report.native_half_motor = half
		report.native_full_motor = full
		report.native_full_envelope = envelope(full_buffer)
		check(report.native_full_envelope.ratio < 1.8, "fixed full throttle has no large recurring 20ms loudness pulses across multiple loops")
		check(absf(report.native_full_envelope.old_cadence_correlation) < 0.3, "the former throttle-scaled two-second beat is absent from native full-throttle envelope")
		check(full.frames > AudioServer.get_mix_rate() and full.rms > 0.10 and full.rms < 0.4, "100% motors produce a substantial native output level")
		check(full.rms / half.rms > 1.7 and full.rms / half.rms < 2.3, "motor slider retains useful independent 50-to-100% control")
		save_wave("full-throttle", full_buffer)
		maximum.motors = 0.0
		maximum.music = 1.0
		mixer.apply(maximum)
		var music_level := stats(await record(1.25))
		report.native_music = music_level
		check(music_level.rms > 0.055 and music_level.peak < 0.9, "music maximum is louder with output headroom")
		maximum.motors = 1.0
		mixer.apply(maximum)
		music.players[1].stream = catalog.biomes[1].music
		music.players[1].play()
		for player in music.players:
			player.volume_db = linear_to_db(sqrt(0.5)) + BiomeMusic.MUSIC_GAIN_DB
		audio.play_shutter()
		var combined := stats(await record(1.5, 0))
		report.native_combined = combined
		check(combined.peak <= db_to_linear(-1) + 0.002 and combined.rms > full.rms * 0.8, "maximum motors and music crossfade remain below output ceiling")
		maximum.effects = 0.0
		maximum.music = 0.0
		mixer.apply(maximum)
		audio.play_shutter()
		check(stats(await record(0.25)).peak < 0.0001, "effects and music mute remain silent despite output boost")
		maximum.effects = 1.0
		maximum.motors = 0.0
		maximum.shutter = 0.0
		mixer.apply(maximum)
		audio.play_shutter()
		check(stats(await record(0.25)).peak < 0.0001, "individual motor and shutter mutes remain silent")
		# Deliberately exceed full scale to exercise the real limiter, not just its settings.
		var probe_samples := PackedFloat32Array()
		probe_samples.resize(FlightAudio.SAMPLE_RATE)
		for index in probe_samples.size():
			probe_samples[index] = sin(TAU * 440 * index / FlightAudio.SAMPLE_RATE) * 0.95
		var overload := AudioStreamPlayer.new()
		overload.stream = FlightAudio._pcm(probe_samples, true)
		root.add_child(overload)
		overload.play()
		var protected := stats(await record(0.5))
		report.native_overload_probe = protected
		check(protected.peak <= db_to_linear(-1) + 0.002 and protected.rms > 0.4, "real boosted over-range signal is limited below -1dBFS")
		overload.stop()
		overload.queue_free()
		maximum.master = 0.0
		mixer.apply(maximum)
		check(AudioServer.is_bus_mute(0), "master 0% still mutes final output")
		maximum.master = 1.0
		maximum.motors = 1.0
		maximum.shutter = 1.0
		mixer.apply(maximum)
		drone.motor_forces.fill(0.04)
		await create_timer(0.3).timeout
		capture.clear_buffer()
		for force in [0.04, 0.16, 0.6, 1.4, 2.4, 4.0, 2.0, 0.4]:
			drone.motor_forces.fill(force)
			await create_timer(0.7).timeout
		var sweep := capture.get_buffer(capture.get_frames_available())
		save_wave("throttle-sweep", sweep)
		check(stats(sweep).peak <= db_to_linear(-1) + 0.002 and capture.get_discarded_frames() == 0, "native throttle sweep records without overload or capture drops")
	# Exercise preview rollback and persistence without opening a world.
	var store := ProgressStore.new(catalog, "user://tests/rotor_audio_%d/progress.json" % Time.get_ticks_usec())
	var baseline := mixer.settings.duplicate(true)
	var panel := AudioMenu.new()
	panel.mixer = mixer
	panel.store = store
	root.add_child(panel)
	panel.fields.master.value = 32
	check(is_equal_approx(mixer.settings.master, 0.32), "live Master preview retains ordinary percentage semantics")
	panel.queue_free()
	await process_frame
	check(mixer.settings == baseline and limiter_count() == 1, "cancel restores preferences without accumulating output gain")
	panel = AudioMenu.new()
	panel.mixer = mixer
	panel.store = store
	root.add_child(panel)
	panel.fields.master.value = 75
	panel.fields.music.value = 60
	panel.submit()
	var restart := ProgressStore.new(catalog, store.path)
	check(is_equal_approx(restart.data.settings.audio.master, 0.75) and is_equal_approx(restart.data.settings.audio.music, 0.6), "volume preferences still save and reload normally")
	panel.queue_free()
	if capture != null:
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	audio.queue_free()
	music.queue_free()
	mixer.queue_free()
	drone.free()
	# Native audio commands are consumed by a separate mix thread.
	await create_timer(0.2).timeout
	audio = null
	music = null
	mixer = null
	capture = null
	report.failures = failed
	report.checks = checked
	var file := FileAccess.open(directory.path_join("metrics.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("ROTOR_AUDIO_RESULT failures=%d checks=%d metrics=%s" % [failed, checked, JSON.stringify(report)])
	quit(1 if failed > 0 else 0)
