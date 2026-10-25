extends SceneTree

var failed := 0
var checked := 0
var test_dir := "user://tests/missions_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func click_control(control: Control) -> void:
	if control.get_parent().get_parent() is ScrollContainer:
		control.get_parent().get_parent().ensure_control_visible(control)
		await process_frame
		await process_frame
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://../.local/test-results"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)

func run() -> void:
	var catalog := ContentCatalog.new()
	var photo: MissionDefinition = catalog.missions["base.mission.sky_photo"]
	var relay: MissionDefinition = catalog.missions["base.mission.relay"]
	check(catalog.errors.is_empty() and catalog.missions.size() == 2, "two resource-defined mission types register with validated rewards and map references")
	var original := var_to_str(photo)
	for field: String in ["location_id", "reward_id", "max_distance", "max_angle_deg", "target_point"]:
		var manifest := catalog.manifest.duplicate() as ContentManifest
		manifest.missions = catalog.manifest.missions.duplicate()
		var invalid := photo.duplicate() as MissionDefinition
		match field:
			"location_id": invalid.location_id = "missing"
			"reward_id": invalid.reward_id = relay.reward_id
			"max_distance": invalid.max_distance = -1
			"max_angle_deg": invalid.max_angle_deg = NAN
			"target_point": invalid.target_point = Vector3(INF, 0, 0)
		manifest.missions[1] = invalid
		check(not ContentCatalog.new(manifest).errors.is_empty(), "invalid mission content rejected: " + field)
	var store := ProgressStore.new(catalog, test_dir.path_join("progress.json"))
	check(store.mission_status(photo.id) == "available" and store.data.tracked_mission.is_empty(), "new saves expose unclaimed missions without automatic photo rewards")
	check(not store.accept_mission("missing").ok and not store.complete_mission(photo.id).ok and not store.track_mission(photo.id).ok, "unknown, unclaimed completion and unclaimed tracking are rejected")
	check(store.accept_mission(photo.id).ok and store.mission_status(photo.id) == "active" and store.data.tracked_mission == photo.id and store.data.credits == 0, "acceptance persists active state and tracking without awarding credits")
	var restarted := ProgressStore.new(catalog, store.path)
	check(restarted.mission_status(photo.id) == "active" and restarted.data.tracked_mission == photo.id, "restart restores active photo mission and tracked selection")
	check(not store.complete_mission(photo.id).ok and store.data.credits == 0, "photo completion requires a saved valid photo")
	var nav := MapNavigation.new()
	var controller := MissionController.new(catalog, store, nav)
	controller.sync_navigation(Vector3.ZERO)
	check(nav.selected_id == photo.location_id and nav.teleport_location(photo.location_id) == null, "restored mission tracks its non-teleportable map target")
	check(controller.track("", Vector3.ZERO).ok and nav.selected() == null and store.mission_status(photo.id) == "active", "stopping tracking preserves active progress while clearing its own navigation")
	check(controller.track(photo.id, Vector3.ZERO).ok and nav.selected_id == photo.location_id, "active mission can be tracked again")
	nav.select("shop.harbor", Vector3.ZERO)
	controller.track("", Vector3.ZERO)
	check(nav.selected_id == "shop.harbor", "stopping mission tracking preserves an independently selected destination")
	var camera_position := photo.target_point + Vector3(0, 0, 30)
	var pose := Transform3D(Basis.IDENTITY, camera_position)
	var good := PhotoObjective.evaluate(photo, pose, true)
	check(good.ok and is_equal_approx(good.distance, 30) and is_zero_approx(good.angle), "photo evaluator accepts centered unobstructed framing")
	check(not PhotoObjective.evaluate(photo, Transform3D(Basis.IDENTITY, photo.target_point + Vector3(0, 0, 5)), true).ok, "too-close photos are rejected")
	check(not PhotoObjective.evaluate(photo, Transform3D(Basis.IDENTITY, photo.target_point + Vector3(0, 0, 100)), true).ok, "too-distant photos are rejected")
	check(not PhotoObjective.evaluate(photo, Transform3D(Basis(Vector3.UP, PI), camera_position), true).ok, "a target behind the camera cannot complete a photo")
	check(not PhotoObjective.evaluate(photo, pose, false).ok, "occlusion rejects otherwise valid framing")
	check(not PhotoObjective.evaluate(photo, pose, true, false).ok, "unloaded collision cannot count as a clear sight line")
	check(not PhotoObjective.evaluate(photo, Transform3D(Basis.IDENTITY, Vector3(NAN, 0, 0)), true).ok, "non-finite camera evidence is rejected")
	check(PhotoObjective.evaluate(photo, Transform3D(Basis.IDENTITY, photo.target_point + Vector3(0, 0, 15)), true).ok and PhotoObjective.evaluate(photo, Transform3D(Basis.IDENTITY, photo.target_point + Vector3(0, 0, 65)), true).ok, "declared photo distance boundaries are inclusive")
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color("79dfc9"))
	var fixture_path := test_dir.path_join("photo.png")
	check(image.save_png(fixture_path) == OK, "photo persistence fixture saves a real PNG")
	check(not store.complete_mission(photo.id, {"photo_path": fixture_path}).ok, "missing photo metadata cannot grant a reward")
	write_json(fixture_path.get_basename() + ".json", {"mission_id": photo.id, "photo_check": {"ok": true, "distance": 500, "angle": 0}})
	check(not store.complete_mission(photo.id, {"photo_path": fixture_path}).ok, "out-of-range saved assessment cannot bypass reward checks")
	write_json(fixture_path.get_basename() + ".json", {"mission_id": relay.id, "photo_check": good})
	check(not store.complete_mission(photo.id, {"photo_path": fixture_path}).ok, "saved evidence from a different mission is rejected")
	write_json(fixture_path.get_basename() + ".json", {"mission_id": photo.id, "photo_check": good})
	store.writable = false
	check(not store.complete_mission(photo.id, {"photo_path": fixture_path}).ok and store.data.credits == 0 and store.mission_status(photo.id) == "active", "failed completion commit exposes no reward or completed status")
	store.writable = true
	check(store.complete_mission(photo.id, {"photo_path": fixture_path}).ok and store.data.credits == 45 and store.mission_status(photo.id) == "completed", "photo evidence and reward complete atomically")
	check(store.complete_mission(photo.id).get("duplicate", false) and store.data.credits == 45, "repeated finish without a new acceptance cannot duplicate rewards")
	restarted = ProgressStore.new(catalog, store.path)
	check(restarted.data == JSON.parse_string(JSON.stringify(store.data)) and restarted.data.assignments[photo.id].photo_path == fixture_path, "restart preserves completed photo evidence and credits exactly")
	check(not restarted.track_mission(photo.id).ok, "completed missions cannot become active through tracking")
	var legacy := store._new_profile()
	legacy.erase("assignments")
	legacy.erase("tracked_mission")
	legacy.credits = 200
	legacy.facilities[relay.facility_id] = true
	legacy.missions[relay.facility_id] = true
	legacy.transactions = [relay.transaction_id()]
	var legacy_path := test_dir.path_join("legacy.json")
	write_json(legacy_path, legacy)
	var migrated := ProgressStore.new(catalog, legacy_path)
	check(migrated.mission_status(relay.id) == "completed" and migrated.mission_status(photo.id) == "available" and migrated.data.credits == 200, "old repaired relay saves migrate without issuing rewards again")
	check(migrated.complete_relay(relay.facility_id, relay.mission_tag, relay.city_tag).ok and migrated.data.credits == 200, "legacy completion API shares the same persistent transaction")
	var blocked := ProgressStore.new(catalog, test_dir.path_join("blocked.json"))
	blocked.writable = false
	check(not blocked.accept_mission(photo.id).ok and blocked.mission_status(photo.id) == "available" and blocked.data.tracked_mission.is_empty(), "failed acceptance save cannot expose accepted or tracked state")
	var malformed := store.data.duplicate(true)
	malformed.assignments[photo.id] = {"status": "completed", "photo_path": 123}
	write_json(test_dir.path_join("malformed.json"), malformed)
	check(store._read(test_dir.path_join("malformed.json")).is_empty(), "malformed persisted mission evidence is rejected before UI loading")
	check(var_to_str(photo) == original, "mission runtime never mutates shared task resources")

	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await game._wait_for_world()
	var photo_plan: Dictionary = {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			var plan: Dictionary = game.store.regions.plan("sky", Vector2i(x, z))
			for candidate: MissionDefinition in plan.get("missions", []):
				if candidate.kind == "photo" and photo_plan.is_empty():
					photo = candidate
					photo_plan = plan
	game.store.visit_region(photo_plan.id)
	game._deploy(photo.target_point + Vector3(10, 8, 20))
	await game._wait_for_world()
	await key(KEY_F3)
	var board: RegionMap = game.menu
	check(board != null and board.accept_button != null, "F3 opens the real production mission panel")
	board.task_filter.select(2)
	board.task_filter.item_selected.emit(2)
	board._select(photo.location_id)
	await process_frame
	await click_control(board.rows[photo.id])
	await click_control(board.accept_button)
	check(game.store.mission_status(photo.id) == "active" and game.navigation.selected_id == photo.location_id and board.accept_button.disabled, "real panel clicks accept the photo mission and start guidance")
	await capture("missions-active")
	# Selection already shares the map; acceptance needs no second screen.
	board._select(photo.location_id)
	await process_frame
	check(game.menu is RegionMap and game.menu.teleport_button.disabled and game.menu.details.text.contains("摄影"), "mission map action selects the actual photo target without enabling teleport")
	await capture("missions-map")
	game._close_menu()
	game._deploy(photo.target_point + Vector3(10, 8, 20))
	await game._wait_for_world()
	for frame in 600:
		await process_frame
		if game.streamer.collision_ready(photo.target_point):
			break
	for index in 3:
		await physics_frame
	game.drone.camera.current = true
	game.drone.camera.look_at(photo.target_point - game.streamer.origin_offset)
	await process_frame
	await process_frame
	var actual: Dictionary = game._assess_photo(photo)
	print("PHOTO_ASSESSMENT ", actual)
	check(actual.ok, "actual streamed station geometry and first-person camera satisfy photo rules")
	var decoy: MissionDefinition
	for x in range(-3, 4):
		for z in range(-3, 4):
			var p: Dictionary = game.store.regions.plan("surface", Vector2i(x, z))
			for candidate: MissionDefinition in p.missions:
				if candidate.kind == "photo" and candidate.id != photo.id and candidate.target_point.distance_to(photo.target_point) > 100 and decoy == null:
					decoy = candidate
	game.store.accept_mission(decoy.id)
	var selection: Dictionary = game._photo_selection()
	check(selection.mission.id == photo.id and selection.assessment.ok and game.store.mission_status(decoy.id) == "active", "multiple accepted photos select the subject in frame instead of a distant tracked objective")
	game.missions.track(photo.id, game._world_position())
	var obstacle: Node3D = WorldGeometry.create_box((game.drone.camera.global_position + photo.target_point - game.streamer.origin_offset) * 0.5, Vector3(8, 8, 8), Color("343434"))
	game.add_child(obstacle)
	for index in 3:
		await physics_frame
	check(not game._assess_photo(photo).ok and game._assess_photo(photo).message.contains("遮挡"), "real inserted collision blocks the station and prevents completion")
	obstacle.queue_free()
	for index in 3:
		await physics_frame
	check(game._assess_photo(photo).ok, "removing the occluder restores a clear shot")
	await capture("missions-framing")
	game.drone.rotation.y = 0
	game.chase_camera.current = true
	await process_frame
	await process_frame
	check(game._assess_photo(photo).ok, "production third-person follow camera can satisfy the same photo objective")
	await capture("missions-third-person")
	game.drone.camera.current = true
	game.drone.rotation.y = 0
	game.drone.camera.look_at(photo.target_point - game.streamer.origin_offset)
	await process_frame
	var shift := Vector3(64, 0, 0)
	game.streamer.shift_origin(shift)
	game.drone.shift_origin(shift)
	game.features.position -= shift
	await process_frame
	await process_frame
	check(game._assess_photo(photo).ok, "photo distance, framing and occlusion remain correct after origin shift")
	var before_credits: int = game.store.data.credits
	game.input_focused = false
	await game._capture()
	game.input_focused = true
	check(game.store.data.credits == before_credits and game.store.mission_status(photo.id) == "active", "unfocused capture cannot complete the mission")
	game.missions.track("", game._world_position())
	check(game.missions.photo_candidate() != null and game.store.mission_status(photo.id) == "active", "accepted photos remain eligible after stopping navigation tracking")
	if DisplayServer.get_name() != "headless":
		game.store.writable = false
		await game._capture()
		check(game.store.mission_status(photo.id) == "active" and game.store.data.credits == before_credits, "real saved photo cannot expose completion when progress commit fails")
		game.store.writable = true
		await key(KEY_F12)
		for frame in 60:
			await process_frame
			if not game.screenshot_busy:
				break
		check(game.store.mission_status(photo.id) == "completed" and game.store.data.credits == before_credits + 30, "real F12 screenshot completes the mission and awards credits")
		var path: String = game.store.data.assignments.get(photo.id, {}).get("photo_path", "")
		check(FileAccess.file_exists(path) and FileAccess.file_exists(path.get_basename() + ".json"), "production capture persists the photo and its frame metadata")
		await game._capture()
		check(game.store.data.credits == before_credits + 30, "later ordinary photos do not repeat the mission reward")
	else:
		var headless_path := test_dir.path_join("headless-production.png")
		var saved: Dictionary = game._save_capture(image, headless_path, {"mission_id": photo.id, "photo_check": actual})
		check(saved.ok and game.missions.finish(photo.id, {"photo_path": headless_path}).ok, "headless uses the real save and transaction path with a PNG fixture")
	var restart_game := ProgressStore.new(game.catalog, game.store.path)
	check(restart_game.mission_status(photo.id) == "completed" and restart_game.data.credits == game.store.data.credits and restart_game.data.tracked_mission.is_empty(), "production restart preserves completion and automatically clears finished tracking")
	game._show_missions()
	await process_frame
	board = game.menu
	board._select(photo.location_id)
	board.refresh()
	check(not board.accept_button.disabled and not board.track_button.disabled and board.detail.text.contains("奖励已发放") and board.accept_button.text.contains("再次"), "completed panel offers explicit location tracking or replay and explains first reward already paid")
	await capture("missions-completed")
	game._close_menu()
	var blocked_path := test_dir.path_join("blocked-file")
	var blocker := FileAccess.open(blocked_path, FileAccess.WRITE)
	blocker.store_string("file blocks directory creation")
	blocker.close()
	check(not game._save_capture(image, blocked_path.path_join("photo.png"), {}).ok, "actual photo write failure reports failure rather than granting a reward")
	game.queue_free()
	await process_frame
	print("MISSIONS_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
