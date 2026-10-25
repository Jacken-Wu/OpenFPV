extends SceneTree
var game
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/expansion-tour"
var examples := {}
var samples: Array[float] = []
var screenshots := {}
var last_us := 0
var measuring := false
var peak_nodes := 0
var peak_memory := 0.0

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)

func _process(_delta: float) -> bool:
	if measuring:
		var now := Time.get_ticks_usec()
		samples.append((now - last_us) / 1000.0)
		last_us = now
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		peak_memory = maxf(peak_memory, Performance.get_monitor(Performance.MEMORY_STATIC))
	return false

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	check(game.store.feedback.is_connected(game._on_feedback) and game.store.unlocked.is_connected(game._on_unlocked), "production store routes committed events to the new audio player")
	var world: BiomeWorld = game.store.regions
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			if site.biome.parameters.get("extension", false) and not examples.has(site.biome.parameters.terrain_style):
				examples[site.biome.parameters.terrain_style] = site
	last_us = Time.get_ticks_usec()
	measuring = true
	var started := Time.get_ticks_msec()
	var camera := Camera3D.new()
	camera.fov = 75
	camera.far = 2500
	game.add_child(camera)
	camera.current = true
	for kind: String in examples:
		var site: Dictionary = examples[kind]
		var plan := world.plan("surface", site.key)
		var point: Vector3 = plan.stations[0].point + Vector3.UP * 10
		game._debug_teleport(point)
		var timeout := Time.get_ticks_msec() + 18000
		while Time.get_ticks_msec() < timeout:
			await process_frame
			camera.global_position = point + Vector3(110, 130, 125) - game.streamer.origin_offset
			camera.look_at(point - game.streamer.origin_offset)
			if game.streamer.last_key == WorldGenerator.key_at(point) and game.streamer.collision_ready(point) and game.streamer.active.size() >= game.streamer.desired.size() and game.streamer.pending.is_empty():
				break
		check(game.streamer.collision_ready(point) and game.streamer.active.size() >= game.streamer.desired.size(), "all streamed terrain and collisions load in production " + kind)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join("world-" + kind + ".png"))
		screenshots[kind] = {"point": [point.x, point.y, point.z], "active": game.streamer.active.size(), "desired": game.streamer.desired.size(), "pending": game.streamer.pending.size()}
		print("TOUR_PROGRESS ", kind, " seconds=", (Time.get_ticks_msec() - started) / 1000.0)
	# Keep a comparable 120-second wall-clock observation after the first cold
	# crossings. Repeated locations still exercise native chunk destruction/upload.
	var keys: Array = examples.keys()
	var next_move := Time.get_ticks_msec()
	var index := 0
	while Time.get_ticks_msec() - started < 120000:
		await process_frame
		if Time.get_ticks_msec() >= next_move:
			var site: Dictionary = examples[keys[index % keys.size()]]
			var point: Vector3 = world.plan("surface", site.key).stations[0].point + Vector3.UP * 10
			game._debug_teleport(point)
			index += 1
			next_move = Time.get_ticks_msec() + 6000
		camera.global_position = game._world_position() + Vector3(70, 65, 90) - game.streamer.origin_offset
		camera.look_at(game.drone.global_position)
	measuring = false
	samples.sort()
	check(samples.size() > 1000 and screenshots.size() == 8, "normal 1080p tour covers every extension and records frame intervals")
	var file := FileAccess.open(directory.path_join("tour.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"content_version": "0.18.0", "seconds": (Time.get_ticks_msec() - started) / 1000.0, "frames": samples.size(), "p50_ms": samples[int(samples.size() * 0.5)], "p95_ms": samples[int(samples.size() * 0.95)], "p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples.back(), "peak_memory_mb": peak_memory / 1048576, "peak_nodes": peak_nodes, "renderer": RenderingServer.get_video_adapter_name(), "resolution": "1920x1080", "worlds": screenshots, "checks": checked, "failures": failed, "scope": "cold production streaming of eight extension biomes, repeated chunk loading; scripted camera, not human RC flight or stable-60fps acceptance"}, "\t"))
	game.queue_free()
	await create_timer(0.3).timeout
	print("EXPANSION_TOUR_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
