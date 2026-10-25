extends SceneTree
var directory := "res://../.local/test-results/regional017-visual"
var game
var failed := 0
var checked := 0
var only := ""
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, title: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", title)
func capture(name_value: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.size = Vector2i(1920, 1080)
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	var world: BiomeWorld = game.store.regions
	var examples := {}
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			var style: String = site.biome.parameters.get("terrain_style", "")
			if not style.is_empty() and not examples.has(style): examples[style] = site
	var camera := Camera3D.new()
	camera.fov = 80
	camera.far = 1800
	game.add_child(camera)
	camera.current = true
	for style: String in ["ruined_city", "monument", "gobi", "snow_peak", "alpine", "ravine", "volcano"]:
		if not only.is_empty() and style != only: continue
		var plan := world.plan("surface", examples[style].key)
		var anchor: Vector2 = examples[style].anchor
		var sampler := BiomeTerrain.new(world.field, anchor)
		var point := Vector3(anchor.x, sampler.sample(anchor.x, anchor.y) + 20, anchor.y)
		if style == "monument": point.y = float(plan.megabase) + 80
		game._debug_teleport(point)
		var timeout := Time.get_ticks_msec() + 25000
		while Time.get_ticks_msec() < timeout:
			await process_frame
			camera.global_position = point + Vector3(140, 145, 160) - game.streamer.origin_offset
			camera.look_at(point - game.streamer.origin_offset)
			if game.streamer.last_key == WorldGenerator.key_at(point) and game.streamer.active.size() >= game.streamer.desired.size() and game.streamer.pending.is_empty(): break
		check(game.streamer.collision_ready(point) and game.streamer.active.size() >= game.streamer.desired.size(), style + " complete production streaming")
		await capture(style + "-overview")
		for angle in 3:
			camera.global_position = point + Vector3(cos(angle * TAU / 3) * 90, 40, sin(angle * TAU / 3) * 90) - game.streamer.origin_offset
			camera.look_at(point - game.streamer.origin_offset)
			await capture(style + "-angle%d" % angle)
		if not plan.caves.is_empty():
			var cave: Dictionary = plan.caves[0]
			var axis: Vector3 = (cave.b - cave.a).normalized()
			camera.global_position = cave.a - axis * 22 + Vector3.UP * 4 - game.streamer.origin_offset
			camera.look_at(cave.a + axis * 12 - game.streamer.origin_offset)
			await capture(style + "-cave-mouth")
			var inside: Vector3 = cave.paths[0][3]
			game._debug_teleport(inside)
			var cave_timeout := Time.get_ticks_msec() + 18000
			while Time.get_ticks_msec() < cave_timeout:
				await process_frame
				if game.streamer.last_key == WorldGenerator.key_at(inside) and game.streamer.collision_ready(inside): break
			check(game.streamer.collision_ready(inside), style + " cave collision streamed")
			camera.global_position = inside - game.streamer.origin_offset
			camera.look_at(inside + axis * 20 - game.streamer.origin_offset)
			await capture(style + "-inside-cave")
		print("VISUAL_PROGRESS ", style)
		if style == "ruined_city":
			var station: Dictionary = plan.stations[0]
			game._deploy(station.point)
			await game._wait_for_world()
			game._set_paused(false)
			await create_timer(1.2).timeout
			game._set_paused(true)
			game._show_workshop()
			check(game.menu == null and not game.store.portal_unlocked(station.id) and game.last_notice.contains("修复线路"), "offline ruined portal blocks service page and explains required repairs")
			await capture("ruined-offline-guidance")
			game._close_menu()
	game.queue_free()
	await create_timer(0.3).timeout
	print("REGIONAL_VISUAL_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
