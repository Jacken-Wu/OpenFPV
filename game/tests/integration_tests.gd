extends SceneTree

class VirtualInput extends FlightInput:
	var pressed := false
	func radio_connected() -> bool:
		return true
	func radio_axis(index: int) -> float:
		return -1.0 if index == 3 else 0.0
	func radio_buttons() -> Array[bool]:
		return [pressed]

class VirtualGame extends "res://scripts/main.gd":
	var test_radio := VirtualInput.new()
	func _create_flight_input() -> FlightInput:
		return test_radio

var failed := 0
var game: Node3D

func check(value: bool, description: String) -> void:
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = VirtualGame.new()
	root.add_child(game)
	await game._wait_for_world()
	var carried_wallet: Dictionary = game.store.data.duplicate(true)
	carried_wallet.credits = 350 # Existing balances survive the reward rebalance.
	game.store._commit(carried_wallet)
	# Native window focus can clear Input.parse_input_event's synthetic keys.
	# Drive the real shared interaction through a stable simulated USB button.
	var profile := {"name": "integration RC", "guid": "virtual", "axes": {}, "auxiliary": [{"id": "interact", "name": "交互", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false, "bindings": {"1": "interact"}}]}
	for index in 4:
		profile.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": -1.0 if index == 3 else 0.0, "invert": false}
	game.test_radio.activate_profile(profile, 99)
	game.test_radio._process(0)
	var holds: Array[MissionDefinition] = []
	for x in range(-3, 4):
		for z in range(-3, 4):
			var plan: Dictionary = game.store.regions.plan("surface", Vector2i(x, z))
			for mission: MissionDefinition in plan.missions:
				if mission.kind == "hold_interact" and holds.size() < 5:
					holds.append(mission)
	for mission in holds:
		game.missions.accept(mission.id, game._world_position())
		game._deploy(mission.target_point)
		await game._wait_for_world()
		# Physical loading and discovery publish on independent callbacks. Start the
		# held interaction only once the actual objective is available in this scene.
		var ready_deadline := Time.get_ticks_msec() + 3000
		while game.missions.interaction_at(game._world_position()) == null and Time.get_ticks_msec() < ready_deadline:
			await process_frame
		game.test_radio.pressed = true
		game.test_radio._process(0)
		# Await the persisted outcome rather than racing a fixed2.25s timer against
		# a window frame that may already have spent time generating the world.
		var finish_deadline := Time.get_ticks_msec() + 6000
		while game.store.mission_status(mission.id) != "completed" and Time.get_ticks_msec() < finish_deadline:
			await create_timer(0.05).timeout
		if game.store.mission_status(mission.id) != "completed":
			var near: MissionDefinition = game.missions.interaction_at(game._world_position())
			print("HELD_DIAGNOSTIC ", mission.id, " held=",game.flight_input.action_held("interact")," nearest=", near.id if near != null else "none", " notice=",game.last_notice)
		game.test_radio.pressed = false
		game.test_radio._process(0)
		await process_frame
	check(holds.size() == 5 and game.store.data.credits == 500, "shared held radio interaction completes five distinct generated objectives and persists rewards")
	var station: Dictionary = game.store.regions.region(RegionalWorld.key_at(game._world_position())).stations[0]
	game._deploy(station.point)
	await game._wait_for_world()
	game._set_paused(false)
	await create_timer(1).timeout
	game._set_paused(true)
	check(not game._docked_station().is_empty(), "real physics settles the drone onto a streamed service platform")
	game._perform_action("interact")
	check(game.menu is Workshop, "one interaction opens purchases, equipment and tuning together")
	var workshop: Workshop = game.menu
	for offer: OfferDefinition in game.catalog.manifest.offers:
		workshop.purchase_requested.emit(offer.id)
	check(game.store.data.credits == 50 and game.store.data.owned.has("base.preset.light35") and game.store.data.owned.has("base.prop.p5_smooth"), "combined shop buys permanent propellers and a complete kit")
	var flight_profile := FlightTuning.from_settings({"rates": 300.0, "expo": 0.3})
	workshop.apply_requested.emit(game.assembler.from_preset("base.preset.light35"), flight_profile)
	check(game.drone.mass < 0.35 and game.drone.tuning.axes.roll.max_rate_dps == 300, "docked equipment and independent tuning apply to the actual drone")
	game._close_menu()
	var restart := ProgressStore.new(game.catalog, game.store.path)
	check(restart.data.credits == 50 and restart.data.build.frame_id == "base.frame.f35" and restart.data.transactions.size() == 7, "restart restores generated rewards, both purchases and equipped configuration")
	game.integration_mode = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused and game.drone.freeze and game.drone.controls == Vector4.ZERO, "focus loss pauses and clears controls")
	game.integration_mode = true
	game.flight_input.using_radio = true
	game.flight_input.selected_device = 99
	game.flight_input._on_connection_changed(99, false)
	game._toggle_pause()
	check(game.paused and game.radio_required and not game.flight_input.using_radio, "disconnect requires explicit input selection before resuming")
	game._show_map()
	check(game.menu is RegionMap, "generated map opens through production UI")
	game.queue_free()
	await process_frame
	print("INTEGRATION_RESULT failures=", failed)
	quit(1 if failed else 0)
