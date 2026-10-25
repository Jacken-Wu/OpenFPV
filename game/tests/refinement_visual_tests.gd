extends SceneTree
var game
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/refinement018-visual"
var baseline := false
var camera: Camera3D
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func capture(name_value: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)
func wait_at(point: Vector3) -> void:
	game._debug_teleport(point)
	var timeout := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < timeout:
		await process_frame
		if game.streamer.last_key == WorldGenerator.key_at(point) and game.streamer.active.size() >= game.streamer.desired.size() and game.streamer.pending.is_empty(): break
	check(game.streamer.collision_ready(point), "production collision readiness")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
		if arg == "--baseline": baseline = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	camera = Camera3D.new()
	camera.near = game.drone.camera.near
	camera.far = game.drone.camera.far
	camera.fov = 90
	game.add_child(camera)
	camera.current = true
	var world: BiomeWorld = game.store.regions
	var city: Dictionary = {}
	var examples := {}
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			var style: String = site.biome.parameters.get("terrain_style", "")
			if site.biome.provider_id == "base.generator.modular_city" and abs(x) < 4 and abs(z) < 4 and city.is_empty(): city = site
			if style in ["gobi", "ruined_city", "monument", "snow_peak"] and not examples.has(style): examples[style] = site
	var plan := world.plan("surface", city.key)
	var point: Vector3 = plan.stations[0].point + Vector3(0, 15, 0)
	await wait_at(point)
	for size_value: Vector2i in [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1280, 1024)]:
		root.size = size_value
		await process_frame
		var viewport_size: Vector2 = game.drone.camera.get_viewport().get_visible_rect().size
		var envelope := AABB(-game.drone.collision.shape.size / 2, game.drone.collision.shape.size)
		var protected := true
		for uv: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2.ONE]:
			var corner: Vector3 = game.drone.camera.project_position(uv * viewport_size, game.drone.camera.near)
			protected = protected and envelope.has_point(game.drone.collision.to_local(corner))
		check(protected, "resized FPV projection near-plane corners remain inside the physical collision envelope")
		camera.global_position = point + Vector3(18, 0, 18) - game.streamer.origin_offset
		camera.look_at(point + Vector3(130, 3, 90) - game.streamer.origin_offset)
		await capture("city-%dx%d" % [size_value.x, size_value.y])
		for index in 3:
			camera.position.x += 0.002
			await capture("city-%dx%d-jitter%d" % [size_value.x, size_value.y, index])
	if not baseline:
		root.size = Vector2i(1920, 1080)
		for kind: String in ["ruined_city", "monument", "gobi", "snow_peak"]:
			plan = world.plan("surface", examples[kind].key)
			point = plan.stations[0].point + Vector3.UP * 10
			await wait_at(point)
			camera.global_position = point + Vector3(100, 85, 100) - game.streamer.origin_offset
			camera.look_at(point - game.streamer.origin_offset)
			await capture(kind + "-overview")
			if kind == "ruined_city":
				var station: Dictionary = plan.stations[0]
				game._deploy(station.point)
				await game._wait_for_world()
				game._set_paused(false)
				await create_timer(1.2).timeout
				game._set_paused(true)
				game._perform_action("interact")
				check(game.menu == null and not game.store.portal_unlocked(station.id) and game.last_notice.contains("修复线路"), "landed locked ruined portal shows repair guidance and never opens a service page")
				await capture("ruined-locked-guidance")
				for task: MissionDefinition in plan.missions:
					if task.kind != "regional" or not task.challenge.portal_required: continue
					game.store.accept_mission(task.id)
					var state: Dictionary = game.store.data.assignments[task.id].duplicate(true)
					state.stage = task.checkpoints.size()
					game.store.save_challenge_state(task.id, state)
					game.store.complete_mission(task.id)
				game._perform_action("interact")
				check(game.menu is Workshop and game.store.portal_unlocked(station.id), "three repaired circuits open both teleport and the landed service page")
				game._close_menu()
			if kind in ["monument", "ruined_city"]:
				for task: MissionDefinition in plan.missions:
					if task.kind != "regional": continue
					game.missions.accept(task.id, point)
					point = task.checkpoints[0]
					await wait_at(point + Vector3.UP * 3)
					camera.global_position = point + Vector3(16, 10, 18) - game.streamer.origin_offset
					camera.look_at(point - game.streamer.origin_offset)
					await capture(kind + "-terminal")
					break
			if kind == "gobi":
				for angle in 3:
					camera.global_position = point + Vector3(cos(angle * TAU / 3) * 70, 25, sin(angle * TAU / 3) * 70) - game.streamer.origin_offset
					camera.look_at(point - game.streamer.origin_offset)
					await capture("gobi-lighting-%d" % angle)
			if kind == "snow_peak" and not plan.caves.is_empty():
				var cave: Dictionary = plan.caves[0]
				for index in range(1, 7):
					var path: PackedVector3Array = cave.paths[1 if index > 3 else 0]
					var p: Vector3 = path[mini(index if index < 4 else index - 3, path.size() - 2)]
					await wait_at(p)
					camera.global_position = p - game.streamer.origin_offset
					camera.look_at(path[mini((index if index < 4 else index - 3) + 1, path.size() - 1)] - game.streamer.origin_offset)
					await capture("cave-junction-%d" % index)
	game.queue_free()
	await create_timer(0.3).timeout
	print("REFINEMENT_VISUAL_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
