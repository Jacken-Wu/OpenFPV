extends SceneTree

var failed := 0
var checked := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func click_at(point: Vector2) -> void:
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

func click_control(control: Control) -> void:
	if control.get_parent().get_parent() is ScrollContainer:
		control.get_parent().get_parent().ensure_control_visible(control)
		await process_frame
		await process_frame
	await click_at(control.get_global_transform_with_canvas() * (control.size * 0.5))

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
	var nav := MapNavigation.new()
	var ids: Array[String] = []
	var content_valid := nav.locations.size() == 13
	for location in nav.locations:
		content_valid = content_valid and not ids.has(location.id) and location.point.is_finite() and location.kind in ["teleport", "shop", "mission", "landmark"]
		ids.append(location.id)
	check(content_valid, "map content has unique IDs, finite 3D positions and explicit kinds")
	check(not nav.select("missing", Vector3.ZERO) and nav.selected() == null, "unknown selection is rejected")
	for location in nav.locations:
		check((nav.teleport_location(location.id) != null) == (location.kind == "teleport"), "only explicit teleport kind can deploy: " + location.id)
	check(nav.teleport_location("missing") == null, "unknown teleport rejected")
	check(nav.nearest_teleport(Vector3(18, 1.2, 17)).id == "teleport.harbor", "legacy shop deployment resolves to the nearest actual portal")
	var shared_approach := nav.find_location("landmark.underground").approach.duplicate()
	nav.select("landmark.underground", Vector3.ZERO)
	check(nav.route.size() == 3 and nav.waypoint() == Vector3(-96, 6, -96), "surface to underground route leads through the authored entrance")
	nav.update(Vector3(-96, 45, -96))
	check(nav.route_index == 0 and not nav.arrived, "matching XZ at the wrong altitude cannot complete a 3D waypoint")
	nav.update(Vector3(-96, 6, -96))
	check(nav.route_index == 1 and nav.waypoint().y == -40, "reaching entrance advances to the lower shaft waypoint")
	nav.update(Vector3(-96, -40, -96))
	check(nav.route_index == 2, "shaft descent advances to the maintenance destination")
	nav.update(Vector3(-96, -43, -112))
	check(nav.arrived, "arrival uses full 3D destination distance")
	nav.update(Vector3(-96, -20, -112))
	check(not nav.arrived, "leaving a destination clears arrived state")
	nav.select("landmark.underground", Vector3(-102, -43, -112))
	check(nav.route.size() == 1, "selecting a destination within the same chamber skips the surface detour")
	nav.select("shop.harbor", Vector3(-102, -43, -112))
	check(nav.route.size() == 3 and nav.waypoint() == Vector3(-96, -40, -96) and nav.route[1] == Vector3(-96, 6, -96), "leaving underground reverses the authored approach before heading to shop")
	check(nav.find_location("landmark.underground").approach == shared_approach, "selection and progression never mutate shared map definitions")
	nav.select("landmark.underground", Vector3.ZERO)
	nav.update(Vector3(-96, -43, -112))
	check(nav.arrived and nav.route_index == nav.route.size() - 1, "arriving via another path finishes intermediate guidance too")
	nav.clear()
	check(nav.selected() == null and nav.route.is_empty(), "clear removes target and route together")

	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await game._wait_for_world()
	var sky_plan: Dictionary = {}
	var maze_plan: Dictionary = {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			if sky_plan.is_empty():
				sky_plan = game.store.regions.plan("sky", Vector2i(x, z))
			if maze_plan.is_empty():
				maze_plan = game.store.regions.plan("maze", Vector2i(x, z))
	game.store.visit_region(sky_plan.id)
	game.store.visit_region(maze_plan.id)
	game.store.data.exploration.mapped[maze_plan.id] = true
	game.exploration.refresh(RegionalWorld.key_at(game._world_position()))
	game.store.accept_mission(game.exploration.definitions[0].id)
	game._show_map()
	await process_frame
	await process_frame
	var map_view: RegionMap = game.menu
	var canvas: MapCanvas = map_view.map_canvas
	check(map_view.teleport_button.disabled, "no target means teleport button disabled")
	var point: Vector3 = game._world_position()
	var deployment: Vector3 = game.spawn_world
	var credits: int = game.store.data.credits
	var mission_id: String = map_view.ordered[0].location_id
	var route_before: String = game.navigation.selected_id
	var underground_id: String = maze_plan.stations[0].id
	var sky_id: String = sky_plan.stations[0].id
	var shop_point: Vector3 = game.navigation.find_location(mission_id).point
	canvas.center_world = Vector2(shop_point.x + 130 / canvas.map_scale, shop_point.z)
	await click_at(canvas.get_global_transform_with_canvas() * canvas.project(shop_point))
	check(game.navigation.selected_id == route_before and map_view.viewed_id == mission_id and map_view.teleport_button.disabled, "viewport click only views a mission without changing tracked route")
	check(game._world_position().is_equal_approx(point) and game.spawn_world == deployment and game.store.data.credits == credits, "map selection preserves position, deployment and progress")
	check(not game._teleport_to(mission_id) and not game._teleport_to(mission_id) and not game._teleport_to("missing") and game.spawn_world == deployment, "production teleport gate rejects shop, mission and unknown IDs")
	map_view.teleport_requested.emit(mission_id)
	check(game.menu == map_view and game._world_position().is_equal_approx(point), "forged shop teleport signal is revalidated at the composition root")
	await capture("map-shop")
	await click_control(map_view.location_buttons[mission_id])
	check(game.navigation.selected_id == route_before and map_view.viewed_id == mission_id and not map_view.details.text.is_empty(), "task list only selects a viewed mission")
	var viewed_task: MissionDefinition = game.store.mission_definition(map_view.selected_id)
	game.store.accept_mission(viewed_task.id)
	map_view.refresh()
	await click_control(map_view.track_button)
	check(game.navigation.selected_id == mission_id and game.store.data.tracked_mission == viewed_task.id, "explicit mission track button starts navigation")
	var cursor := Vector2(260, 210)
	var world_before := canvas.unproject(cursor)
	canvas.zoom_at(cursor, 2)
	check(canvas.unproject(cursor).is_equal_approx(world_before), "zoom keeps the world position under the pointer fixed")
	var selected_before: String = game.navigation.selected_id
	var center_before := canvas.center_world
	var start := canvas.get_global_transform_with_canvas() * Vector2(300, 300)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = start
	press.pressed = true
	root.push_input(press, true)
	var drag := InputEventMouseMotion.new()
	drag.position = start + Vector2(80, 40)
	drag.relative = Vector2(80, 40)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	press.position = drag.position
	press.pressed = false
	root.push_input(press, true)
	await process_frame
	check(not canvas.center_world.is_equal_approx(center_before) and game.navigation.selected_id == selected_before, "viewport drag pans the map without selecting another location")
	canvas.fit_all()
	map_view._select(underground_id)
	check(game.navigation.selected_id == mission_id and game.store.data.tracked_mission == viewed_task.id, "browsing a portal preserves tracked mission and route")
	await click_control(map_view.track_button)
	check(game.navigation.selected_id == underground_id and game.store.data.tracked_mission == viewed_task.id, "explicit portal track starts location navigation while retaining accepted task")
	map_view = game.menu
	await capture("map-underground")
	game._close_menu()
	game.store.unlock_portal(sky_id)
	game._show_map()
	await process_frame
	map_view = game.menu
	map_view._select(sky_id)
	map_view = game.menu
	check(not map_view.teleport_button.disabled, "explicit teleport selection enables the action")
	await click_control(map_view.teleport_button)
	check(game.menu == null and game.paused and game.spawn_world == game.navigation.find_location(sky_id).point and game.drone.motion_velocity() == Vector3.ZERO, "actual teleport button deploys at a portal, clears motion and leaves flight paused")
	await game._wait_for_world()
	check(game.streamer.collision_ready(game.spawn_world), "teleport destination streams real collision geometry")
	game.navigation.select(mission_id, game._world_position())
	game._show_map()
	await process_frame
	check(not game.menu.details.text.is_empty() and game.navigation.selected_id == mission_id, "target and highlight survive closing and reopening the map")
	game._show_map()
	await process_frame
	check(game.menu == null and game.navigation_hud.visible, "M toggle closes the map and restores flight guidance")
	game._deploy(game.navigation.find_location(sky_id).point + Vector3(0, 8, 20))
	await game._wait_for_world()
	game.drone.rotation = Vector3.ZERO
	game.navigation.select(mission_id, game._world_position())
	await process_frame
	await capture("navigation-front")
	game.drone.rotation.y = PI
	await process_frame
	await capture("navigation-behind")
	game.drone.camera.look_at(game.navigation.waypoint() - game.streamer.origin_offset)
	await process_frame
	await capture("navigation-highlight")
	game.chase_camera.current = true
	await process_frame
	await capture("navigation-chase")
	check(game.navigation_hud.camera == game.chase_camera, "guidance uses the active third-person camera too")
	var waypoint: Vector3 = game.navigation.waypoint()
	var world_position: Vector3 = game._world_position()
	var shift := Vector3(1152, 0, 0)
	game.streamer.shift_origin(shift)
	game.drone.shift_origin(shift)
	game.features.position -= shift
	await process_frame
	await process_frame
	check(game.navigation.waypoint() == waypoint and game._world_position().is_equal_approx(world_position) and game.navigation_hud.origin_offset == game.streamer.origin_offset, "navigation keeps global targets and local camera projection consistent across origin shifts")
	game._show_map()
	await process_frame
	map_view = game.menu
	game.navigation.clear()
	check(game.navigation.selected_id.is_empty() and game.navigation.route.is_empty() and not map_view.details.text.is_empty(), "clearing guidance leaves viewed information available")
	game.queue_free()
	await process_frame
	print("MAP_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
