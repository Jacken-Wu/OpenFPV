extends SceneTree

class VirtualInput:
	extends FlightInput
	var connected := true
	var axes: Array[float] = [0.0, 0.0, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var buttons: Array[bool] = [false, false, false, false]
	func radio_connected() -> bool:
		return connected
	func radio_axis(index: int) -> float:
		return axes[index]
	func radio_buttons() -> Array[bool]:
		return buttons.duplicate()

class VirtualGame:
	extends "res://scripts/main.gd"
	var test_radio := VirtualInput.new()
	func _create_flight_input() -> FlightInput:
		return test_radio

var failed := 0
var requests: Array[String] = []

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func profile() -> Dictionary:
	var value := {"name": "动作测试", "guid": "virtual", "axes": {}, "auxiliary": [
		{"id": "pause", "name": "飞行", "source": "axis", "axis": 4, "min": -1.0, "max": 1.0, "type": "two_position", "invert": false, "bindings": {"0": "pause", "1": "resume"}},
		{"id": "reset", "name": "重置", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false, "bindings": {"1": "reset"}},
		{"id": "camera", "name": "视角", "source": "axis", "axis": 5, "min": -1.0, "max": 1.0, "type": "three_position", "invert": false, "bindings": {"0": "toggle_camera", "2": "map"}},
		{"id": "knob", "name": "旋钮", "source": "axis", "axis": 6, "min": -1.0, "max": 1.0, "type": "analog", "invert": false, "bindings": {"0": "help", "2": "photo"}},
		{"id": "interact", "name": "交互", "source": "buttons", "buttons": [1], "type": "momentary", "invert": false, "bindings": {"1": "interact"}}
	]}
	for index in 4:
		value.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": -1.0 if index == 3 else 0.0, "invert": false}
	return value

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var value := profile()
	check(FlightInput.valid_profile(value) and FlightInput.valid_profile(JSON.parse_string(JSON.stringify(value))), "per-position bindings validate and survive JSON persistence")
	for field: String in ["bad_action", "bad_position", "bad_container"]:
		var invalid := value.duplicate(true)
		match field:
			"bad_action": invalid.auxiliary[0].bindings["0"] = "launch_missile"
			"bad_position": invalid.auxiliary[0].bindings["2"] = "pause"
			"bad_container": invalid.auxiliary[0].bindings = []
		check(not FlightInput.valid_profile(invalid), "invalid binding rejected: " + field)
	var reader := VirtualInput.new()
	root.add_child(reader)
	reader.set_process(false)
	reader.activate_profile(value, 99)
	reader.action_requested.connect(func(action: String): requests.append(action))
	reader.enabled = false
	reader._process(0)
	check(requests.is_empty(), "activating a profile primes current positions without firing their bindings")
	reader.axes[4] = 1.0
	reader._process(0)
	check(requests == ["resume"], "paused flight still polls switch commands so a switch can resume")
	for index in 20:
		reader._process(0)
	check(requests.size() == 1, "remaining in one detent never repeats its command")
	reader.axes[4] = -1.0
	reader._process(0)
	check(requests.back() == "pause", "opposite detent can explicitly pause instead of toggling")
	requests.clear()
	reader.buttons[0] = true
	reader._process(0)
	reader._process(0)
	reader.buttons[0] = false
	reader._process(0)
	reader.buttons[0] = true
	reader._process(0)
	check(requests == ["reset", "reset"], "momentary reset fires once per press and never on an unbound release")
	requests.clear()
	for raw: float in [-0.1, 0.05, -0.02, 0.08, -0.05]:
		reader.axes[4] = raw
		reader._process(0)
	check(requests.is_empty(), "two-position axis jitter around the center does not fire actions")
	reader.axes[4] = 0.4
	reader._process(0)
	check(requests == ["resume"], "axis crossing the hysteresis band triggers one new detent")
	requests.clear()
	reader.axes[5] = -1.0
	reader._process(0)
	reader.axes[5] = 0.0
	reader._process(0)
	reader.axes[5] = 1.0
	reader._process(0)
	check(requests == ["toggle_camera", "map"], "three-position switch supports distinct actions with unbound middle")
	requests.clear()
	reader.axes[6] = 1.0
	reader._process(0)
	for raw: float in [0.48, 0.52, 0.45, 0.51]:
		reader.axes[6] = raw
		reader._process(0)
	check(requests == ["photo"], "continuous knob uses stable low/middle/high action zones")
	reader.buttons[1] = true
	reader._process(0)
	check(reader.action_held("interact"), "bound interaction remains held while its control is held")
	reader.buttons[1] = false
	reader._process(0)
	check(not reader.action_held("interact"), "releasing a momentary control releases held interaction")
	requests.clear()
	reader.set_actions_enabled(false)
	reader.axes[4] = -1.0
	reader.buttons[0] = false
	reader._process(0)
	reader.set_actions_enabled(true)
	reader._process(0)
	check(requests.is_empty(), "menu and focus suppression discard transitions and reprime on return")
	reader.axes[4] = 1.0
	reader._process(0)
	check(requests == ["resume"], "fresh deliberate movement works after suppression ends")
	requests.clear()
	reader.profile.auxiliary[0].bindings["0"] = "reset"
	reader.buttons[0] = true
	reader.axes[4] = -1.0
	reader._process(0)
	check(requests == ["reset"], "two controls requesting the same action in a frame do not duplicate it")
	reader.buttons[1] = true
	reader._process(0)
	reader.connected = false
	reader._process(0)
	check(not reader.using_radio and not reader.action_held("interact") and reader.auxiliary_positions.is_empty(), "disconnect clears action history and held interactions even while flight is paused")
	reader.connected = true
	reader.activate_profile(value, 99)
	requests.clear()
	reader._process(0)
	check(requests.is_empty(), "reconnection never fires an existing detent as a fresh action")
	reader.queue_free()

	var game := VirtualGame.new()
	root.add_child(game)
	await game._wait_for_world()
	var radio := game.test_radio
	radio.activate_profile(value, 99)
	radio._process(0)
	radio.axes[3] = 1.0
	radio.axes[4] = 1.0
	radio._process(0)
	await physics_frame
	await physics_frame
	check(not game.paused and not game.drone.freeze and game.drone.controls.w == 1.0, "bound resume immediately enables current full throttle with no arming step or low-throttle gate")
	await create_timer(0.2).timeout
	check(game.drone.total_thrust > 0 and game.drone.linear_velocity.y > 0, "resumed production drone produces thrust without an armed state")
	radio.axes[4] = -1.0
	radio._process(0)
	check(game.drone.total_thrust == 0 and game.drone.controls == Vector4.ZERO, "pause immediately clears motor output and flight controls")
	await physics_frame
	await physics_frame
	var at := game.drone.position
	await create_timer(0.1).timeout
	check(game.paused and game.drone.freeze and game.drone.total_thrust == 0 and game.drone.position.is_equal_approx(at), "bound pause freezes production physics and clears motor output")
	radio.axes[4] = 1.0
	radio._process(0)
	await create_timer(0.1).timeout
	radio.buttons[0] = true
	radio._process(0)
	check(not game.paused and game.drone.freeze and game.drone.position.is_equal_approx(game.spawn_world - game.streamer.origin_offset), "bound reset redeploys immediately while preserving the running state")
	await create_timer(0.1).timeout
	check(not game.drone.freeze and game.drone.controls.w == 1.0, "flight continues after reset as soon as collision is ready")
	radio.buttons[0] = false
	radio.axes[4] = -1.0
	radio._process(0)
	radio.buttons[0] = true
	radio._process(0)
	check(game.paused, "reset while paused keeps flight paused")
	game.drone.rotation = Vector3(0.6, 1.0, -0.4)
	game.drone.linear_velocity = Vector3(4, 2, 1)
	game.drone.angular_velocity = Vector3(1, 2, 3)
	var reset_key := InputEventKey.new()
	reset_key.physical_keycode = KEY_R
	reset_key.pressed = true
	game._unhandled_key_input(reset_key)
	check(game.drone.global_basis.is_equal_approx(Basis.IDENTITY) and game.drone.linear_velocity == Vector3.ZERO and game.drone.angular_velocity == Vector3.ZERO, "R resets full roll/pitch/yaw and both velocities, not just speed")
	await create_timer(0.05).timeout
	check(game.paused and game.drone.global_basis.is_equal_approx(Basis.IDENTITY), "paused R reset remains upright across physics steps")
	radio.axes[3] = -1.0
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = 1.0
	radio._process(0)
	await create_timer(0.05).timeout
	game.drone.rotation = Vector3(0.7, -0.8, 0.5)
	game.drone.angular_velocity = Vector3(3, 2, 1)
	game._unhandled_key_input(reset_key)
	await create_timer(0.06).timeout
	check(not game.paused and game.drone.global_basis.is_equal_approx(Basis.IDENTITY) and game.drone.angular_velocity.is_zero_approx(), "running R reset remains upright after freeze and physics synchronization")
	game._set_paused(true)
	game.drone.global_transform = Transform3D(Basis.from_euler(Vector3(0.5, 0.9, -0.6)), game.drone.global_position + Vector3(3, 15, 2))
	var in_place_position := game.drone.global_position
	var deployment := game.spawn_world
	radio.profile.auxiliary[1].bindings["1"] = "reset_attitude"
	radio.buttons[0] = false
	radio._process(0)
	radio.buttons[0] = true
	radio._process(0)
	check(game.paused and game.drone.global_position.is_equal_approx(in_place_position) and game.drone.global_basis.y.is_equal_approx(Vector3.UP) and game.spawn_world == deployment, "bound in-place reset levels the drone without changing position or deployment")
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = 1.0
	radio._process(0)
	await create_timer(0.05).timeout
	check(game.drone.global_basis.y.is_equal_approx(Vector3.UP) and game.drone.angular_velocity.is_zero_approx(), "in-place reset survives resuming from pause")
	game._edit_radio(value)
	radio.axes[4] = 1.0
	radio._process(0)
	check(game.menu is RadioCalibration and game.paused, "moving a bound resume switch in settings cannot resume flight")
	game._close_menu()
	radio._process(0)
	check(not game.paused, "closing settings restores the running state without retriggering the held switch")
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = 1.0
	radio._process(0)
	check(not game.paused, "switch can deliberately resume immediately after leaving settings")
	var was_first_person := game.drone.camera.current
	radio.axes[5] = -1.0
	radio._process(0)
	check(game.drone.camera.current != was_first_person, "bound camera action uses the production camera path")
	radio.axes[5] = 1.0
	radio._process(0)
	check(game.menu != null and game.paused, "bound map action opens the production menu and pauses")
	game._close_menu()
	game.integration_mode = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = 1.0
	radio._process(0)
	check(game.paused and not radio.actions_enabled, "focus loss blocks bound resume even if a switch moves")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	radio._process(0)
	check(not game.paused, "regaining focus restores previously running flight while priming the switch")
	game.integration_mode = true
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = 1.0
	radio._process(0)
	check(not game.paused, "one deliberate action resumes after focus returns")
	game._set_paused(true)
	var pause_key := InputEventKey.new()
	pause_key.pressed = true
	pause_key.physical_keycode = KEY_SPACE
	game._unhandled_key_input(pause_key)
	check(not game.paused, "space now resumes flight instead of requiring a separate motor unlock")
	game._unhandled_key_input(pause_key)
	check(game.paused, "space uses the same pause state as the radio and P key")
	radio.axes[3] = -1.0
	var relay: MissionDefinition
	for x in range(-3, 4):
		for z in range(-3, 4):
			var plan: Dictionary = game.store.regions.plan("surface", Vector2i(x, z))
			for candidate: MissionDefinition in plan.missions:
				if candidate.kind == "hold_interact" and relay == null:
					relay = candidate
	game.exploration.visit(relay.target_point)
	game.missions.accept(relay.id, game._world_position()) # Map acceptance; E pickup now requires landing.
	game._deploy(relay.target_point)
	await game._wait_for_world()
	radio.axes[4] = -1.0
	radio._process(0)
	radio.axes[4] = -1.0
	radio._process(0)
	game._set_paused(true)
	await create_timer(0.1).timeout
	radio.buttons[1] = true
	radio._process(0)
	await create_timer(2.3).timeout
	check(game.store.mission_status(relay.id) == "completed" and game.store.data.credits == 30, "holding a bound switch completes the generated two-second beacon interaction")
	radio.buttons[1] = false
	radio._process(0)
	radio.connected = false
	radio._process(0)
	game._perform_action("resume")
	check(game.paused and game.radio_required, "disconnect still requires explicit input selection before resuming")
	game.queue_free()
	await process_frame
	print("ACTIONS_RESULT failures=", failed)
	quit(1 if failed else 0)
