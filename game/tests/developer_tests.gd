extends SceneTree
class TestGame extends "res://scripts/main.gd":
	var fail_photo := false
	var exposure: Image
	func _save_capture(image: Image, path: String, metadata: Dictionary) -> Dictionary:
		exposure = image.duplicate()
		return {"ok": false, "message": "test write failure"} if fail_photo else super(image, path, metadata)
var failed := 0
var checked := 0
var directory := "user://tests/developer"
var game: Node3D

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1

func physics(frames: int) -> void:
	for frame in frames:
		await physics_frame

func key(code: Key, character: int = 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func screenshot(name_value: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)

func pcm_peak(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	for index in stream.data.size() / 2:
		peak = maxf(peak, absf(stream.data.decode_s16(index * 2) / 32768.0))
	return peak

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var drone := FPVDrone.new()
	root.add_child(drone)
	drone.freeze = true
	for pair: Vector2 in [Vector2(280, 0), Vector2(280.01, 0), Vector2(300, 0), Vector2(300.01, 1), Vector2(299, 1), Vector2(280.01, 1), Vector2(280, 0)]:
		drone.update_altitude_protection(pair.x)
		check(drone.altitude_cutoff == bool(pair.y), "altitude hysteresis at %.2fm expects cutoff=%d" % [pair.x, int(pair.y)])
	drone.freeze = false
	drone.reset_drone(Vector3(0, 301, 0))
	await physics(3)
	drone.controls = Vector4(0.7, -0.8, 0.6, 0.9)
	drone.motor_forces.fill(3)
	await physics(3)
	check(drone.altitude_cutoff and is_zero_approx(drone.total_thrust) and drone.motor_forces == PackedFloat32Array([0, 0, 0, 0]), "all four actual motors stop immediately despite lag and full stick torque")
	check(is_equal_approx(drone.controls.w, 0.9) and is_zero_approx(drone.effective_throttle()) and drone.position.y < 301 and drone.linear_velocity.y < 0, "protection preserves commanded throttle while gravity continues")
	drone.controls = Vector4(0, 0, 0, 0.23)
	for frame in 420:
		await physics_frame
		if not drone.altitude_cutoff:
			break
	await physics(3)
	check(drone.position.y <= 280 and not drone.altitude_cutoff and drone.total_thrust > 0 and is_equal_approx(drone.controls.w, 0.23), "natural descent restores the new current throttle rather than pre-cutoff throttle")
	drone.world_origin_offset = Vector3(2048, 320, -2048)
	drone.reset_drone(Vector3(0, -19, 0))
	await physics(3)
	check(drone.altitude_cutoff, "world height300m survives vertical floating-origin offsets")
	drone.reset_attitude()
	await physics(3)
	check(drone.altitude_cutoff, "attitude reset cannot bypass protection above300m")
	drone.reset_drone(Vector3(0, -41, 0))
	await physics(3)
	check(not drone.altitude_cutoff, "world height279m restores protection after origin shift")
	var audio := FlightAudio.new()
	audio.drone = drone
	root.add_child(audio)
	drone.motor_forces.fill(0.1)
	audio._process(1)
	var low_pitch: float = audio.pitches[0]
	var low_level: float = audio.levels[0]
	drone.motor_forces.fill(3.5)
	audio._process(1)
	check(audio.pitches[0] > low_pitch * 2 and audio.levels[0] > low_level * 2, "more actual throttle raises rotor pitch and volume")
	drone.motor_forces = PackedFloat32Array([0.1, 1.0, 2.0, 3.9])
	audio._process(1)
	check(audio.pitches[0] < audio.pitches[1] and audio.pitches[1] < audio.pitches[2] and audio.pitches[2] < audio.pitches[3], "stick-driven differential motor forces produce four distinct rotor voices")
	drone.altitude_cutoff = true
	audio._process(1)
	check(audio.levels == PackedFloat32Array([0, 0, 0, 0]), "altitude cutoff immediately mutes all powered rotor voices")
	drone.altitude_cutoff = false
	drone.freeze = true
	audio._process(1)
	check(audio.levels == PackedFloat32Array([0, 0, 0, 0]), "paused simulation mutes rotor audio")
	var rotor := FlightAudio.rotor_stream()
	var shutter := FlightAudio.shutter_stream()
	check(rotor.loop_mode == AudioStreamWAV.LOOP_FORWARD and rotor.mix_rate == 22050 and rotor.get_length() > 0.39 and pcm_peak(rotor) > 0.2 and pcm_peak(rotor) < 0.9, "generated looping rotor PCM is non-silent and has headroom")
	check(absf(rotor.data.decode_s16(0) - rotor.data.decode_s16(rotor.data.size() - 2)) < 2000, "loop seam avoids a large discontinuity")
	check(shutter.loop_mode == AudioStreamWAV.LOOP_DISABLED and shutter.get_length() < 0.2 and pcm_peak(shutter) > 0.1 and pcm_peak(shutter) < 0.95 and abs(shutter.data.decode_s16(shutter.data.size() - 2)) < 10, "generated shutter has a short one-shot envelope without clipping or tail pop")
	check(rotor.save_to_wav(directory.path_join("rotor-base.wav")) == OK and shutter.save_to_wav(directory.path_join("shutter.wav")) == OK, "generated audio previews export successfully")
	audio.queue_free()
	drone.queue_free()
	await process_frame
	game = TestGame.new()
	root.add_child(game)
	await game._wait_for_world()
	var commands: DeveloperCommands = game.developer_commands
	check(commands.execute("/help").contains("/location") and commands.execute("/seed").contains(str(game.store.data.seed)) and commands.execute("/pos").contains("世界坐标"), "developer help, seed and global coordinates are available")
	check(commands.execute("/invalid").contains("未知") and commands.execute("/tp nan 0 0").contains("有限") and commands.execute("/tp 1e39 0 0").contains("有限") and commands.execute("/tp 0 0").contains("用法"), "malformed and non-finite developer commands are rejected")
	check(commands.execute("/tp location").contains("请先") and commands.execute("/location missing").contains("找不到"), "missing or invalid locator targets do not reuse stale coordinates")
	var locator := BiomeLocator.new(game.store.regions)
	check(locator.choices().size() == game.catalog.biomes.size() and commands.execute("/location list").contains("base.biome.pine_valley"), "all data-defined biomes can be listed and selected")
	var before := JSON.stringify(game.store.data)
	for choice in locator.choices():
		var at := Vector3(-1432, 20, 2121)
		var found := locator.locate(choice.biome.id, at)
		check(found.ok and game.store.regions.plan(found.kind, found.key).stations[0].point == found.point, "locator returns a real generated platform for " + choice.name)
		var best := INF
		var field: BiomeField = game.store.regions.field
		var spacing := float(field.rules[choice.kind + "_spacing"])
		var center := Vector2i(floori(at.x / spacing), floori(at.z / spacing))
		# Independent broad enumeration catches first-hit/ring-order mistakes.
		for x in range(center.x - 5, center.x + 6):
			for z in range(center.y - 5, center.y + 6):
				var site := field.surface_site(Vector2i(x, z)) if choice.kind == "surface" else field.volume_site(choice.kind, Vector2i(x, z))
				if site.is_empty() or (choice.kind == "surface" and not String(site.biome.id).begins_with(String(choice.biome.id) + ":")):
					continue
				var anchor: Vector2 = site.anchor if choice.kind == "surface" else site.pos
				best = minf(best, anchor.distance_to(Vector2(at.x, at.z)))
		check(is_equal_approx(found.distance, best), "locator chooses nearest center against broad enumeration for " + choice.name)
	check(JSON.stringify(game.store.data) == before, "locating undiscovered biomes never changes exploration, tasks, ownership or portal locks")
	check(locator.resolve("浮岛").kind == "sky" and locator.resolve("maze").kind == "maze" and locator.resolve("pine_valley").biome.id == "base.biome.pine_valley", "console supports Chinese names, fragments and concise English IDs")
	var found := locator.locate("sky", Vector3(20000, 0, -20000))
	var fresh := BiomeLocator.new(BiomeWorld.new(game.catalog, int(game.store.data.seed))).locate("sky", Vector3(20000, 0, -20000))
	check(found.id == fresh.id and found.point.is_equal_approx(fresh.point), "far signed coordinates and cold seed reconstruction locate the same platform")
	game._set_paused(false)
	await key(KEY_SLASH, 47)
	check(game.menu is DeveloperConsole and game.paused and game.menu.entry.has_focus() and game.menu.entry.text == "/", "slash opens a focused console with one slash and pauses flight")
	check(not game.flight_input.actions_enabled, "console suppresses bound radio actions while editing commands")
	var console: DeveloperConsole = game.menu
	await key(KEY_P, 112)
	check(game.menu == console and game.paused and console.entry.text == "/p", "typing flight hotkeys inside console does not trigger flight actions")
	console._submit("/location sky")
	check(console.output.get_parsed_text().contains("平台坐标") and commands.last_location.ok, "submitted console command prints location output")
	var deployment: Array = game.store.data.deployment.duplicate()
	var portals: Dictionary = game.store.data.exploration.portals.duplicate()
	console._submit("/tp location")
	check(game._world_position().distance_to(commands.last_location.point) < 0.1 and game.store.data.deployment == deployment and game.store.data.exploration.portals == portals, "debug teleport reaches locator target without overwriting safe spawn or registering portals")
	if DisplayServer.get_name() != "headless":
		await screenshot("developer-console")
	await key(KEY_ESCAPE)
	check(game.menu == null and not game.paused, "Escape closes console and restores running state")
	game._set_paused(true)
	await key(KEY_SLASH, 47)
	check(game.menu.history.size() >= 2, "command history survives closing and reopening console")
	await key(KEY_UP)
	check(game.menu.entry.text == "/tp location", "up arrow recalls the previous command")
	await key(KEY_ESCAPE)
	check(game.menu == null and game.paused, "console opened from deliberate pause closes back to pause")
	var effects: FlightEffects = game.flight_effects
	effects.update_warning(290, false, true)
	effects.phase = 0.1
	var first := effects.edge_opacity()
	effects.phase = 0.4
	check(effects.severity == 1 and not is_equal_approx(first, effects.edge_opacity()) and effects.warning.text.contains("接近"), "280-300m produces flashing red edges and approach text")
	if DisplayServer.get_name() != "headless":
		game.set_process(false)
		await screenshot("altitude-warning")
	effects.update_warning(285, true, true)
	effects.phase = 0.1
	first = effects.edge_opacity()
	effects.phase = 0.4
	check(effects.severity == 2 and first == effects.edge_opacity() and effects.warning.text.contains("动力已关闭"), "latched cutoff keeps steady red warning while descending through285m")
	if DisplayServer.get_name() != "headless":
		await screenshot("altitude-cutoff")
	effects.update_warning(280, false, true)
	check(effects.severity == 0 and effects.warning.text.is_empty(), "warning clears at280m recovery")
	game.set_process(true)
	commands.execute("/volume 0")
	check(AudioServer.get_bus_volume_db(0) <= -79, "developer volume command can mute audio")
	check(commands.execute("/volume 101").contains("0~100") and commands.execute("/volume bad").contains("用法"), "volume command rejects invalid values")
	commands.execute("/volume 100")
	if DisplayServer.get_name() != "headless":
		check(game.flight_audio.motors.all(func(player: AudioStreamPlayer): return player.playing), "all four native audio voices are running in the normal window")
		# Return to a safe platform, preserve pause, and verify real exposure/feedback.
		game._deploy(Vector3(deployment[0], deployment[1], deployment[2]))
		await game._wait_for_world()
		var count: int = effects.shutter_count
		game._capture()
		for frame in 120:
			await process_frame
			if effects.shutter_count > count:
				break
		check(effects.flash > 0 and effects.shutter_count == count + 1 and game.flight_audio.shutter.playing, "successful photo produces a visible flash and plays generated shutter audio")
		game._capture()
		await screenshot("photo-flash")
		check(root.get_texture().get_image().get_pixel(5, 5).r > game.exposure.get_pixel(5, 5).r + 0.05, "saved exposure stays clean while the displayed frame receives white flash")
		await create_timer(0.3).timeout
		check(effects.flash == 0 and not game.screenshot_busy and effects.shutter_count == count + 1, "photo feedback fades and repeated capture during exposure is deduplicated")
		game.fail_photo = true
		await game._capture()
		check(effects.shutter_count == count + 1 and game.last_notice == "test write failure", "failed photo save never displays false successful shutter feedback")
	game.queue_free()
	await process_frame
	print("DEVELOPER_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
