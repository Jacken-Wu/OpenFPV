extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/mission-replay"
var examples: Dictionary = {}

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	failed += int(not value)

func finish(store: ProgressStore, mission: MissionDefinition) -> Dictionary:
	var evidence := {"point": mission.target_point, "speed": 0.0, "seconds": mission.hold_seconds}
	if mission.kind in FlightChallengeRules.KINDS:
		var state: Dictionary = store.data.assignments[mission.id].duplicate(true)
		match mission.kind:
			"race": state.stage = mission.checkpoints.size()
			"balloons":
				state.started = true
				state.hits = range(mission.checkpoints.size())
				state.elapsed = FlightChallengeRules.balloon_release_time(mission, mission.checkpoints.size() - 1) + 0.1
			"orbit": state.orbit = TAU
			"follow":
				state.elapsed = mission.challenge.duration
				state.visible_time = state.elapsed
				state.near_time = state.elapsed
		var saved := store.save_challenge_state(mission.id, state)
		if not saved.ok:
			return saved
	elif mission.kind in ["circuit", "courier"]:
		for point: Vector3 in mission.checkpoints:
			var step := store.advance_mission(mission.id, point, 0, true)
			if not step.ok:
				return step
	elif mission.kind == "photo":
		var path := store.path.get_base_dir().path_join("evidence.png")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(Color.SKY_BLUE)
		image.save_png(path)
		var file := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"mission_id": mission.id, "photo_check": {"ok": true, "distance": (mission.min_distance + mission.max_distance) * 0.5, "angle": 0}}))
		file.close()
		evidence.photo_path = path
	return store.complete_mission(mission.id, evidence)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	var store := ProgressStore.new(catalog, "user://tests/replay_%d/progress.json" % Time.get_ticks_usec())
	for x in range(-3, 4):
		for z in range(-3, 4):
			if examples.size() == 9:
				break
			var plan: Dictionary = store.regions.plan("surface", Vector2i(x, z))
			for mission: MissionDefinition in plan.missions + plan.legacy_missions:
				examples[mission.kind] = mission
	check(examples.size() == 9, "all nine generated task kinds are covered including legacy circuit")
	var tasks: Array = examples.values()
	tasks.append_array(catalog.manifest.missions)
	for mission: MissionDefinition in tasks:
		check(store.accept_mission(mission.id).ok, "first acceptance " + mission.id)
		var before: int = store.data.credits
		check(finish(store, mission).ok and store.data.credits == before + catalog.entries[mission.reward_id].credits, "first completion alone pays " + mission.kind)
		var credited: int = store.data.credits
		var owned: Array = store.data.owned.duplicate()
		var transactions: Array = store.data.transactions.duplicate()
		var count: int = AchievementBook.counts(store.data, catalog).missions
		var snapshot: Dictionary = store.data.duplicate(true)
		store.writable = false
		check(not store.accept_mission(mission.id).ok and store.data == snapshot, "failed replay acceptance is atomic " + mission.kind)
		store.writable = true
		var nav := MapNavigation.new(4)
		var controller := MissionController.new(catalog, store, nav)
		controller.challenge_id = mission.id
		controller.runtime_state = {"status": "active", "stage": 99, "orbit": TAU}
		controller.dwell = 99
		check(controller.accept(mission.id, mission.acceptance_point()).ok and controller.runtime_state.is_empty() and controller.dwell == 0 and store.data.assignments[mission.id].get("stage", 0) == 0, "replay starts fresh and clears controller caches " + mission.kind)
		check(AchievementBook.counts(store.data, catalog).missions == count and store.data.credits == credited, "replaying retains historical achievement count without credit " + mission.kind)
		store = ProgressStore.new(catalog, store.path)
		check(store.mission_status(mission.id) == "active" and store.data.tracked_mission == mission.id and store.mission_completed_once(mission.id), "restarted replay stays active despite old reward/facility ledger " + mission.kind)
		if mission.generated:
			check(not store.complete_mission(mission.id).ok, "repeat must meet the same objective requirements " + mission.kind)
		var before_finish: Dictionary = store.data.duplicate(true)
		store.writable = false
		check(not finish(store, mission).ok and store.data == before_finish, "failed repeat progress/completion is atomic " + mission.kind)
		store.writable = true
		check(finish(store, mission).ok and store.mission_status(mission.id) == "completed" and store.data.credits == credited and store.data.owned == owned and store.data.transactions == transactions, "repeat completes without any second grant or ledger growth " + mission.kind)
		check(int(store.data.assignments[mission.id].completion_count) == 2 and store.complete_mission(mission.id).get("duplicate", false), "duplicate finish cannot increase replay count " + mission.kind)
		check(store.accept_mission(mission.id).ok and finish(store, mission).ok and int(store.data.assignments[mission.id].completion_count) == 3 and store.data.credits == credited, "third playthrough also remains free of rewards " + mission.kind)
	# Old snapshots did not have a count; historical completion and reward remain authoritative.
	var legacy: MissionDefinition = catalog.manifest.missions[0]
	store.data.assignments[legacy.id].erase("completion_count")
	store._commit(store.data)
	store = ProgressStore.new(catalog, store.path)
	var cash: int = store.data.credits
	check(store.accept_mission(legacy.id).ok and finish(store, legacy).ok and store.data.credits == cash, "old count-less completion remains replayable without rewards")
	await labels_and_map()
	print("MISSION_REPLAY_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)

func labels_and_map() -> void:
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	var mission: MissionDefinition = game.store.mission_definition(examples.race.id)
	# Labels/map expose the newest layout. Historical definitions are covered above.
	var identity := mission.history_id if not mission.history_id.is_empty() else mission.id
	for candidate in game.missions.local_definitions(mission.acceptance_point()):
		if (candidate.history_id if not candidate.history_id.is_empty() else candidate.id) == identity:
			mission = candidate
			break
	var point := mission.acceptance_point()
	game._debug_teleport(point)
	for frame in 1500:
		await process_frame
		if game.streamer.collision_ready(point):
			break
	game.drone.camera.current = true
	game.drone.camera.global_position = point + Vector3(0, 3, 16) - game.streamer.origin_offset
	game.drone.camera.look_at(point + Vector3.UP * 3 - game.streamer.origin_offset)
	# Keep the paused test camera stable while presenting the exact production labels.
	game.set_process(false)
	for status: String in ["available", "active", "completed"]:
		if status == "active":
			check(game.missions.accept(mission.id, point).ok, "production controller accepts the labelled entry")
		elif status == "completed":
			check(finish(game.store, mission).ok, "production task can become completed while label stays present")
		game.challenge_view.update_at(point, game.streamer.origin_offset, true)
		await process_frame
		game.challenge_view.update_at(point, game.streamer.origin_offset, true)
		var actor: Dictionary = game.challenge_view.actors[mission.id]
		var panel: Node3D = actor.entry
		var material: StandardMaterial3D = panel.get_child(1).material_override
		check(panel.visible and material.albedo_color == MissionChallengeView.ENTRY_COLORS[status] and panel.get_child(0).text.contains({"available": "未接取", "active": "已接取", "completed": "已完成"}[status]), "nearby world billboard has text and distinct background " + status)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(directory.path_join("entry-" + status + ".png")) == OK, "capture real label " + status)
		game.challenge_view.set_labels_visible(false)
		check(not panel.visible, "menu/photo can immediately hide entry label " + status)
		game.challenge_view.update_at(point + Vector3.ONE * 100, game.streamer.origin_offset, true)
		check(not panel.visible, "entry label disappears outside proximity " + status)
	game.set_process(true)
	game.exploration.refresh(RegionalWorld.key_at(point))
	game._show_missions()
	await process_frame
	game.menu._select(mission.location_id)
	game.menu.refresh()
	check(not game.menu.accept_button.disabled and game.menu.accept_button.text.contains("再次") and game.menu.details.text.contains("不再发放"), "production map offers completed replay with explicit no-reward text")
	var panel: RegionMap = game.menu
	panel.task_filter.select(3)
	panel.task_filter.item_selected.emit(3)
	check(panel.rows.has(mission.id) and panel.map_canvas.mission_color(mission.location_id) == Color("91a6c5") and panel.rows[mission.id].get_theme_color("font_color") == panel.map_canvas.mission_color(mission.location_id), "completed map rows and icons share their distinct completion colour")
	panel.task_filter.select(4)
	panel.task_filter.item_selected.emit(4)
	check(not panel.ordered.has(mission) and not panel.map_canvas.mission_filter.has(mission.location_id), "unfinished filter omits tasks with a prior completion")
	panel.task_filter.select(2)
	panel.task_filter.item_selected.emit(2)
	panel._select(mission.location_id)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(directory.path_join("map-completion-colours.png")) == OK, "capture completed map row and icon")
	game.menu.accept_button.pressed.emit()
	check(game.store.mission_status(mission.id) == "active" and game.store.data.tracked_mission == mission.id, "actual map button reaccepts and tracks")
	panel.refresh()
	check(panel.map_canvas.mission_color(mission.location_id) == Color("91a6c5") and panel.rows[mission.id].text.contains("已完成"), "active replay retains its historical completion colour and label")
	game._close_menu()
	finish(game.store, mission)
	game._debug_teleport(point + Vector3.UP * 0.6)
	game.drone.global_basis = Basis.IDENTITY
	game._set_paused(false)
	for frame in 240:
		await physics_frame
		if game._docked_task_id() == mission.id:
			break
	game._set_paused(true)
	game._perform_action("interact")
	check(game.store.mission_status(mission.id) == "active" and game.store.data.assignments[mission.id].get("stage", 0) == 0, "actual E reaccepts completed task from its beginning")
	var state: Dictionary = game.store.data.assignments[mission.id].duplicate(true)
	state.stage = mission.checkpoints.size()
	game.store.writable = false
	check(not game.store.save_challenge_state(mission.id, state).ok and game.store.data.assignments[mission.id].get("stage", 0) == 0, "failed replay checkpoint save preserves previous state")
	game.store.writable = true
	game.queue_free()
	await create_timer(0.2).timeout
