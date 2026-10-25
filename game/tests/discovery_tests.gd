extends SceneTree
var failed := 0
var checked := 0
class ResumeGame extends "res://scripts/main.gd":
	var profile_path: String
	func _create_progress_store() -> ProgressStore:
		return ProgressStore.new(catalog, profile_path)

var directory := "user://tests/discovery_" + str(Time.get_ticks_usec())
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1
func write_json(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
func click(control: Control) -> void:
	var scroll := control.get_parent().get_parent()
	if scroll is ScrollContainer:
		scroll.ensure_control_visible(control)
		await process_frame
		await process_frame
	await click_point(control.get_global_transform_with_canvas() * (control.size * 0.5))
func click_point(point: Vector2) -> void:
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
func capture(title: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := "res://../.local/test-results/discovery"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			folder = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder.path_join(title + ".png")) == OK, "capture " + title)
func run() -> void:
	var catalog := ContentCatalog.new()
	var store := ProgressStore.new(catalog, directory.path_join("world/progress.json"))
	var world := store.regions as BiomeWorld
	var nav := MapNavigation.new(4)
	var exploration := WorldExploration.new(store, nav)
	nav.teleport_resolver = store.portal_unlocked
	exploration.refresh(Vector2i.ZERO)
	check(exploration.biomes.is_empty() and nav.locations.is_empty(), "unvisited world reveals neither geography nor objectives")
	var home := world.instance_at(world.spawn_point())
	check(exploration.visit(world.spawn_point()).ok and exploration.biomes.size() == 1, "visiting reveals exactly the current surface biome")
	check(store.data.exploration.mapped.has(home.id) and not store.data.exploration.portals.has(home.stations[0].id), "discovery does not unlock a platform for teleport")
	check(nav.teleport_location(home.stations[0].id) == null, "visible but unregistered platform cannot teleport")
	var far := world.plan("surface", Vector2i(20, -17))
	exploration.visit(far.stations[0].point)
	exploration.refresh(Vector2i(-40, 30))
	check(exploration.biomes.size() == 2 and nav.find_location(home.stations[0].id) != null and nav.find_location(far.stations[0].id) != null, "all explored maps persist beyond the old nine-page window")
	var maze: Dictionary = {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			var candidate := world.plan("maze", Vector2i(x, z))
			if not candidate.is_empty() and maze.is_empty() and not world.map_task(candidate).is_empty():
				maze = candidate
	var task := store.mission_definition(world.map_task(maze))
	exploration.visit(maze.stations[0].point)
	check(store.data.exploration.visited.has(maze.id) and not store.data.exploration.mapped.has(maze.id), "entering special biome records visit but keeps its map locked")
	check(nav.find_location(task.location_id) != null and exploration.biomes.size() == 2, "unmapped special biome exposes its unlock objective without internal map")
	store.accept_mission(task.id)
	store.writable = false
	var evidence := {"point": task.target_point, "speed": 0.0, "seconds": task.hold_seconds}
	check(not store.complete_mission(task.id, evidence).ok and not store.data.exploration.mapped.has(maze.id), "failed completion cannot reveal special map or issue rewards")
	store.writable = true
	if task.kind in ["circuit", "courier"]:
		for point in task.checkpoints:
			store.advance_mission(task.id, point, 0, true)
	check(store.complete_mission(task.id, evidence).ok and store.data.exploration.mapped.has(maze.id), "designated task atomically unlocks the special biome map")
	var reward: int = store.data.credits
	store.complete_mission(task.id, evidence)
	check(store.data.credits == reward, "map unlock mission cannot duplicate its reward")
	exploration.refresh(Vector2i.ZERO)
	check(exploration.biomes.size() == 3, "completed special map joins all permanently revealed maps")
	store.writable = false
	check(not store.unlock_portal(home.stations[0].id).ok and nav.teleport_location(home.stations[0].id) == null, "failed platform save does not expose teleport")
	store.writable = true
	check(store.unlock_portal(home.stations[0].id).ok and nav.teleport_location(home.stations[0].id) != null, "registered platform enables teleport independently of map discovery")
	var reload := ProgressStore.new(catalog, store.path)
	check(reload.data.exploration == store.data.exploration, "map visits, special unlocks and platform registration survive restart")
	check(not store.unlock_portal("v4:surface:999:999:forged").ok, "nonexistent platform cannot be registered")
	# Keep real calibration, auxiliary switches and flight tuning across reset/upgrade.
	var profile := {"name": "persistent RC", "guid": "test-guid", "axes": {}, "auxiliary": []}
	for index in 4:
		profile.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": 0.0, "invert": index == 3, "deadzone": 0.02}
	profile.auxiliary.append({"id": "aux_4", "name": "暂停", "type": "two_position", "source": "axis", "axis": 4, "min": -1.0, "max": 1.0, "invert": false, "bindings": {"0": "pause", "1": "resume"}})
	var settings := {"radio_profiles": {"test-guid|persistent RC": profile}, "active_radio_profile": "test-guid|persistent RC", "radio_active": true, "flight": FlightTuning.defaults()}
	check(FlightInput.valid_profile(profile) and store.save_settings(settings).ok, "valid RC axes and action-switch configuration saves normally")
	store.reset_world(12345)
	check(store.data.settings == settings and store.data.exploration.mapped.is_empty() and store.data.exploration.portals.is_empty(), "new seed clears world discovery but preserves all control settings")
	var legacy := store.data.duplicate(true)
	legacy.world_version = 3
	write_json(store.path, legacy)
	var upgraded := ProgressStore.new(catalog, store.path)
	check(upgraded.data.world_version == 4 and upgraded.data.settings == JSON.parse_string(JSON.stringify(settings)), "automatic old-world rebuild preserves calibration instead of erasing it")
	var empty := upgraded._new_profile()
	write_json(store.path, empty)
	var recovered := ProgressStore.new(catalog, store.path)
	check(recovered.data.settings == JSON.parse_string(JSON.stringify(settings)), "independent controls copy restores profiles after world profile replacement")
	var backup_path := directory.path_join("backup-only/progress.json")
	write_json(backup_path, empty)
	write_json(backup_path + ".backup", legacy)
	var backup_recovered := ProgressStore.new(catalog, backup_path)
	check(backup_recovered.data.settings == JSON.parse_string(JSON.stringify(settings)), "existing old profile backup can recover calibration lost in a previous rebuild")
	# Swept navigation: high speed, off-centre turns, altitude and wall separation.
	var route_nav := MapNavigation.new(4)
	var location := MapLocation.new()
	location.id = "test"
	location.point = Vector3(32, 8.5, 16)
	location.layer = "maze"
	route_nav.locations.append(location)
	route_nav.route_resolver = func(_from: Vector3, _to: MapLocation): return PackedVector3Array([Vector3(0, 8.5, 0), Vector3(16, 8.5, 0), Vector3(16, 8.5, 16), location.point])
	route_nav.select(location.id, Vector3(-12, 4, 5))
	route_nav.update(Vector3(10, 4, 5))
	check(route_nav.route_index >= 1, "swept off-centre flight passes a waypoint between rendered frames")
	route_nav.update(Vector3(16, 4, 11))
	check(route_nav.route_index >= 2, "corridor turns tolerate flight below the reference centreline")
	route_nav.select(location.id, Vector3(-12, 8.5, 16))
	route_nav.update(Vector3(12, 8.5, 16))
	check(route_nav.route_index == 0, "parallel corridor behind a wall cannot satisfy the waypoint")
	route_nav.select(location.id, Vector3(-12, 0.5, 0))
	route_nav.update(Vector3(12, 0.5, 0))
	check(route_nav.route_index >= 1, "low flight near maze floor still reaches corridor guidance")
	route_nav.select(location.id, Vector3(-12, 35, 0))
	route_nav.update(Vector3(12, 35, 0))
	check(route_nav.route_index == 0, "matching XZ at another altitude cannot skip a shaft waypoint")
	route_nav.select(location.id, Vector3(-100, 8.5, 0))
	route_nav.update(Vector3(100, 8.5, 0))
	check(route_nav.route_index == 0, "large discontinuous reposition does not sweep unseen waypoints")
	# Resume a real platform even when its special map and teleport are still locked.
	var resume_path := directory.path_join("resume/progress.json")
	var resume_data := store._new_profile()
	var resume_point: Vector3 = maze.stations[0].point
	resume_data.deployment = [resume_point.x, resume_point.y, resume_point.z]
	write_json(resume_path, resume_data)
	var resumed := ResumeGame.new()
	resumed.profile_path = resume_path
	root.add_child(resumed)
	await resumed._wait_for_world()
	check(resumed.spawn_world.is_equal_approx(resume_point) and not resumed.store.portal_unlocked(maze.stations[0].id), "resume uses the saved physical platform without bypassing its map or teleport locks")
	resumed.queue_free()
	await process_frame
	# Production UI and physical docking.
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await game._wait_for_world()
	for x in range(-2, 3):
		game.store.visit_region(game.store.regions.plan("surface", Vector2i(x, 0)).id)
	var distant_plan: Dictionary = game.store.regions.plan("surface", Vector2i(20, -17))
	game.store.visit_region(distant_plan.id)
	game.exploration.refresh(Vector2i.ZERO)
	game.navigation.select(distant_plan.missions[0].location_id, game._world_position())
	game._show_missions()
	await process_frame
	await process_frame
	var view: RegionMap = game.menu
	check(view != null and view.task_filter.selected == 0 and view.rows.size() <= 8, "F3 opens unified map with at most eight nearby task rows")
	var sorted := true
	for index in range(1, view.ordered.size()):
		sorted = sorted and view.drone_point.distance_to(game.missions.objective_point(view.ordered[index - 1])) <= view.drone_point.distance_to(game.missions.objective_point(view.ordered[index])) + 0.01
	check(sorted and view.selected_id == view.ordered[0].id, "nearest task is selected first and all rows follow real 3D distance")
	var first: MissionDefinition = view.ordered[0]
	await click(view.rows[first.id])
	check(game.navigation.selected_id == distant_plan.missions[0].location_id and view.viewed_id == first.location_id and view.selected_id == first.id and view.info_panel.visible, "task row only changes viewed details and preserves previous route")
	await capture("unified-task-map")
	check(view.map_canvas.map_scale >= 0.5, "nearest task opens at readable local zoom despite distant explored regions")
	for button: Node in view.find_children("*", "Button", true, false):
		if button.text == "全部已解锁":
			await click(button)
	check(Rect2(Vector2.ZERO, view.map_canvas.size - Vector2(300, 0)).has_point(view.map_canvas.project(distant_plan.stations[0].point)), "all-explored control fits distant unlocked geography into the same map")
	await capture("explored-overview")
	await click(view.accept_button)
	check(game.store.mission_status(first.id) == "active" and game.store.data.tracked_mission == first.id, "unified detail acceptance starts exactly the selected task")
	view.task_filter.select(2)
	view.task_filter.item_selected.emit(2)
	var second: MissionDefinition = view.ordered[mini(1, view.ordered.size() - 1)]
	var second_point: Vector3 = game.navigation.find_location(second.location_id).point
	view.map_canvas.center_world = Vector2(second_point.x, second_point.z)
	view.map_canvas.map_scale = 1.5
	await process_frame
	await click_point(view.map_canvas.get_global_transform_with_canvas() * view.map_canvas.project(second_point))
	check(view.selected_id == second.id and game.navigation.selected_id == first.location_id and view.viewed_id == second.location_id and view.rows.has(second.id), "real map icon reveals row while retaining explicitly accepted task route")
	await click(view.collapse_button)
	check(not view.task_sidebar.visible and view.map_canvas.visible, "task list collapses without closing the map")
	await capture("collapsed-task-map")
	await click(view.collapse_button)
	var station: Dictionary = game.store.regions.instance_at(game.spawn_world).stations[0]
	view._select(station.id)
	check(view.teleport_button.disabled and view.details.text.contains("尚未登记") and view.selected_id.is_empty(), "unregistered portal uses portal-specific details with disabled teleport")
	check(not game._teleport_to(station.id), "composition root rejects an unregistered teleport even if UI is bypassed")
	await capture("locked-portal")
	game._close_menu()
	game._deploy(station.point)
	await game._wait_for_world()
	game._show_workshop()
	check(not game.store.portal_unlocked(station.id), "hovering at deployment height cannot register a portal")
	game._set_paused(false)
	await create_timer(1.0).timeout
	game._set_paused(true)
	game._perform_action("interact")
	check(game.menu is Workshop and game.store.portal_unlocked(station.id), "real landing and interaction atomically register a platform and open service")
	game._close_menu()
	game._show_map()
	await process_frame
	view = game.menu
	view._select(station.id)
	check(not view.teleport_button.disabled and view.details.text.contains("已登记"), "registered portal details enable teleport")
	await capture("unlocked-portal")
	check(game._teleport_to(station.id), "registered portal passes production teleport gate")
	game.store.save_settings(settings)
	game._show_radio()
	var saved_profile_visible: bool = game.menu is RadioMenu and game.menu.profile_select.get_item_text(0).contains("persistent RC") and not game.menu.edit_button.disabled
	check(saved_profile_visible, "saved RC profile remains editable without a matching connected device")
	check(game.menu.keys.size() == 1 and game.menu.profile_select.item_count == 1 and game.menu.device_select.item_count >= 1, "saved profiles and input devices use independent compact dropdowns")
	await capture("saved-radio-profiles")
	game.queue_free()
	await process_frame
	print("DISCOVERY_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
