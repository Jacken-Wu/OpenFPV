extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/follow-live"
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	game.set_process(false)
	var mission: MissionDefinition
	for task: MissionDefinition in game.store.regions.plan("surface", Vector2i(-3, 3)).missions:
		if task.kind == "follow":
			mission = task
	check(mission != null and game.missions.accept(mission.id, game._world_position()).ok, "production accepts coverage-based follow")
	var target := FlightChallengeRules.follow_point(mission, 0)
	game._debug_teleport(target + Vector3(20, 4, 0))
	for frame in 1800:
		await process_frame
		if game.streamer.collision_ready(target + Vector3(20, 4, 0)):
			break
	check(game.streamer.collision_ready(target + Vector3(20, 4, 0)), "actual follow region collision is loaded before filming")
	game.drone.camera.current = true
	var before: int = game.store.data.credits
	var time := 0.0
	var valid_frames := 0
	var frames := 0
	var captured := false
	var started := Time.get_ticks_usec()
	var previous := started
	while time < 32 and game.store.mission_status(mission.id) == "active":
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := clampf((now - previous) / 1000000.0, 0.001, 0.25)
		previous = now
		target = FlightChallengeRules.follow_point(mission, float(game.missions.challenge_state(mission).get("elapsed", 0)) + delta)
		var point := target + Vector3(20, 4, 0)
		game.drone.position = point - game.streamer.origin_offset
		game.streamer.focus = point
		game.drone.camera.look_at(target - game.streamer.origin_offset)
		var view: Dictionary = game._challenge_camera(delta)
		valid_frames += int(view.get("in_view", false) and view.get("clear", false))
		frames += 1
		game.missions.update_objective(point, 10, delta, false, false, view)
		game.challenge_view.update_at(point, game.streamer.origin_offset, true, delta, false)
		time += delta
		if not captured and time > 5:
			game.objective.text = mission.display_name + "\n" + game.missions.objective_hint(mission)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory.path_join("follow-live.png"))
			captured = true
	check(valid_frames > frames * 0.95, "real production camera frustum and physics rays see moving target throughout scripted pursuit")
	check(game.store.mission_status(mission.id) == "completed" and game.store.data.credits == before + game.catalog.entries[mission.reward_id].credits, "thirty-second live take commits completion and first reward")
	check(game.missions.finish(mission.id).get("duplicate", false) and game.store.data.credits == before + game.catalog.entries[mission.reward_id].credits, "duplicate live completion cannot pay again")
	var file := FileAccess.open(directory.path_join("follow-live.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"seconds": time, "frames": frames, "visible_clear_frames": valid_frames, "checks": checked, "failures": failed, "scope": "scripted target-relative motion, actual Main camera and physics occlusion, persisted reward; not human RC flight"}, "\t"))
	game.queue_free()
	await create_timer(0.3).timeout
	print("FOLLOW_LIVE_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
