extends SceneTree
class VirtualInput extends FlightInput:
	var connected := true
	var pressed := false
	var map_pressed := false
	func radio_connected() -> bool:
		return connected
	func radio_axis(index: int) -> float:
		return -1.0 if index == 3 else 0.0
	func radio_buttons() -> Array[bool]:
		return [pressed, map_pressed]
class VirtualGame extends "res://scripts/main.gd":
	var test_radio := VirtualInput.new()
	func _create_flight_input() -> FlightInput:
		return test_radio
var failed := 0
var checked := 0
var game: Node3D
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1
func radio_profile() -> Dictionary:
	var result := {"name": "session test", "guid": "virtual", "axes": {}, "auxiliary": [
		{"id": "interact", "name": "交互", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false, "bindings": {"1": "interact"}},
		{"id": "map", "name": "地图", "source": "buttons", "buttons": [1], "type": "momentary", "invert": false, "bindings": {"1": "map"}}
	]}
	for index in 4:
		result.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": -1.0 if index == 3 else 0.0, "invert": false}
	return result
func interact() -> void:
	game.test_radio.pressed = false
	game.test_radio._process(0)
	game.test_radio.pressed = true
	game.test_radio._process(0)
	await process_frame
func release() -> void:
	game.test_radio.pressed = false
	game.test_radio._process(0)
	await process_frame
func map_key() -> void:
	game.test_radio.map_pressed = false
	game.test_radio._process(0)
	game.test_radio.map_pressed = true
	game.test_radio._process(0)
	await process_frame
func deploy(point: Vector3) -> void:
	game._close_menu()
	game._set_paused(true)
	game._deploy(point)
	await game._wait_for_world()
	for frame in 3:
		await physics_frame
func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://../.local/test-results/playability"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)
func find_task(kind: String, layer: String) -> MissionDefinition:
	for x in range(-3, 4):
		for z in range(-3, 4):
			var p: Dictionary = game.store.regions.plan(layer, Vector2i(x, z))
			for mission: MissionDefinition in p.get("legacy_missions", p.get("missions", [])):
				if mission.kind == kind:
					return mission
	return null
func begin(mission: MissionDefinition) -> void:
	var fields := mission.id.split(":")
	game.store.visit_region(":".join([fields[2], fields[3], fields[4]]))
	game.exploration.refresh(RegionalWorld.key_at(game._world_position()))
	game.missions.accept(mission.id, game._world_position())
func run() -> void:
	game = VirtualGame.new()
	root.add_child(game)
	await game._wait_for_world()
	game.test_radio.activate_profile(radio_profile(), 99)
	game.test_radio._process(0)
	var tuning := FlightTuning.defaults()
	tuning.gravity = 0.0
	game.drone.apply_tuning(tuning)
	var initial_credits: int = game.store.data.credits
	for layer: String in ["surface", "sky", "maze"]:
		var courier := find_task("courier", layer)
		begin(courier)
		await deploy(courier.checkpoints[0] - Vector3.UP * 0.65)
		await interact()
		check(game.store.data.assignments[courier.id].get("stage", 0) == 1 and game.menu == null, "physical-height radio pickup works in " + layer)
		await release()
		var restart := ProgressStore.new(game.catalog, game.store.path)
		check(restart.data.assignments[courier.id].get("stage", 0) == 1, "delivery pickup survives restart in " + layer)
		await deploy(courier.source_point - Vector3.UP * 0.65)
		await interact()
		await release()
		check(game.store.mission_status(courier.id) == "completed" and game.menu == null, "delivery handoff consumes interaction before platform menu in " + layer)
		var survey := find_task("survey", layer)
		begin(survey)
		await deploy(survey.target_point - Vector3.UP * 0.65)
		game._set_paused(false)
		await create_timer(survey.hold_seconds + 0.3).timeout
		game._set_paused(true)
		check(game.store.mission_status(survey.id) == "completed", "real low-speed survey dwell completes beside the beacon in " + layer)
		var relay := find_task("hold_interact", layer)
		begin(relay)
		await deploy(relay.target_point - Vector3.UP * 0.65)
		await interact()
		await create_timer(relay.hold_seconds + 0.3).timeout
		await release()
		check(game.store.mission_status(relay.id) == "completed", "held radio interaction completes actual calibration in " + layer)
		var circuit := find_task("circuit", layer)
		begin(circuit)
		for point in circuit.checkpoints:
			await deploy(point)
			game._set_paused(false)
			await create_timer(0.04).timeout
			game._set_paused(true)
		check(game.store.mission_status(circuit.id) == "completed", "ordered circuit completes through streamed checkpoints in " + layer)
		var photo := find_task("photo", layer)
		begin(photo)
		var vantage := photo.target_point + Vector3(0, 3, 18)
		if layer == "maze":
			var fields := photo.id.split(":")
			var p: Dictionary = game.store.regions.plan(layer, Vector2i(int(fields[3]), int(fields[4])))
			var data: Dictionary = p.shape.maze
			var cell := BiomeStructures.cell_at(data, photo.target_point)
			for direction in 4:
				if data.doors[cell] & (1 << direction):
					var step: Vector2i = BiomeStructures.DIRECTIONS[direction]
					vantage = BiomeStructures.cell_point(data, cell) + Vector3(step.x * 16, 7, step.y * 16)
					break
		await deploy(vantage)
		for frame in 150:
			await process_frame
		game.drone.camera.current = true
		game.drone.camera.look_at(photo.target_point - game.streamer.origin_offset)
		await process_frame
		var assessment: Dictionary = game._assess_photo(photo)
		check(assessment.ok, "real photo target is visible and photographable in " + layer)
		if assessment.ok:
			if DisplayServer.get_name() != "headless":
				game._capture()
				while game.screenshot_busy:
					await process_frame
			else:
				var fixture := Image.create(24, 24, false, Image.FORMAT_RGB8)
				fixture.fill(Color("517b73"))
				var path: String = game.store.path.get_base_dir().path_join(layer + "-photo.png")
				var saved: Dictionary = game._save_capture(fixture, path, {"mission_id": photo.id, "photo_check": assessment})
				if saved.ok:
					game.missions.finish(photo.id, {"photo_path": path})
		check(game.store.mission_status(photo.id) == "completed", "photo evidence and one-time reward commit in " + layer)
	check(game.store.data.credits == initial_credits + 450, "all five mission types in three layers award exactly once")
	# Remote menu open/close returns to the entry state.
	var station: Dictionary = game.store.regions.instance_at(game.store.regions.spawn_point()).stations[0]
	await deploy(station.point - Vector3.UP * 0.65)
	game._set_paused(false)
	await create_timer(0.06).timeout
	await interact()
	check(game.menu is Workshop and game.paused and not game.menu_was_paused, "radio interaction opens docked workshop from running flight")
	await release()
	game.menu.tabs.current_tab = 1
	var edit: LineEdit = game.menu.rate_controls.roll.max_rate_dps.get_line_edit()
	edit.grab_focus()
	edit.text = "510"
	await interact()
	await release()
	check(game.menu == null and not game.paused and game.store.data.settings.flight.axes.roll.max_rate_dps == 510, "same radio interaction commits the edited numeric field, saves, closes and restores running state")
	game._set_paused(true)
	await interact()
	await release()
	game.store.writable = false
	await interact()
	await release()
	check(game.menu is Workshop and game.paused, "failed settings save keeps workshop open and paused")
	game.store.writable = true
	await interact()
	await release()
	check(game.menu == null and game.paused, "paused workshop entry remains paused after saving and closing")
	game._set_paused(false)
	await map_key()
	check(game.menu is RegionMap and game.paused, "radio map switch opens the paused map")
	game.test_radio.map_pressed = false
	game.test_radio._process(0)
	await map_key()
	check(game.menu == null and not game.paused, "same radio map switch closes and resumes automatically")
	game._physics_process(0)
	await create_timer(0.04).timeout
	var entry_velocity := Vector3(5, 1, -3)
	var entry_angular := Vector3(0.2, 0.4, -0.1)
	game.drone.linear_velocity = entry_velocity
	game.drone.angular_velocity = entry_angular
	game._show_map()
	game._show_map()
	game._physics_process(0)
	check(game.drone.linear_velocity.is_equal_approx(entry_velocity) and game.drone.angular_velocity.is_equal_approx(entry_angular), "closing a running map preserves both linear and angular motion")
	await deploy(station.point - Vector3.UP * 0.65)
	game._show_map()
	await process_frame
	var view: RegionMap = game.menu
	check(is_equal_approx(view.map_canvas.map_scale, 0.7), "map always opens at fixed0.7 scale")
	view.map_canvas.map_scale = 3.0
	game._show_map()
	check(game.menu == null and game.paused, "keyboard map toggle closes while retaining prior pause")
	game._show_map()
	await process_frame
	view = game.menu
	check(is_equal_approx(view.map_canvas.map_scale, 0.7), "map reopens at fixed scale after prior zoom")
	var local := Vector2(130, 230)
	var tracked_before: String = game.navigation.selected_id
	var expected := view.map_canvas.unproject(local)
	var global_point := view.map_canvas.get_global_transform_with_canvas() * local
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = global_point
		root.push_input(event, true)
		await process_frame
	check(game.navigation.selected_id == tracked_before and view.viewed_id == "temporary" and Vector2(game.navigation.find_location("temporary").point.x, game.navigation.find_location("temporary").point.z).is_equal_approx(expected), "blank map click only previews a temporary marker and preserves guidance")
	check(game.navigation.teleport_location("temporary") == null, "temporary waypoint cannot teleport")
	view.track_button.pressed.emit()
	check(game.navigation.selected_id == "temporary", "temporary marker requires explicit Track button")
	game.exploration.refresh(Vector2i.ZERO)
	check(game.navigation.selected_id == "temporary" and game.navigation.selected() != null, "temporary waypoint survives map materialization")
	game._close_menu()
	game.flight_region = Vector2i(999999, 999999)
	game._process(0)
	check(game.navigation.selected_id == "temporary", "temporary guidance survives actual flight-region refresh")
	var to_target: Vector3 = game.navigation.waypoint() - game._world_position()
	game.drone.rotation.y = atan2(-to_target.x, -to_target.z)
	game.drone.camera.look_at(game.navigation.waypoint() - game.streamer.origin_offset)
	await process_frame
	await capture("compact-navigation")
	var reticle: Array = game.navigation_hud.get_children().filter(func(node: Node): return node is Label and node.text == "+")
	check(reticle.size() == 1 and reticle[0].z_index > game.navigation_hud.z_index, "centre reticle draws above navigation labels")
	# Focus recovery preserves intentional pauses and disconnection protection.
	game._set_paused(false)
	game.integration_mode = false
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.paused and not game.input_focused, "focus loss freezes flight")
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(not game.paused and game.input_focused, "focus return restores previously running flight")
	game._set_paused(true)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	game._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(game.paused, "focus return preserves a deliberate pause")
	game.integration_mode = true
	# New physical regions and platform registration create separate popup text.
	var far: Dictionary = game.store.regions.plan("surface", Vector2i(40, 40))
	var prior_popups: Array = game.unlock_notifications.shown.duplicate()
	game.store.writable = false
	game.store.visit_region(far.id)
	game.store.unlock_portal(far.stations[0].id)
	check(game.unlock_notifications.shown == prior_popups, "failed unlock transactions never display success popups")
	game.store.writable = true
	game.store.visit_region(far.id)
	check(game.unlock_notifications.shown.any(func(text: String): return text.contains("新地区地图已解锁")), "new region map unlock displays popup text")
	game.store.unlock_portal(station.id)
	check(game.unlock_notifications.shown.any(func(text: String): return text.contains("传送点已解锁")), "platform unlock displays popup text")
	await process_frame
	check(game.unlock_notifications.global_position.x >= 0 and game.unlock_notifications.get_global_rect().end.x <= root.get_visible_rect().size.x, "unlock popups remain inside the visible viewport")
	await capture("unlock-notices")
	check(game.streamer.radius == 4 and game.streamer.vertical_radius == 3 and game.streamer.desired.size() <= 825, "larger horizontal rendering retains bounded vertical and collision budgets")
	await deploy(Vector3(0, 299, 0))
	game.drone.paused_linear_velocity = Vector3(0, 80, 0)
	game._set_paused(false)
	await create_timer(0.6).timeout
	check(game._world_position().y > 300 and game.drone.altitude_cutoff and is_zero_approx(game.drone.total_thrust) and game.drone.world_origin_offset == game.streamer.origin_offset, "300m protection stops motors without clamping inertial motion; floating-origin stays synchronized")
	check(game.streamer.desired.size() <= 825 and game.streamer.desired.has(Vector3i(WorldGenerator.key_at(game._world_position()).x, -1, WorldGenerator.key_at(game._world_position()).z)), "high-altitude streaming keeps a bounded ground horizon")
	game._set_paused(true)
	game.queue_free()
	await process_frame
	print("PLAYABILITY_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
