extends SceneTree
var directory := ""
class ProfileMain extends "res://scripts/main.gd":
	var frame_cpu_ms := 0.0
	var interaction_ms := 0.0
	func _process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		super._process(delta)
		frame_cpu_ms = (Time.get_ticks_usec() - started) / 1000.0
	func _interactions(delta: float, point: Vector3) -> bool:
		var started := Time.get_ticks_usec()
		var result := super._interactions(delta, point)
		interaction_ms = (Time.get_ticks_usec() - started) / 1000.0
		return result
var seconds := 45.0
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
	if directory.is_empty(): directory = ProjectSettings.globalize_path("user://tests/streaming-tour-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	root.mode = Window.MODE_MAXIMIZED
	var game = ProfileMain.new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	var initial: Vector3 = game._world_position() + Vector3.UP * 65
	game.drone.position = initial - game.streamer.origin_offset
	game.streamer.focus = initial
	await create_timer(2).timeout
	var samples: Array[float] = []
	var stalls: Array[Dictionary] = []
	var previous := Time.get_ticks_usec()
	var began := previous
	var peak_commit := 0.0
	var missing := 0
	var last_capture := -1
	while float(Time.get_ticks_usec() - began) / 1000000 < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - previous) / 1000.0
		previous = now
		var elapsed := float(now - began) / 1000000
		var point := initial + Vector3(elapsed * 38, 0, sin(elapsed * 0.13) * 100)
		game.drone.position = point - game.streamer.origin_offset
		var tilt := deg_to_rad(float(game.drone.spec.camera_tilt))
		game.drone.rotation = Vector3(-0.32 - tilt, -1.3 + sin(elapsed * 0.21) * 0.25, 0)
		game.drone.camera.rotation = Vector3(tilt, 0, 0)
		peak_commit = maxf(peak_commit, game.streamer.last_commit_ms)
		missing += int(not game.streamer.collision_ready(point))
		samples.append(ms)
		if ms > 25: stalls.append({"s": elapsed, "ms": ms, "main_ms": game.frame_cpu_ms, "interactions_ms": game.interaction_ms, "commit_ms": game.streamer.last_commit_ms, "active": game.streamer.active.size(), "pending": game.streamer.pending.size()})
		if "--screenshots" in OS.get_cmdline_user_args() and int(elapsed / 10) != last_capture:
			last_capture = int(elapsed / 10)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("crossing%d.png" % last_capture))
	var report := {"seconds": float(Time.get_ticks_usec() - began) / 1000000, "frames": samples.size(), "over25": stalls.size(), "peak_commit_ms": peak_commit, "collision_wait_frames": missing, "stalls": stalls, "window": str(root.size), "renderer": RenderingServer.get_video_adapter_name(), "rendering_method": RenderingServer.get_current_rendering_method(), "initial": [initial.x, initial.y, initial.z], "speed": 38, "camera": "mounted FPV camera; turn whole drone, not camera through own model", "route": "initial + (38*t, 0, 100*sin(0.13*t))"}
	samples.sort()
	report.p50 = samples[int(samples.size() * 0.5)]
	report.p95 = samples[int(samples.size() * 0.95)]
	report.p99 = samples[int(samples.size() * 0.99)]
	report.max_ms = samples.back()
	var file := FileAccess.open(directory.path_join("crossing.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.queue_free()
	await create_timer(0.3).timeout
	print("STREAMING_TOUR_RESULT ", JSON.stringify(report))
	quit()
