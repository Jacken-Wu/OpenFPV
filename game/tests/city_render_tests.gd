extends SceneTree
class ReproGame extends "res://scripts/main.gd":
	func _create_progress_store() -> ProgressStore:
		var value := ProgressStore.new(catalog, "user://tests/flash022_%d/progress.json" % Time.get_ticks_usec())
		value.reset_world(1919810)
		return value
var directory := "res://../.local/test-results/city-render022"
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("City rendering diagnostics require a normal window")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.mode = Window.MODE_MAXIMIZED
	var game := ReproGame.new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	var point := Vector3(8705, 46, 576)
	game._debug_teleport(point)
	for frame in 10000:
		await process_frame
		if game.streamer.pending.is_empty() and game.streamer.active.size() >= game.streamer.desired.size(): break
	var plan: Dictionary = game.store.regions.plan("surface", game.store.regions.field.nearest(Vector2(point.x, point.z)).key)
	print("REPRO_SITE ", plan.id, " ", plan.biomes[0].display_name)
	for mission: MissionDefinition in plan.missions:
		if mission.kind == "regional" and mission.challenge.mode == "repair":
			game.store.accept_mission(mission.id)
			game.store.data.assignments[mission.id].stage = 2
			game.store.data.tracked_mission = mission.id
			game.missions.sync_navigation(point)
			break
	var events: Array[Dictionary] = []
	var worst := 0.0
	for frame in 1200:
		await process_frame
		var t := frame / 100.0
		game.drone.position = point + Vector3(sin(t * 0.6) * 120, sin(t) * 16, sin(t * 0.31) * 120) - game.streamer.origin_offset
		game.drone.rotation_degrees = Vector3(-38 + sin(t * 0.8) * 45, 34 + t * 30, 3 + sin(t * 1.6) * 65)
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var tiny := shot.duplicate() as Image
		tiny.resize(256, 136, Image.INTERPOLATE_NEAREST)
		var black := 0
		for y in range(4, 132):
			for x in range(30, 226):
				var pixel := tiny.get_pixel(x, y)
				if maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.008: black += 1
		var ratio := black / 25088.0
		if frame % 300 == 0: print("REPRO_FRAME ", frame, " black=", ratio)
		if ratio > worst:
			worst = ratio
			shot.save_png(directory.path_join("worst.png"))
		if frame == 0: shot.save_png(directory.path_join("start.png"))
		if ratio > 0.15:
			shot.save_png(directory.path_join("flash-%d.png" % frame))
			events.append({"frame": frame, "black": ratio})
	var report := {"frames": 1200, "worst_black": worst, "events": events, "seed": 1919810, "point": [8705, 46, 576], "window": str(root.size), "rendering_method": RenderingServer.get_current_rendering_method(), "scope": "Scripted mounted FPV pose/movement with all HUD layers and repair stage 3. Per-frame GPU readback synchronizes rendering; zero events cannot prove an intermittent presentation/driver issue absent in human flight or recording."}
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.queue_free()
	await create_timer(0.3).timeout
	print("FLASH_DIAGNOSTIC ", JSON.stringify(report))
	print("CITY_RENDER_RESULT failures=%d frames=1200" % events.size())
	quit(1 if not events.is_empty() else 0)
