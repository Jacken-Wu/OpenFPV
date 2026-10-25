extends SceneTree
var failed := 0
var checked := 0
var directory := "user://tests/exploration-captures"
var game: Node3D

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	check(catalog.errors.is_empty(), "all biome building pools validate")
	var fingerprint := catalog.fingerprint()
	var nav := MapNavigation.new(4)
	var target := MapLocation.new()
	target.id = "route-test"
	target.point = Vector3(120, 10, 120)
	nav.locations.append(target)
	nav.route_resolver = func(_from: Vector3, _to: MapLocation): return PackedVector3Array([Vector3(0, 10, 0), Vector3(120, 10, 0), target.point])
	nav.select(target.id, Vector3(-50, 10, 28))
	nav.update(Vector3(-10, 10, 28))
	nav.update(Vector3(25, 10, 28))
	check(nav.route_index == 1, "flying28m beside an already passed intermediate point continues to the following destination")
	nav.update(Vector3(65, 10, 28))
	nav.update(Vector3(108, 10, 28))
	check(nav.route_index == 2, "cutting a surface-route corner displays the next leg instead of requiring a U-turn")
	nav.update(Vector3(120, 10, 70))
	nav.update(Vector3(119, 10, 116))
	check(nav.arrived, "relaxed intermediate guidance still reaches the physical destination")
	nav.select(target.id, Vector3(-40, 60, 28))
	nav.update(Vector3(20, 60, 28))
	check(nav.route_index == 0, "wrong height cannot use surface-route lookahead")
	nav.select(target.id, Vector3(-100, 10, 0))
	nav.update(Vector3(100, 10, 0))
	check(nav.route_index == 0, "discontinuous reposition never scans through intermediate points")
	var world := BiomeWorld.new(catalog, 271828)
	var maze: Dictionary = {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			if maze.is_empty():
				maze = world.plan("maze", Vector2i(x, z))
	var data: Dictionary = maze.shape.maze
	var path := BiomeStructures.maze_path(data, 0, data.doors.size() - 1)
	check(path.size() >= 8, "real generated maze supplies a long connected navigation route")
	var location := MapLocation.new()
	location.id = "maze-rescue"
	location.layer = "maze"
	location.structure_id = maze.id
	location.point = path[path.size() - 1]
	var maze_nav := MapNavigation.new(4)
	maze_nav.locations.append(location)
	maze_nav.route_resolver = world.route
	maze_nav.select(location.id, path[0])
	var old_waypoint := maze_nav.waypoint()
	maze_nav.previous_point = path[5]
	maze_nav.has_previous = true
	maze_nav.update(path[6])
	check(maze_nav.route[0].distance_to(path[6]) <= 16.01 and maze_nav.waypoint() != old_waypoint, "stale maze waypoint automatically replans from the actual cell along connected corridors")
	maze_nav.select(location.id, path[0])
	check(maze_nav.route[0] != path[0], "already occupying a maze cell never requires touching its center before moving forward")
	maze_nav.previous_point = path[5]
	maze_nav.has_previous = true
	maze_nav.update(path[5].lerp(path[6], 0.002))
	check(maze_nav.route[0] != old_waypoint and maze_nav.route[0].distance_to(path[5]) <= 16.01, "slow flight with only3cm of movement per frame still rescues a missed maze point")
	var enumeration := {"kinds": {}, "empty": 0, "instances": 0, "varied": false}
	var first_layout := ""
	var coverage: Dictionary = {}
	var clear := true
	for x in range(-4, 5):
		for z in range(-3, 4):
			for layer: String in ["surface", "sky", "maze"]:
				var plan := world.plan(layer, Vector2i(x, z))
				if plan.is_empty():
					continue
				enumeration.instances += 1
				if plan.landmarks.is_empty():
					enumeration.empty += 1
				var layout := ""
				for landmark: Dictionary in plan.landmarks:
					coverage[String(plan.biomes[0].id).split(":")[0]] = true
					enumeration.kinds[landmark.kind] = true
					layout += String(landmark.kind)
					# A connected district contains services and flight paths by design.
					# Actual drone clearance is checked in regional_world_tests.
					if landmark.kind == "megastructure": continue
					for station: Dictionary in plan.stations:
						clear = clear and Vector2(landmark.point.x - station.point.x, landmark.point.z - station.point.z).length() > float(landmark.radius) + 6
					for mission: MissionDefinition in plan.missions:
						clear = clear and Vector2(landmark.point.x - mission.acceptance_point().x, landmark.point.z - mission.acceptance_point().z).length() > float(landmark.radius) + 6
						# Environmental gates intentionally pass beside/through open
						# structures; their actual body clearance has a physics suite.
						if mission.challenge.get("route_revision", 0) == 0 and mission.kind != "regional":
							clear = clear and Vector2(landmark.point.x - mission.target_point.x, landmark.point.z - mission.target_point.z).length() > float(landmark.radius) + 6
				if first_layout.is_empty():
					first_layout = layout
				else:
					enumeration.varied = enumeration.varied or layout != first_layout
	check(coverage.size() >= 7, "sampled core and outer biomes produce varied landmark pools")
	check(enumeration.kinds.has("pyramid") and enumeration.kinds.has("aqueduct") and enumeration.kinds.has("turbines") and enumeration.kinds.has("sky_colonnade"), "desert, surface, sky and underground special structures all occur")
	check(enumeration.empty > 0 and enumeration.varied and enumeration.empty < enumeration.instances, "special structures are optional and layouts vary instead of repeating one required gateway")
	check(clear, "generated landmarks retain platform and task clearances")
	var warm := world.plan("surface", Vector2i(2, -3))
	var cold := BiomeWorld.new(catalog, 271828).plan("surface", Vector2i(2, -3))
	check(JSON.stringify(warm.landmarks) == JSON.stringify(cold.landmarks) and JSON.stringify(warm.chunks) == JSON.stringify(cold.chunks), "cold seed reconstruction preserves building choice, geometry, ownership and stable IDs")
	check(catalog.fingerprint() == fingerprint and world.plans.size() <= 48, "building generation leaves shared content immutable and caches bounded")
	var wrong := catalog.manifest.duplicate() as ContentManifest
	wrong.biomes = wrong.biomes.duplicate()
	var invalid := wrong.biomes[0].duplicate() as BiomeDefinition
	invalid.parameters = invalid.parameters.duplicate(true)
	invalid.parameters.landmark_pool = [{"kind": "pyramid", "chance": 1.1}]
	wrong.biomes[0] = invalid
	check(not ContentCatalog.new(wrong).errors.is_empty(), "invalid landmark probability is rejected before world generation")
	var temp := "user://tests/save-library_%d" % Time.get_ticks_usec()
	var library := SaveLibrary.new(catalog, temp)
	var current := ProgressStore.new(catalog, library.active_path())
	current.data.credits = 321
	current.data.settings = {"flight": FlightTuning.defaults(), "radio_profiles": {}, "radio_active": false, "active_radio_profile": ""}
	var profile := {"name": "saved RC", "guid": "virtual", "axes": {}, "auxiliary": [{"id": "map", "name": "地图", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false, "bindings": {"1": "map"}}]}
	for index in 4:
		profile.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": -1.0 if index == 3 else 0.0, "invert": false}
	current.data.settings.radio_profiles["virtual"] = profile
	current.data.settings.active_radio_profile = "virtual"
	check(library.save(current).ok and ProgressStore.read_snapshot(current.path).credits == 321, "manual save commits current progress through validated atomic storage")
	var duplicate := library.duplicate_current(current, "沙海/测试副本")
	check(duplicate.ok and FileAccess.file_exists(library._path(duplicate.id)) and not duplicate.id.contains("/"), "save names containing slashes remain metadata and cannot change file paths")
	check(library.entries(current.path).size() == 2 and library.active_path() == current.path, "another save copy does not silently switch the active world")
	var new_world := library.new_world(current, "松林新世界", -98765)
	check(new_world.ok and new_world.store.data.seed == -98765 and new_world.store.data.credits == 0, "new world creates a separate initial slot with its chosen seed")
	var created: ProgressStore = new_world.store
	check(created.data.settings == current.data.settings and ProgressStore.read_snapshot(current.path).credits == 321, "creating a world preserves old progress and carries player control settings")
	check(FlightInput.valid_profile(created.data.settings.radio_profiles.virtual), "world slots preserve a complete RC calibration and auxiliary action binding")
	check(SaveLibrary.new(catalog, temp).active_path() == created.path, "active slot selection persists across application restart")
	check(library.rename_slot(library.id_for_path(created.path), "新的名称", created).ok and created.data.save_name == "新的名称", "renaming the current save updates its runtime and disk metadata")
	check(not library.delete_slot(library.id_for_path(created.path), created).ok and not library.delete_slot("../outside", created).ok and not library.load_slot("../outside", created).ok, "current-world deletion and forged paths are rejected")
	check(not library.duplicate_current(created, " ").ok and not library.rename_slot(duplicate.id, "bad\nname", created).ok, "blank and multiline save names are rejected")
	created.data.settings.flight.gravity = 8.5
	check(library.save(created).ok, "new control preferences save in the active world")
	var loaded := library.load_slot(duplicate.id, created)
	check(loaded.ok and loaded.store.data.seed == 271828 and loaded.store.data.credits == 321, "loading another slot restores that world's independent progress")
	var restored: ProgressStore = loaded.store
	check(is_equal_approx(restored.data.settings.flight.gravity, 8.5), "loading an older world retains current player control preferences")
	var pointer := library.active_path()
	library.writable = false
	check(not library.new_world(restored, "写入失败", 12).ok and not library.load_slot("legacy", restored).ok and not library.delete_slot("legacy", restored).ok and library.active_path() == pointer, "failed save operations keep the active slot and do not switch or remove worlds")
	library.writable = true
	var recovery := library.duplicate_current(restored, "备份恢复")
	library.rename_slot(recovery.id, "第二版名称", restored)
	write(library._path(recovery.id), "{broken")
	var recovered := library.load_slot(recovery.id, restored)
	check(recovered.ok and recovered.store.data.credits == 321 and not ProgressStore.read_snapshot(recovered.store.path).is_empty(), "damaged slot main file recovers its validated transaction backup")
	var active: ProgressStore = recovered.store
	check(library.delete_slot(duplicate.id, active).ok and not FileAccess.file_exists(library._path(duplicate.id)) and DirAccess.get_files_at(temp.path_join("trash")).size() >= 1, "deleting an inactive slot moves it into the recoverable trash directory")
	write(temp.path_join("active.json"), "{broken")
	check(not library.active_path().is_empty() and not ProgressStore.read_snapshot(library.active_path()).is_empty(), "damaged active marker falls back to a valid previous selection or legacy save")
	# Check real solid shells and their deliberately open flight corridors.
	var geometry := Node3D.new()
	root.add_child(geometry)
	var pyramid := Architecture.build("pyramid", "fixture/pyramid", Vector3.ZERO)
	geometry.add_child(WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": pyramid}, Vector3.ZERO))
	var tower := Architecture.build("radio_tower", "fixture/tower", Vector3(100, 0, 0))
	geometry.add_child(WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": tower}, Vector3.ZERO))
	await physics_frame
	await physics_frame
	var space := geometry.get_world_3d().direct_space_state
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 6, -35), Vector3(0, 6, 35))).is_empty(), "pyramid has a real open10m-wide traversable tunnel")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(15, 50, 0), Vector3(15, -2, 0))).is_empty(), "pyramid stepped shell has actual collision")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(100, 8, -30), Vector3(100, 8, 30))).is_empty(), "lattice tower keeps an open center for flight")
	var leg: Dictionary = tower[0]
	var across := Vector3.RIGHT * 2
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(leg.center - across, leg.center + across)).is_empty(), "diagonal tower beams have matching rotated collision")
	geometry.queue_free()
	await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(false)
	await key(KEY_ESCAPE)
	check(game.menu is PauseMenu and game.paused and not game.menu_was_paused, "Escape opens a real pause menu and remembers running entry state")
	await capture("pause-menu")
	game._show_save_menu()
	await process_frame
	check(game.menu is SaveMenu and game.menu.list.item_count >= 1 and game.paused, "pause menu opens save management with the existing world")
	var menu: SaveMenu = game.menu
	menu.name_field.text = "UI另存世界"
	menu.library.duplicate_current(menu.current, menu.name_field.text)
	menu.refresh()
	check(menu.list.item_count == 2, "save list refreshes after another world copy")
	await capture("save-management")
	menu.name_field.grab_focus()
	await key(KEY_ESCAPE)
	check(game.menu is PauseMenu and game.paused, "Escape returns from the focused save editor to pause menu")
	await key(KEY_ESCAPE)
	check(game.menu == null and not game.paused, "Escape closes pause menu and restores prior flight state")
	await key(KEY_ESCAPE)
	game.save_library.writable = false
	game.menu.quit_requested.emit()
	check(game.menu is PauseMenu and not game.menu.feedback.text.is_empty(), "failed save-and-exit keeps the game open with an error message")
	game.save_library.writable = true
	await key(KEY_ESCAPE)
	game._set_paused(true)
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE)
	check(game.paused, "Escape menu preserves a deliberately paused entry state")
	game._show_save_menu()
	menu = game.menu
	menu.name_field.text = "UI新世界"
	menu.seed_field.value = -2468
	menu.new_world()
	await game._wait_for_world()
	check(game.menu == null and game.paused and game.store.data.seed == -2468 and game.streamer.generator.seed_value == -2468 and game.missions.store == game.store, "actual new-world UI switches physics, streaming, tasks and save state together")
	game._show_save_menu()
	menu = game.menu
	for index in menu.rows.size():
		if menu.rows[index].id == "legacy":
			menu._select(index)
	menu.load_selected()
	await game._wait_for_world()
	check(game.store.data.seed == 271828 and game.streamer.generator.seed_value == 271828 and game.missions.store == game.store and game.paused, "actual load UI restores the previous world and its scene services")
	if DisplayServer.get_name() != "headless":
		await game._capture()
		check(game.photo_notice.remaining > 0 and game.photo_notice.image_path.is_absolute_path() and FileAccess.file_exists(game.photo_notice.image_path) and game.photo_notice.path_label.text == game.photo_notice.image_path, "successful real photo displays its complete existing file path")
		await capture("photo-path")
		game.photo_notice.remaining = 0
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.current = true
		for kind: String in ["pyramid", "twin_towers", "radio_tower", "courtyard", "sky_colonnade", "turbines"]:
			var preview := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": Architecture.build(kind, "preview/" + kind, Vector3.ZERO)}, Vector3.ZERO)
			game.add_child(preview)
			preview.position = Vector3(0, 150, 0) - game.streamer.origin_offset
			var size: Vector3 = Architecture.TYPES[kind].size
			var distance := maxf(maxf(size.x, size.y), size.z)
			camera.position = preview.position + Vector3(distance * 1.1, size.y * 0.65 + 10, distance * 1.4)
			camera.look_at(preview.position + Vector3.UP * size.y * 0.38)
			await process_frame
			await capture("building-" + kind)
			preview.queue_free()
		camera.queue_free()
	game.queue_free()
	await process_frame
	print("EXPLORATION_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
