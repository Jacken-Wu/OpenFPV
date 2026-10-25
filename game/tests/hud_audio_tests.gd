extends SceneTree
## Scoped regression for rotor texture and compact bottom-bar telemetry.
class VirtualInput extends FlightInput:
	func radio_connected() -> bool:
		return true
	func radio_axis(index: int) -> float:
		return [0.6, -0.3, 0.2, -0.4][index] if index < 4 else 0.0
	func radio_buttons() -> Array[bool]:
		var values: Array[bool] = []
		for index in JOY_BUTTON_MAX:
			values.append(index % 2 == 0)
		return values
class TestGame extends "res://scripts/main.gd":
	func _create_flight_input() -> FlightInput:
		return VirtualInput.new()
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/hud-audio"
var game: TestGame
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1
func frames(count: int = 8) -> void:
	for index in count:
		await process_frame
func profile(count: int) -> Dictionary:
	var value := {"guid": "preview-test", "name": "操作预览测试", "axes": {}, "auxiliary": []}
	for index in 4:
		value.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": 0.0, "invert": false}
	for index in count:
		value.auxiliary.append({"id": "switch%d" % index, "name": "开关%02d" % (index + 1), "source": "buttons", "buttons": [index], "invert": false, "type": "momentary"})
	return value
func capture_and_grid(name_text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	print("HUD_LAYOUT window=%s capture=%s logical=%s" % [DisplayServer.window_get_size(), image.get_size(), root.get_visible_rect().size])
	check(image.save_png(directory.path_join(name_text + ".png")) == OK, "capture " + name_text)
	var sticks := game.input_display.sticks
	var scale_factor := Vector2(image.get_size()) / root.get_visible_rect().size
	for index in 2:
		for axis in 2:
			# Probe well clear of the stick dot and square borders, in final pixels.
			var local := Vector2(38 + index * 76, 28) + (Vector2(0, 14) if axis == 0 else Vector2(14, 0))
			var point := Vector2i((sticks.get_global_transform_with_canvas() * local) * scale_factor)
			var brightness := 0.0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var pixel := image.get_pixelv(point + Vector2i(dx, dy))
					brightness = maxf(brightness, pixel.g)
			check(brightness > 0.45, "%s stick%d %s grid visible after window scaling" % [name_text, index, "vertical" if axis == 0 else "horizontal"])
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var rotor := FlightAudio.rotor_stream()
	var samples := PackedFloat32Array()
	var energy := 0.0
	var peak := 0.0
	var step_energy := 0.0
	for index in rotor.data.size() / 2:
		var value := rotor.data.decode_s16(index * 2) / 32768.0
		samples.append(value)
		energy += value * value
		peak = maxf(peak, absf(value))
		if index > 0:
			step_energy += pow(value - samples[index - 1], 2)
	var rms := sqrt(energy / samples.size())
	var seam := absf(samples[0] - samples[-1])
	check(rotor.loop_mode == AudioStreamWAV.LOOP_FORWARD and rotor.get_length() == 8 and peak > 0.6 and peak < 0.71, "eight-second rotor loop has headroom and no clipping")
	check(seam < 0.04 and seam < sqrt(step_energy / (samples.size() - 1)) * 3, "circular filter state prevents an outlier click at the loop boundary")
	var maximum_tone_share := 0.0
	for frequency in [150, 200, 300, 400, 450, 600, 750, 800, 900, 130, 260, 390, 520]:
		var real_sum := 0.0
		var imag_sum := 0.0
		for index in samples.size():
			real_sum += samples[index] * cos(TAU * frequency * index / rotor.mix_rate)
			imag_sum += samples[index] * sin(TAU * frequency * index / rotor.mix_rate)
		var amplitude := 2.0 * Vector2(real_sum, imag_sum).length() / samples.size()
		maximum_tone_share = maxf(maximum_tone_share, amplitude * amplitude / (2 * rms * rms))
	check(maximum_tone_share < 0.20, "voiced blade harmonics avoid a single dominant stationary tone")
	check(rotor.save_to_wav(directory.path_join("rotor-base.wav")) == OK, "export rotor for spectral and listening review")
	game = TestGame.new()
	root.add_child(game)
	await game._wait_for_world()
	game.flight_audio.set_process(false)
	game.drone.freeze = false
	game.drone.motor_forces.fill(float(game.drone.spec.max_thrust))
	game.flight_audio._process(0.01)
	check(game.flight_audio.levels[0] > 0 and game.flight_audio.levels[0] < 0.2, "short thrust changes ramp gain instead of imposing frame-rate amplitude steps")
	game.flight_audio._process(1)
	check(is_equal_approx(game.flight_audio.pitches[0], 2.4) and is_equal_approx(game.flight_audio.pitches[0], game.flight_audio.pitches[3]), "full throttle pitch capped at 2.4 without artificial motor detuning")
	if DisplayServer.get_name() != "headless":
		# Keep the actual four native players at full throttle for a short playback.
		await frames(40)
		check(game.flight_audio.motors.all(func(player: AudioStreamPlayer): return player.playing and player.get_playback_position() > 0), "four native full-throttle voices advance without restarting the loop")
	game.drone.freeze = false
	game.drone.motor_forces = PackedFloat32Array([0.1, 1, 2, 3.9])
	game.flight_audio._process(1)
	check(game.flight_audio.pitches[0] < game.flight_audio.pitches[1] and game.flight_audio.pitches[1] < game.flight_audio.pitches[2] and game.flight_audio.pitches[2] < game.flight_audio.pitches[3], "real differential thrust still controls four motor voices")
	game.drone.altitude_cutoff = true
	game.flight_audio._process(0.001)
	check(game.flight_audio.levels == PackedFloat32Array([0, 0, 0, 0]), "altitude cutoff still mutes immediately")
	game.drone.altitude_cutoff = false
	game.drone.freeze = true
	game.flight_audio._process(0.001)
	check(game.flight_audio.levels == PackedFloat32Array([0, 0, 0, 0]), "pause still mutes immediately")
	game.flight_audio.set_process(true)
	var settings: Dictionary = game.store.data.settings.duplicate(true)
	settings.input_display = {"sticks": true, "switches": true, "mode": 2}
	check(game.store.save_settings(settings).ok, "scoped UI fixture persists preview preferences in an isolated test save")
	game.flight_input.set_process(false)
	game.flight_input.using_radio = true
	game.radio_required = false
	for window_size in [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(960, 600)]:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_size(window_size)
			await frames(4)
		for count in [8, 16, 24]:
			game.flight_input.profile = profile(count)
			await frames(14)
			var preview := game.input_display
			var bar_rect := game.bottom_bar.get_global_rect()
			check(preview.is_visible_in_tree() and preview.aux_labels.size() == count and preview.aux_list.columns >= 2, "%s %d auxiliaries use multiple columns" % [window_size, count])
			var all_visible := true
			for label: Label in preview.aux_labels.values():
				all_visible = all_visible and label.is_visible_in_tree() and preview.get_global_rect().encloses(label.get_global_rect()) and not label.text.contains("未连接")
			check(all_visible and preview.find_children("*", "ScrollContainer", true, false).is_empty(), "%s all %d auxiliary states fit without scrolling" % [window_size, count])
			check(bar_rect.encloses(preview.get_global_rect()) and root.get_visible_rect().encloses(bar_rect) and preview.position.x > game.prompt.get_parent().position.x + game.prompt.get_parent().size.x, "%s compact preview sits beside status inside bottom bar" % window_size)
			check(game.bottom_bar.size.y < 195, "%s bottom bar stays below 195 logical pixels with %d switches" % [window_size, count])
			if count == 16:
				await capture_and_grid("bottom-%dx%d" % [window_size.x, window_size.y])
	check(game.hud_shortcuts.text.contains("R 重置到传送点") and game.hud_shortcuts.text.contains("E 交互") and not game.hud_shortcuts.text.contains("F3") and not game.prompt.text.contains("F3"), "bottom shortcuts carry corrected R/E labels and omit F3")
	for configuration in [{"sticks": true, "switches": false, "mode": 1}, {"sticks": false, "switches": true, "mode": 2}, {"sticks": false, "switches": false, "mode": 2}]:
		game.store.data.settings.input_display = configuration
		await frames()
		check(game.input_display.visible == (configuration.sticks or configuration.switches) and game.input_display.sticks.visible == configuration.sticks and (not game.input_display.visible or game.input_display.aux_list.visible == configuration.switches), "independent preview switches collapse unused content " + str(configuration))
	game.store.data.settings.input_display = {"sticks": true, "switches": true, "mode": 2}
	await frames()
	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	game._unhandled_key_input(f3)
	check(game.menu is RegionMap and not game.input_display.visible, "F3 still opens unified map and hides the bottom preview")
	game._close_menu()
	await frames()
	check(game.input_display.visible, "closing the menu restores compact preview")
	game.queue_free()
	await frames()
	print("HUD_AUDIO_RESULT failures=%d checks=%d tone_share=%.5f seam=%.5f" % [failed, checked, maximum_tone_share, seam])
	quit(1 if failed > 0 else 0)
