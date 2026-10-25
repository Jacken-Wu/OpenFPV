extends SceneTree

class VirtualInput:
	extends FlightInput
	var pressed := false
	func radio_connected() -> bool:
		return true
	func radio_axis(index: int) -> float:
		return -1.0 if index == 3 else 0.0
	func radio_buttons() -> Array[bool]:
		return [pressed]

class VirtualGame:
	extends "res://scripts/main.gd"
	var test_radio := VirtualInput.new()
	func _create_flight_input() -> FlightInput:
		return test_radio

var failed := 0

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func wait_physics(frames: int) -> void:
	for index in frames:
		await physics_frame

func button_named(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := button_named(child, title)
		if found != null:
			return found
	return null

func run() -> void:
	var defaults := FlightTuning.defaults()
	check(FlightTuning.valid(defaults), "default independent axis and environment profile validates")
	var legacy := FlightTuning.from_settings({"rates": 300.0, "expo": 0.3})
	check(legacy.axes.roll.max_rate_dps == 300 and legacy.axes.pitch.max_rate_dps == 300 and legacy.axes.yaw.max_rate_dps == 210 and legacy.axes.yaw.expo == 0.3, "legacy shared rates migrate with the original yaw ratio and expo")
	check(FlightTuning.response(-1, defaults.axes.roll) == -360 and FlightTuning.response(1, defaults.axes.roll) == 360 and FlightTuning.response(0, defaults.axes.roll) == 0, "curve has symmetric endpoints and neutral zero")
	var independent := defaults.duplicate(true)
	independent.axes.roll = {"max_rate_dps": 800.0, "expo": 0.6}
	independent.axes.pitch = {"max_rate_dps": 210.0, "expo": 0.0}
	independent.axes.yaw = {"max_rate_dps": 690.0, "expo": 0.1}
	var target := FPVDrone.target_rates(Vector4(0.5, 0.5, 0.5, 0), independent) * (180.0 / PI)
	check(target.is_equal_approx(Vector3(-105, -319.125, -220)), "controller applies each axis's independent limit and expo with correct body signs")
	check(FlightTuning.from_settings({"flight": independent, "rates": 180}).axes.roll.max_rate_dps == 800, "new profile takes precedence over legacy scalar settings")
	for field: String in ["gravity", "air_drag", "angular_drag", "max_rate_dps", "expo"]:
		var invalid := defaults.duplicate(true)
		if field in ["max_rate_dps", "expo"]:
			invalid.axes.roll[field] = NAN
		else:
			invalid[field] = INF
		check(not FlightTuning.valid(invalid), "non-finite setting rejected: " + field)
	var invalid := defaults.duplicate(true)
	invalid.axes.pitch.expo = 1.1
	check(not FlightTuning.valid(invalid), "out-of-range expo rejected")
	invalid = defaults.duplicate(true)
	invalid.gravity = -1
	check(not FlightTuning.valid(invalid), "negative gravity rejected")
	invalid = defaults.duplicate(true)
	invalid.axes.yaw = "broken"
	check(not FlightTuning.valid(invalid), "malformed per-axis record rejected")
	check(FlightTuning.from_settings({"flight": invalid}) == defaults, "invalid loaded profile falls back to defaults without mutating the source")

	var zero_gravity := FPVDrone.new()
	var high_gravity := FPVDrone.new()
	root.add_child(zero_gravity)
	root.add_child(high_gravity)
	zero_gravity.position = Vector3(-20, 100, 0)
	high_gravity.position = Vector3(20, 100, 0)
	var environment := defaults.duplicate(true)
	environment.gravity = 0.0
	environment.air_drag = 0.0
	environment.angular_drag = 0.0
	zero_gravity.apply_tuning(environment)
	environment.gravity = 12.0
	high_gravity.apply_tuning(environment)
	await wait_physics(30)
	check(absf(zero_gravity.linear_velocity.y) < 0.02 and high_gravity.linear_velocity.y < -2, "gravity setting changes actual rigid-body free fall, including zero gravity")
	environment.gravity = 0.0
	zero_gravity.apply_tuning(environment)
	environment.air_drag = 3.0
	high_gravity.apply_tuning(environment)
	zero_gravity.linear_velocity = Vector3(20, 0, 0)
	high_gravity.linear_velocity = Vector3(20, 0, 0)
	await wait_physics(60)
	check(absf(zero_gravity.linear_velocity.x - 20) < 0.1 and high_gravity.linear_velocity.x < 15, "air resistance multiplier changes real deceleration without altering mass or parts")
	environment.air_drag = 0.0
	environment.axes.yaw.expo = 0.0
	zero_gravity.apply_tuning(environment)
	environment.angular_drag = 5.0
	high_gravity.apply_tuning(environment)
	zero_gravity.angular_velocity = Vector3.UP
	high_gravity.angular_velocity = Vector3.UP
	zero_gravity.controls = Vector4(0, 0, -rad_to_deg(1) / 252.0, 0)
	high_gravity.controls = zero_gravity.controls
	await wait_physics(30)
	check(zero_gravity.angular_velocity.y > high_gravity.angular_velocity.y + 0.01, "rotational resistance affects actual angular motion")
	zero_gravity.queue_free()
	high_gravity.queue_free()
	await process_frame

	var game := VirtualGame.new()
	root.add_child(game)
	await game._wait_for_world()
	game._deploy(Vector3(0, 70, 16))
	await game._wait_for_world()
	game._set_paused(false)
	await create_timer(0.1).timeout
	var velocity := Vector3(12, -3, 4)
	var angular := Vector3(0.7, -0.2, 0.9)
	game.drone.linear_velocity = velocity
	game.drone.angular_velocity = angular
	game._set_paused(true)
	await wait_physics(2)
	var position_before: Vector3 = game.drone.position
	await create_timer(0.15).timeout
	check(game.drone.position.is_equal_approx(position_before) and game.drone.motion_velocity().is_equal_approx(velocity) and game.telemetry.text.contains("46.8 km/h"), "pause freezes position while retaining velocity and displaying its saved speed")
	game._set_paused(true)
	game._show_help()
	game._close_menu()
	check(game.drone.paused_linear_velocity.is_equal_approx(velocity) and game.drone.paused_angular_velocity.is_equal_approx(angular), "nested menus and repeated pause do not overwrite saved motion with frozen zeros")
	game.ready_frames = 0
	game._resume_flight()
	game._physics_process(0)
	check(game.drone.linear_velocity.is_equal_approx(velocity) and game.drone.angular_velocity.is_equal_approx(angular), "resume restores both linear and angular velocity before simulation continues")
	await wait_physics(3)
	check(game.drone.linear_velocity.length() > 8 and game.drone.angular_velocity.length() > 0.1, "restored velocity survives physics synchronization instead of being reset to zero")
	game._set_paused(true)
	game._reset_attitude()
	game._resume_flight()
	game.ready_frames = 0
	game._physics_process(0)
	check(game.drone.linear_velocity == Vector3.ZERO and game.drone.angular_velocity == Vector3.ZERO, "explicit reset clears the saved pause snapshot so old velocity cannot return")
	game._set_paused(true)
	var relay: MissionDefinition
	for x in range(-3, 4):
		for z in range(-3, 4):
			var plan: Dictionary = game.store.regions.plan("surface", Vector2i(x, z))
			for candidate: MissionDefinition in plan.missions:
				if candidate.kind == "hold_interact" and relay == null:
					relay = candidate
	game.exploration.visit(relay.target_point)
	game.missions.accept(relay.id, game._world_position()) # This test checks an already accepted interaction.
	game._deploy(relay.target_point)
	await game._wait_for_world()
	var radio_profile := {"name": "暂停交互测试", "axes": {}, "auxiliary": [{"id": "interact", "name": "交互", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false, "bindings": {"1": "interact"}}]}
	for index in 4:
		radio_profile.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": -1.0 if index == 3 else 0.0, "invert": false}
	game.test_radio.activate_profile(radio_profile, 99)
	game.test_radio._process(0)
	game.test_radio.pressed = true
	game.test_radio._process(0)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	await create_timer(2.3).timeout
	game.test_radio.pressed = false
	game.test_radio._process(0)
	check(game.paused and game.store.mission_status(relay.id) == "completed" and game.store.data.credits == 30, "held interaction completes the generated beacon while flight is paused")
	var fixture: Dictionary = game.store.data.duplicate(true)
	fixture.credits = 200
	game.store._commit(fixture)
	var station: Dictionary = game.store.regions.region(RegionalWorld.key_at(game._world_position())).stations[0]
	game.drone.apply_tuning(FlightTuning.defaults())
	game._deploy(station.point)
	await game._wait_for_world()
	game._set_paused(false)
	await create_timer(1.0).timeout
	game._set_paused(true)
	key.pressed = true
	game._unhandled_key_input(key)
	check(game.menu is Workshop and game.paused, "E opens combined platform services after physical landing")
	var buy: Button = game.menu.offer_buttons[game.catalog.manifest.offers[0].id]
	buy.pressed.emit()
	check(game.store.data.credits == 50 and game.store.data.owned.has("base.prop.p5_smooth"), "platform shop purchase uses normal saved ownership and credit transaction")
	game._close_menu()

	game._show_workshop()
	var workshop: Workshop = game.menu
	var runtime_before: Dictionary = game.drone.tuning.duplicate(true)
	for axis in FlightTuning.AXES:
		workshop.rate_controls[axis].max_rate_dps.value = independent.axes[axis].max_rate_dps
		workshop.rate_controls[axis].expo.value = independent.axes[axis].expo
	workshop.advanced_controls.gravity.value = 7.4
	workshop.advanced_controls.air_drag.value = 2.25
	workshop.advanced_controls.angular_drag.value = 1.5
	check(workshop.curve_plot.sample(0.5).is_equal_approx(Vector3(220, 105, 319.125)), "per-axis controls immediately update three distinct response curves")
	check(game.drone.tuning == runtime_before, "draft changes leave live physics unchanged until saving")
	var motion := InputEventMouseMotion.new()
	var plot := workshop.curve_plot.plot_rect()
	motion.position = Vector2(plot.position.x + plot.size.x * 0.75, plot.get_center().y)
	workshop.curve_plot._gui_input(motion)
	check(workshop.curve_plot.tooltip_text.contains("50%") and workshop.curve_plot.tooltip_text.contains("220.0"), "curve hover reports stick percentage and exact angular response")
	workshop.tabs.current_tab = 1
	await capture_image("workshop-rates")
	workshop.tabs.current_tab = 2
	await capture_image("workshop-environment")
	button_named(workshop, "保存并应用").pressed.emit()
	check(game.drone.tuning.axes.roll.max_rate_dps == 800 and game.drone.tuning.axes.pitch.max_rate_dps == 210 and game.drone.tuning.axes.yaw.max_rate_dps == 690, "saving applies all three independent angular limits to the production drone")
	check(is_equal_approx(game.drone.gravity_scale * 9.81, 7.4) and game.drone.tuning.air_drag == 2.25 and game.drone.tuning.angular_drag == 1.5, "saving applies advanced gravity and both resistance settings")
	var restart := ProgressStore.new(game.catalog, game.store.path)
	var saved: Dictionary = restart.data.settings.flight
	check(FlightTuning.valid(saved) and saved.axes.pitch.expo == 0 and is_equal_approx(saved.gravity, 7.4), "restart restores per-axis curves and environment settings together")
	var rejected: Dictionary = restart.data.settings.duplicate(true)
	rejected.flight.gravity = NAN
	check(not restart.save_settings(rejected).ok and is_equal_approx(ProgressStore.new(game.catalog, game.store.path).data.settings.flight.gravity, 7.4), "invalid direct settings write leaves previous persisted tuning intact")
	check(not restart.save_loadout(restart.data.build, rejected).ok, "invalid flight values cannot bypass validation through equipment saves")
	game._close_menu()
	game._show_workshop()
	workshop = game.menu
	check(workshop.rate_controls.yaw.max_rate_dps.value == 690 and is_equal_approx(workshop.advanced_controls.gravity.value, 7.4), "reopening workshop populates saved independent controls")
	button_named(workshop, "恢复默认操控").pressed.emit()
	button_named(workshop, "恢复默认环境").pressed.emit()
	check(workshop.flight_profile == FlightTuning.defaults() and game.drone.tuning.axes.roll.max_rate_dps == 800, "restore-default buttons affect only the draft until applied")
	game._close_menu()
	check(game.drone.tuning.axes.roll.max_rate_dps == 800 and is_equal_approx(game.drone.tuning.gravity, 7.4), "canceling draft changes preserves current flight settings")
	game.queue_free()
	await process_frame
	print("TUNING_RESULT failures=", failed)
	quit(1 if failed else 0)

func capture_image(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			await process_frame
			await RenderingServer.frame_post_draw
			var directory := argument.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(directory)
			root.get_texture().get_image().save_png(directory.path_join(filename + ".png"))
