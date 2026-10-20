extends SceneTree

var failed := 0
var game: Node3D

func check(value: bool, description: String) -> void:
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game._wait_for_world()
	game._deploy(Vector3(-18, 1.2, 17))
	game._set_paused(false)
	await create_timer(0.7).timeout
	check(game._grounded(), "deploy, stream and settle on relay landing platform")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(2.3).timeout
	key.pressed = false
	Input.parse_input_event(key)
	check(game.store.data.facilities.get(game.RELAY_ID, false) and game.gate == null and game.store.data.credits == 200, "real held interaction repairs relay and removes gate after saved reward")
	var offer: OfferDefinition = game.catalog.manifest.offers[0]
	check(game.store.purchase(offer.id, offer.city_tag).ok, "task credits buy propellers through normal ownership checks")
	game._set_paused(true)
	game._show_workshop()
	var workshop: Workshop = game.menu
	workshop.apply_requested.emit(game.assembler.from_preset("base.preset.light35"), 300.0, 0.3)
	check(game.drone.mass < 0.35 and game.drone.rates_dps == 300, "landed workshop applies newly acquired kit and flight profile")
	game._close_menu()
	var restart := ProgressStore.new(game.catalog, game.store.path)
	check(restart.data.credits == 50 and restart.data.build.frame_id == "base.frame.f35" and restart.data.facilities.get(game.RELAY_ID, false), "restart preserves mission, shop, equipped parts and credits together")
	game.drone.armed = true
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	# Test sessions ignore real desktop focus; dispatch the production focus path below.
	game.integration_mode = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused and not game.drone.armed and game.drone.freeze, "focus loss pauses and disarms")
	game.integration_mode = true
	game.flight_input.using_radio = true
	game.flight_input.selected_device = 99
	game.flight_input._on_connection_changed(99, false)
	game._toggle_pause()
	check(game.paused and game.radio_required and not game.flight_input.using_radio, "disconnect requires explicit device or keyboard selection before resuming")
	game._show_map()
	check(game.menu != null, "map opens through production UI")
	game.queue_free()
	await process_frame
	print("INTEGRATION_RESULT failures=", failed)
	quit(1 if failed else 0)
