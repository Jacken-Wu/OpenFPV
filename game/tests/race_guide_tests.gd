extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/race-guide019"
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func cross(controller: MissionController, task: MissionDefinition, index: int) -> void:
	controller.invalidate_motion()
	var point := task.checkpoints[index]
	var direction := task.gate_normals[index]
	controller.update_objective(point - direction, 1, 0.02, false, false)
	controller.update_objective(point + direction, 1, 0.02, false, false)
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
	var plan: Dictionary = game.store.regions.plan("surface", Vector2i(-3, -3))
	var task: MissionDefinition
	for candidate: MissionDefinition in plan.missions:
		if candidate.kind == "race": task = candidate; break
	check(task != null, "real production city has a directed course")
	if task == null: quit(1); return
	var point := task.checkpoints[0] + Vector3.UP * 5
	game._debug_teleport(point)
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if game.streamer.collision_ready(point) and game.streamer.pending.is_empty() and game.streamer.active.size() >= game.streamer.desired.size(): break
	check(game.streamer.collision_ready(point), "actual course region collision is loaded")
	await physics_frame
	game.set_process(false)
	check(game.missions.accept(task.id, point).ok, "production controller accepts and tracks the course")
	var view: MissionChallengeView = game.challenge_view
	var origin: Vector3 = game.streamer.origin_offset
	view.update_at(point, origin, true)
	var guide: RaceRouteGuide = view.actors[task.id].guide
	check(guide.segments.size() == task.checkpoints.size() and guide.arrow_count > 0, "tracked route connects the approach and all remaining gates with arrows")
	var aligned := true
	for segment: Dictionary in guide.segments:
		aligned = aligned and (guide.to_global(segment.to) + origin).distance_to(task.checkpoints[segment.gate]) < 0.02
	check(aligned and game.store.data.assignments[task.id].get("stage", 0) == 0, "actual guide mesh anchors match gate centres without advancing progress")
	var physical := false
	for child in guide.find_children("*", "CollisionObject3D", true, false): physical = physical or child != null
	check(not physical, "reference line has no physical collision")
	var line: MeshInstance3D = guide.get_child(0)
	check(not line.mesh.material.no_depth_test and line.mesh.material.albedo_color == Color("ffe090"), "current segment is gold and obeys depth occlusion")
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.global_position = point - task.gate_normals[0] * 22 + Vector3.UP * 9 - origin
	camera.look_at(task.checkpoints[1] - origin)
	camera.current = true
	await capture("city-course-start")
	view.update_at(point, origin + Vector3(64, 0, 64), true)
	check((guide.to_global(guide.segments[0].to) + origin + Vector3(64, 0, 64)).distance_to(task.checkpoints[0]) < 0.02, "floating origin keeps the guide aligned")
	view.update_at(point, origin, true)
	view.set_labels_visible(false)
	check(not guide.visible, "menus/photos hide route guidance immediately")
	view.update_at(point, origin, false)
	check(not guide.visible, "hidden update cannot reintroduce the guide")
	view.set_labels_visible(true)
	check(guide.visible, "returning to flight restores route guidance")
	cross(game.missions, task, 0)
	view.update_at(point, origin, true)
	guide = view.actors[task.id].guide
	check(game.store.data.assignments[task.id].stage == 1 and guide.segments.size() == task.checkpoints.size() - 1 and guide.segments[0].gate == 1, "committed crossing removes the finished segment and highlights the next")
	await capture("city-course-next")
	game.missions.track("", point)
	view.update_at(point, origin, true)
	check((not view.actors.has(task.id) or not view.actors[task.id].has("guide")) and game.store.mission_status(task.id) == "active", "stopping tracking removes the line while retaining the accepted mission")
	game.missions.track(task.id, point)
	for index in range(1, task.checkpoints.size()): cross(game.missions, task, index)
	view.update_at(point, origin, true)
	check(game.store.mission_status(task.id) == "completed" and (not view.actors.has(task.id) or not view.actors[task.id].has("guide")), "completed route leaves no stale line")
	var vertical := task.duplicate() as MissionDefinition
	vertical.checkpoints = PackedVector3Array([Vector3(0, 5, 0), Vector3(0, 250, 0), Vector3(220, 250, 0)])
	vertical.gate_normals = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.RIGHT])
	var vertical_guide := RaceRouteGuide.new()
	root.add_child(vertical_guide)
	vertical_guide.configure(vertical, 0)
	check(vertical_guide.arrow_count > 0 and vertical_guide.arrow_count <= 256 and vertical_guide.get_child_count() == 6, "vertical shafts and long legs build finite direction geometry")
	vertical_guide.queue_free()
	game.queue_free()
	await create_timer(0.2).timeout
	print("RACE_GUIDE_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
