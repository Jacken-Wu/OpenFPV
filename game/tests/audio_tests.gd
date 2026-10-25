extends SceneTree
class VirtualRadio extends RadioCalibration:
	func _refresh_devices() -> void:
		devices = [99]
		device_select.add_item("测试遥控器")
		_select_device(0)
	func _connected() -> bool:
		return true
	func _read_axes() -> Array[float]:
		return [0.02, -0.02, 0.01, -0.98, 0.01]
	func _read_buttons() -> Array[bool]:
		return [false]
	func _device_guid() -> String:
		return "test"
	func _device_name() -> String:
		return "测试遥控器"

var failed := 0
var checked := 0
var game: Node3D
var directory := "res://../.local/test-results/audio"

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var axis := {"axis": 0, "min": -0.8, "max": 0.9, "center": 0.1, "invert": false, "deadzone": 0.1}
	check(FlightInput.normalize_axis(0.15, axis, false) == 0 and FlightInput.normalize_axis(0.05, axis, false) == 0, "asymmetric stick drift inside individual deadzone is zero")
	check(is_equal_approx(FlightInput.normalize_axis(0.54, axis, false), 0.5) and FlightInput.normalize_axis(0.9, axis, false) == 1 and FlightInput.normalize_axis(-0.8, axis, false) == -1, "deadzone remaps continuously with both full-travel endpoints preserved")
	check(FlightInput.normalize_axis(-0.75, axis, true) == 0 and FlightInput.normalize_axis(0.9, axis, true) == 1, "throttle drift is removed at idle while full throttle remains available")
	axis.invert = true
	check(FlightInput.normalize_axis(0.85, axis, true) == 0 and FlightInput.normalize_axis(-0.8, axis, true) == 1, "reversed throttle deadzone follows actual idle endpoint")
	axis.erase("deadzone")
	check(FlightInput.normalize_axis(0.895, axis, true) > 0, "legacy throttle missing deadzone keeps its prior response")
	var profile := {"guid": "test", "name": "Deadzone", "axes": {}, "auxiliary": [{"id": "aux", "name": "旋钮", "source": "axis", "axis": 4, "min": -1.0, "max": 1.0, "invert": false, "type": "analog", "deadzone": 0.08}]}
	for index in 4:
		profile.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": 0.0, "invert": false, "deadzone": 0.04 + index * 0.01}
	check(FlightInput.valid_profile(profile) and FlightInput.valid_profile(JSON.parse_string(JSON.stringify(profile))), "every axis deadzone persists through profile JSON")
	check(is_equal_approx(FlightInput.auxiliary_value(profile.auxiliary[0], 0.03), 0.5) and FlightInput.auxiliary_value(profile.auxiliary[0], 1.0) == 1, "analogue auxiliary drift stabilizes centre while preserving endpoints")
	for invalid: Variant in [-0.01, 0.21, INF, NAN, "bad"]:
		var copy := profile.duplicate(true)
		copy.axes.roll.deadzone = invalid
		check(not FlightInput.valid_profile(copy), "invalid flight deadzone rejected " + str(invalid))
		copy = profile.duplicate(true)
		copy.auxiliary[0].deadzone = invalid
		check(not FlightInput.valid_profile(copy), "invalid auxiliary deadzone rejected " + str(invalid))
	var radio := VirtualRadio.new()
	radio.initial_profile = profile
	var host := CenterContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	host.add_child(radio)
	var field: SpinBox = radio.axis_rows.get_child(0).find_children("*", "SpinBox", true, false)[0]
	field.value = 7
	check(is_equal_approx(radio.mapping.roll.deadzone, 0.07) and is_equal_approx(profile.axes.roll.deadzone, 0.04), "deadzone UI edits a profile draft without changing shared input")
	field.get_line_edit().grab_focus()
	field.get_line_edit().text = "8.5"
	radio._accept()
	check(is_equal_approx(radio.mapping.roll.deadzone, 0.085), "saving commits a typed deadzone before collecting the profile")
	await capture("radio-deadzones")
	var capture_radio := RadioCapture.new()
	capture_radio.begin([-1.0, -1.0, -1.0, -1.0])
	capture_radio.sample([1.0, 1.0, 1.0, 1.0])
	var recaptured := capture_radio.stick_mapping([0.0, 0.0, 0.0, -1.0], radio.mapping)
	check(is_equal_approx(recaptured.roll.deadzone, 0.085) and is_equal_approx(recaptured.throttle.deadzone, 0.07), "recalibration preserves per-role deadzones")
	host.queue_free()
	await process_frame
	var catalog := ContentCatalog.new()
	var paths: Dictionary = {}
	for biome in catalog.biomes:
		var stream := biome.music as AudioStreamWAV
		check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.get_length() >= 30 and stream.get_length() <= 50 and not biome.music_title.is_empty(), "original looping theme assigned for " + biome.display_name)
		paths[stream.resource_path] = true
	check(paths.size() == catalog.biomes.size() and catalog.errors.is_empty(), "every biome has its own distinct validated music resource")
	check(catalog.fingerprint() == ContentCatalog.new().fingerprint(), "audio-inclusive fingerprint is stable across catalog loads")
	var rotor := FlightAudio.rotor_stream()
	var maximum_tone_share := 0.0
	var energy := 0.0
	for index in rotor.data.size() / 2:
		energy += pow(rotor.data.decode_s16(index * 2) / 32768.0, 2)
	for frequency in [150, 200, 300, 400, 450, 600, 750, 800, 900, 130, 260, 390, 520]:
		var real_sum := 0.0
		var imag_sum := 0.0
		for index in rotor.data.size() / 2:
			var sample := rotor.data.decode_s16(index * 2) / 32768.0
			real_sum += sample * cos(TAU * frequency * index / rotor.mix_rate)
			imag_sum += sample * sin(TAU * frequency * index / rotor.mix_rate)
		var amplitude := 2.0 * Vector2(real_sum, imag_sum).length() / (rotor.data.size() / 2)
		maximum_tone_share = maxf(maximum_tone_share, amplitude * amplitude / (2 * energy / (rotor.data.size() / 2)))
	check(maximum_tone_share < 0.20, "voiced blade harmonics avoid a single dominant stationary tone")
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._show_pause_menu()
	check(game.menu is PauseMenu and game.menu.find_children("*", "Button", true, false).any(func(button: Button): return button.text == "声音设置"), "production Esc menu exposes audio settings")
	game._show_audio_menu()
	var panel: AudioMenu = game.menu
	var original: Dictionary = game.audio_mixer.settings.duplicate(true)
	panel.fields.motors.value = 23
	panel.fields.music.value = 61
	check(is_equal_approx(game.audio_mixer.settings.motors, 0.23) and is_equal_approx(game.audio_mixer.settings.music, 0.61) and not game.store.data.settings.has("audio"), "volume preview updates separate buses without persisting")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Motors")) == "Effects" and game.flight_audio.motors[0].bus == "Motors" and game.flight_audio.shutter.bus == "Shutter", "actual motor and shutter players route through independent effects buses")
	panel.fields.master.value = 0
	check(AudioServer.is_bus_mute(0), "zero master volume genuinely mutes all output")
	panel.fields.master.value = 80
	panel.fields.effects.value = 0
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "effects mute leaves music independently audible")
	panel.draft.output_device = "Unavailable test output"
	panel.refresh_devices()
	check(game.audio_mixer.actual_device == "Default" and panel.feedback.text.contains("不可用") and game.audio_mixer.settings.output_device == "Unavailable test output", "missing output device falls back without discarding saved preference")
	var available: PackedStringArray = game.audio_mixer.output_devices()
	if not available.is_empty():
		panel.device_select.select(panel.devices.find(available[0]))
		panel.device_select.item_selected.emit(panel.devices.find(available[0]))
		check(game.audio_mixer.actual_device == available[0], "output dropdown selects a real enumerated device")
	await capture("audio-settings")
	game._close_menu()
	check(game.audio_mixer.settings == original, "Esc cancels all preview volume and output changes")
	game._show_audio_menu()
	panel = game.menu
	panel.fields.motors.value = 35
	panel.fields.music.value = 42
	game.store.writable = false
	panel.submit()
	check(game.menu == panel and not game.store.data.settings.has("audio"), "failed audio save leaves the menu open and stored settings intact")
	game.store.writable = true
	panel.submit()
	check(game.menu is PauseMenu and is_equal_approx(game.store.data.settings.audio.motors, 0.35), "successful audio save commits preferences then returns to pause menu")
	var restart := ProgressStore.new(game.catalog, game.store.path)
	check(is_equal_approx(GameAudioSettings.from_settings(restart.data.settings).music, 0.42), "audio settings survive restart")
	var invalid: Dictionary = game.store.data.settings.duplicate(true)
	invalid.audio.music = NAN
	check(not game.store.save_settings(invalid).ok and not game.store.save_loadout(game.store.data.build, invalid).ok, "non-finite audio settings cannot enter either settings transaction")
	var next: Dictionary = game.save_library.new_world(game.store, "Audio world", 42)
	check(next.ok and next.store.data.settings.audio == game.store.data.settings.audio, "audio preferences follow player across new world creation")
	var music: BiomeMusic = game.biome_music
	game.set_process(false)
	music.set_process(false)
	var first := catalog.biomes[0]
	var second := catalog.biomes[1]
	music.transition(first.music, first.music_title)
	music._process(2)
	music.transition(second.music, second.music_title)
	music._process(1)
	check(music.gains.x > 0.2 and music.gains.y > 0.2 and is_equal_approx(music.gains.length_squared(), 1), "biome changes use equal-power crossfade with both tracks audible")
	if DisplayServer.get_name() != "headless":
		check(music.players.all(func(player: AudioStreamPlayer): return player.playing), "both native music players actually play during windowed crossfade")
	for biome in catalog.biomes:
		music.transition(biome.music, biome.music_title)
		music._process(2)
		check(music.players.size() == 2 and music.players.count(null) == 0 and music.players.filter(func(player: AudioStreamPlayer): return player.stream != null).size() == 1 and music.target_stream == biome.music, "bounded native playback switches to " + biome.music_title)
	var previous_stream: AudioStream = music.target_stream
	music.observe(first, 0.1)
	music.observe(second, 0.1)
	check(music.target_stream == previous_stream, "brief biome border jitter does not restart music")
	music.observe(second, 0.7)
	check(music.target_stream == second.music, "stable biome entry selects its assigned theme")
	if DisplayServer.get_name() != "headless":
		music._process(2)
		var active: AudioStreamPlayer
		for player in music.players:
			if player.stream == second.music:
				active = player
		active.play(second.music.get_length() - 0.1)
		await create_timer(0.4).timeout
		check(active.playing and active.get_playback_position() < 1, "native music playback wraps through the WAV loop boundary")
	game.queue_free()
	await process_frame
	print("AUDIO_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
