extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/navigation020"
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	game.set_process(false)
	game.set_physics_process(false)
	var hud: NavigationHUD = game.navigation_hud
	var camera: Camera3D = game.drone.camera
	camera.current = true
	hud.camera = camera
	hud.visible = true
	var location := MapLocation.new()
	location.id = "preview_fixture"
	location.layer = "temporary"
	location.display_name = "导航测试"
	game.navigation.locations.append(location)
	game.navigation.selected_id = location.id
	for window_size: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1280, 1024)]:
		root.size = window_size
		await process_frame
		var extent: Vector2 = camera.get_viewport().get_visible_rect().size
		print("NAVIGATION_VIEWPORT " + JSON.stringify({"requested": str(window_size), "window": str(root.size), "visible": str(extent)}))
		check(root.size == window_size, "requested physical window size is applied")
		for uv: Vector2 in [Vector2(0.5, 0.03), Vector2(0.18, 0.08), Vector2(0.85, 0.1), Vector2(0.5, 0.25), Vector2(0.5, 0.95)]:
			var screen := uv * extent
			var target := camera.project_position(screen, 45)
			var state := hud.marker_state(target)
			check(not state.offscreen and Vector2(state.point).distance_to(screen) < 0.02, "inside frustum remains an exact circle, including upper HUD area " + str(window_size) + " " + str(uv))
			var box := hud.label_rect(screen, Vector2(230, 44))
			var clear := true
			for control in hud.avoid_controls:
				if control.is_visible_in_tree(): clear = clear and not box.intersects(control.get_global_rect().grow(6))
			check(clear, "navigation text avoids actual visible panels without moving its target")
			check(not box.intersects(Rect2(screen - Vector2.ONE * 18, Vector2.ONE * 36)), "navigation text also leaves the primary marker unobstructed")
		var above := camera.project_position(Vector2(extent.x * 0.5, -40), 45)
		check(hud.marker_state(above).offscreen, "only truly outside top edge becomes arrow")
		check(hud.marker_state(camera.global_position + camera.global_basis.z * 20).offscreen, "behind camera stays a directional arrow")
		var finite_sweep := true
		for depth: float in [-0.01, -0.000001, 0, 0.000001, 0.01]:
			for offset: Vector3 in [Vector3.ZERO, Vector3(50, 30, 0), Vector3(-50, -30, 0)]:
				var grazing := hud.marker_state(camera.global_transform * (offset + Vector3(0, 0, depth)))
				finite_sweep = finite_sweep and grazing.valid and Vector2(grazing.point).is_finite() and Vector2(grazing.direction).is_finite() and Rect2(Vector2.ZERO, hud.size).has_point(grazing.point)
		check(finite_sweep, "camera-plane crossings and coincident targets never produce invalid canvas vertices")
		check(not hud.marker_state(Vector3(NAN, 0, 0)).valid, "invalid target is discarded before canvas drawing")
		var below: Dictionary = hud.marker_state(camera.global_position + camera.global_basis.z * 20)
		var bottom_text := hud.label_rect(below.point, Vector2(230, 44))
		check(absf(game.bottom_bar.get_global_rect().position.y - bottom_text.end.y - 12) < 0.1, "behind-camera arrow text docks twelve pixels above bottom information panel")
		location.point = camera.global_position + camera.global_basis.z * 20 + game.streamer.origin_offset
		game.navigation.route = PackedVector3Array([location.point])
		hud.queue_redraw()
		await capture("bottom-arrow-%dx%d" % [window_size.x, window_size.y])
		hud.label_anchor = "below"
		var steady := true
		for step in 100:
			var screen := Vector2(extent.x * 0.32 + sin(step * 0.1) * 3, extent.y * 0.55 + sin(step * 0.2) * 20)
			var rect := hud.label_rect(screen, Vector2(230 + step % 3, 44))
			steady = steady and hud.label_anchor == "below" and absf(rect.position.y - screen.y - 28) < 0.1
		check(steady, "moving camera and changing distance digits retain a clear text side without vertical flips")
		location.point = camera.project_position(extent * Vector2(0.18, 0.08), 45) + game.streamer.origin_offset
		game.navigation.route = PackedVector3Array([location.point])
		hud.origin_offset = game.streamer.origin_offset
		hud.queue_redraw()
		await capture("top-target-%dx%d" % [window_size.x, window_size.y])
	var world: BiomeWorld = game.store.regions
	var maze: Dictionary = {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			if maze.is_empty(): maze = world.plan("maze", Vector2i(x, z))
	check(not maze.is_empty(), "real maze available for preview")
	var route: PackedVector3Array = BiomeStructures.maze_path(maze.shape.maze, 0, maze.shape.maze.doors.size() - 1)
	check(route.size() >= 4, "real maze has multiple upcoming corridor nodes")
	for index in route.size(): route[index].y = float(maze.shape.maze.floor) + 9
	var point := route[0] - (route[1] - route[0]).normalized() * 3
	game._debug_teleport(point)
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if game.streamer.collision_ready(point) and game.streamer.pending.is_empty(): break
	check(game.streamer.collision_ready(point), "production maze collision loaded")
	game.navigation.route = route.duplicate()
	game.navigation.route_index = 0
	game.navigation.corridor_route = true
	game.navigation.arrived = false
	camera = Camera3D.new()
	game.add_child(camera)
	camera.global_position = point + Vector3.UP * 0.3 - game.streamer.origin_offset
	camera.look_at(route[1] - game.streamer.origin_offset)
	camera.current = true
	hud.camera = camera
	hud.drone_point = point
	hud.origin_offset = game.streamer.origin_offset
	location.point = route[-1]
	game.navigation_preview.update_route(game.navigation, point, game.streamer.origin_offset, camera, true)
	check(game.navigation_preview.visible and game.navigation_preview.lines.filter(func(line: MeshInstance3D): return line.visible).size() >= 2, "maze exposes a bounded thin current/next route before arrival")
	check(game.navigation_preview.markers.size() == 3 and game.navigation.route_index == 0, "future nodes are bounded and do not advance the next target")
	var current := camera.unproject_position(route[0] - game.streamer.origin_offset)
	var separated := true
	for marker: Label3D in game.navigation_preview.markers:
		if marker.visible: separated = separated and current.distance_to(camera.unproject_position(marker.global_position)) > 28
	check(separated, "future markers cannot cover the immediate target")
	hud.queue_redraw()
	await capture("maze-lookahead")
	game.navigation.route_index = 1
	game.navigation_preview.update_route(game.navigation, point, game.streamer.origin_offset, camera, true)
	check(game.navigation_preview.position.is_equal_approx(route[1] - game.streamer.origin_offset), "preview advances with the actual route index")
	game.navigation_preview.update_route(game.navigation, point, game.streamer.origin_offset + Vector3(64, 0, 64), camera, true)
	check(game.navigation_preview.position.is_equal_approx(route[1] - game.streamer.origin_offset - Vector3(64, 0, 64)), "preview rebases with floating origin")
	game.navigation_preview.update_route(game.navigation, point, game.streamer.origin_offset, camera, false)
	check(not game.navigation_preview.visible, "menus/photos hide all corridor preview geometry")
	game.queue_free()
	await create_timer(0.2).timeout
	print("NAVIGATION_PREVIEW_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
