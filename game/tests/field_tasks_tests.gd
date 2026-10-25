extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/field-tasks"
var game: Node3D
var geometry: Array[Dictionary] = []
var balloon_geometry: Dictionary = {}
var sample_mission: MissionDefinition
var pop_events := 0
var tested_pads := 0

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	failed += int(not value)

func capture(name_text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_text + ".png")) == OK, "capture " + name_text)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	for seed_value in [271828, 42, 314159]:
		var world := BiomeWorld.new(catalog, seed_value)
		var points: Array[Vector3] = []
		var layers := {"surface": 0, "sky": 0, "maze": 0}
		var valid := true
		for x in range(-3, 4):
			for z in range(-3, 4):
				for kind: String in layers:
					if layers[kind] >= 8:
						continue
					var plan := world.plan(kind, Vector2i(x, z))
					if plan.is_empty():
						continue
					layers[kind] += 1
					valid = valid and plan.missions.size() >= 2 and plan.missions.size() <= 5
					for mission: MissionDefinition in plan.missions:
						valid = valid and not mission.pickup_platform.is_empty()
						if mission.kind == "balloons":
							valid = valid and mission.checkpoints.size() >= 5
						var point := mission.acceptance_point()
						for previous in points:
							if point.distance_to(previous) < MissionSites.MIN_SPACING - 0.01:
								print("PAD_TOO_CLOSE ", seed_value, " ", mission.id, " ", point.distance_to(previous))
								valid = false
						points.append(point)
						tested_pads += 1
						if geometry.filter(func(item: Dictionary): return item.layer == kind).size() < 2 and seed_value == 271828:
							geometry.append({"seed": seed_value, "mission": mission, "layer": kind})
						if sample_mission == null and seed_value == 271828 and kind == "surface" and mission.kind == "balloons":
							sample_mission = mission
						if seed_value == 271828 and mission.kind == "balloons" and not balloon_geometry.has(kind):
							balloon_geometry[kind] = mission
		check(valid, "three-dimensional pads stay separated and all tasks retain reception platforms seed=" + str(seed_value))
		check(layers.surface == 8 and layers.sky == 8 and layers.maze == 8, "eight instances of every layer sampled per seed")
	await pad_collisions(catalog)
	await balloon_clearance(catalog)
	legacy_reception(catalog)
	await production()
	var report := {"checks": checked, "failures": failed, "seeds": [271828, 42, 314159], "instances": 72, "sampled_pads": tested_pads, "minimum_spacing_m": MissionSites.MIN_SPACING, "physical_pads": geometry.size(), "rays_per_physical_pad": 9, "balloon_layers_with_clearance": balloon_geometry.size(), "kind": "generated native collision, actual landing/interaction, balloon state/FX and world-space labels; not human flight"}
	var file := FileAccess.open(directory.path_join("field-tasks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("FIELD_TASKS_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)

func legacy_reception(catalog: ContentCatalog) -> void:
	var store := ProgressStore.new(catalog, "user://tests/field_legacy_%d/progress.json" % Time.get_ticks_usec())
	var current := store.mission_definition(sample_mission.id)
	var old_id := ":".join(sample_mission.id.split(":").slice(0, 6))
	var old := store.mission_definition(old_id)
	var controller := MissionController.new(catalog, store, MapNavigation.new(4))
	check(store.accept_mission(old_id).ok and not store.accept_mission(current.id).ok, "legacy and replacement tasks cannot both be newly accepted at one reception slot")
	var local := controller.local_definitions(current.acceptance_point())
	check(local.filter(func(task: MissionDefinition): return task.acceptance_point().is_equal_approx(current.acceptance_point())).size() == 1 and local.has(old) and controller.available_at(current.acceptance_point()) == null, "active legacy task owns its sign and cannot accidentally accept its replacement")
	var snapshot: Dictionary = store.data.duplicate(true)
	snapshot.assignments[old_id].status = "completed"
	snapshot.assignments[old_id].completion_count = 1
	snapshot.tracked_mission = ""
	store._commit(snapshot)
	controller.invalidate_motion()
	local = controller.local_definitions(current.acceptance_point())
	check(local.has(current) and not local.has(old) and controller.available_at(current.acceptance_point()).id == current.id, "completed historical task does not stack a second sign or mask the current reception")

func pad_collisions(catalog: ContentCatalog) -> void:
	var generator := WorldGenerator.new(catalog, 271828)
	for item: Dictionary in geometry:
		var mission: MissionDefinition = item.mission
		var point := mission.acceptance_point()
		var host := Node3D.new()
		root.add_child(host)
		var first := WorldGenerator.key_at(point - Vector3(4, 3, 4))
		var last := WorldGenerator.key_at(point + Vector3(4, 4, 4))
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for z in range(first.z, last.z + 1):
					host.add_child(WorldGeometry.create_chunk(generator.generate(Vector3i(x, y, z)), point))
		await physics_frame
		await physics_frame
		var clear := true
		for x: float in [-2, 0, 2]:
			for z: float in [-2, 0, 2]:
				var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 2, z), Vector3(x, -1, z))
				var hit := host.get_world_3d().direct_space_state.intersect_ray(ray)
				clear = clear and not hit.is_empty() and absf(hit.position.y + point.y - float(mission.pickup_platform.top)) < 0.04 and hit.normal.dot(Vector3.UP) > 0.99
		check(clear, "real reception floor is clear and landable " + mission.id)
		host.queue_free()
		await physics_frame

func balloon_clearance(catalog: ContentCatalog) -> void:
	var generator := WorldGenerator.new(catalog, 271828)
	for kind: String in balloon_geometry:
		var mission: MissionDefinition = balloon_geometry[kind]
		var point := mission.checkpoints[0]
		var bounds := AABB(point, Vector3.ZERO)
		for launch: Vector3 in mission.checkpoints:
			bounds = bounds.expand(launch - Vector3.ONE * 2)
			bounds = bounds.expand(Vector3(launch.x + 2, mission.challenge.height_limit + 2, launch.z + 2))
		var first := WorldGenerator.key_at(bounds.position)
		var last := WorldGenerator.key_at(bounds.end)
		var host := Node3D.new()
		root.add_child(host)
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for z in range(first.z, last.z + 1):
					host.add_child(WorldGeometry.create_chunk(generator.generate(Vector3i(x, y, z)), point))
		await physics_frame
		await physics_frame
		var shape := SphereShape3D.new()
		shape.radius = 1.5
		var clear := true
		for launch: Vector3 in mission.checkpoints:
			for index in 9:
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = shape
				query.transform.origin = Vector3(launch.x, lerpf(launch.y, mission.challenge.height_limit, index / 8.0), launch.z) - point
				if not host.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
					print("BALLOON_BLOCKED ", mission.id, " ", query.transform.origin + point)
					clear = false
		check(clear and mission.checkpoints.size() >= 5, "native geometry leaves complete rising balloon columns clear " + kind)
		host.queue_free()
		await physics_frame

func production() -> void:
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	var mission: MissionDefinition = game.store.mission_definition(sample_mission.id)
	var pad := mission.acceptance_point()
	game._debug_teleport(pad + Vector3.UP * 0.7)
	for frame in 1200:
		await process_frame
		if game.streamer.collision_ready(pad):
			break
	game.drone.global_basis = Basis.IDENTITY
	game.drone.tuning.gravity = 0
	game._set_paused(false)
	await create_timer(0.12).timeout
	game._perform_action("interact")
	check(game.store.mission_status(mission.id) == "available" and game._docked_task_id().is_empty(), "hovering directly above reception cannot accept a task")
	game.drone.tuning.gravity = 9.81
	for frame in 240:
		await physics_frame
		if game._docked_task_id() == mission.id:
			break
	check(game._docked_task_id() == mission.id, "native drone physically lands on reception floor")
	game._set_paused(true)
	game.set_process(false)
	game.drone.camera.current = true
	var camera: Camera3D = game.drone.camera
	var sign := pad + Vector3.UP * 3
	var direction := Vector3.BACK
	for index in 16:
		var candidate := Vector3(cos(index * TAU / 16), 0, sin(index * TAU / 16))
		var ray := PhysicsRayQueryParameters3D.create(sign + candidate * 40 - game.streamer.origin_offset, sign - game.streamer.origin_offset)
		ray.exclude = [game.drone.get_rid()]
		if game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			direction = candidate
			break
	camera.global_position = sign + direction * 16 - game.streamer.origin_offset
	camera.look_at(sign - game.streamer.origin_offset)
	game.challenge_view.controller = game.missions
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	var actor: Dictionary = game.challenge_view.actors[mission.id]
	check(actor.balloons.is_empty(), "unaccepted balloon task shows only its reception point")
	var label: Label3D = actor.entry.get_child(0)
	check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED and not label.fixed_size and not label.no_depth_test and actor.entry.global_position.is_equal_approx(sign - game.streamer.origin_offset), "sign is a depth-tested world object facing the camera, without fixed screen size")
	var near_width := camera.unproject_position(label.global_position + camera.global_basis.x * 2.95).distance_to(camera.unproject_position(label.global_position - camera.global_basis.x * 2.95))
	await capture("reception-near")
	camera.global_position = sign + direction * 40 - game.streamer.origin_offset
	var far_width := camera.unproject_position(label.global_position + camera.global_basis.x * 2.95).distance_to(camera.unproject_position(label.global_position - camera.global_basis.x * 2.95))
	check(near_width > far_width * 2.4 and near_width < far_width * 2.6, "world sign shrinks proportionally with viewing distance")
	await capture("reception-far")
	game.challenge_view.update_at(pad + Vector3(80, 0, 0), game.streamer.origin_offset, true)
	check(not actor.entry.visible, "distant signs disappear at their draw distance")
	camera.global_position = sign + direction * 16 - game.streamer.origin_offset
	check(game.missions.accept(mission.id, pad + Vector3(500, 0, 0)).ok, "remote map acceptance reserves a balloon task")
	game.missions.update_objective(pad + Vector3(500, 0, 0), 0, 120, false, false)
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	check(game.missions.challenge_state(mission).get("elapsed", 0) == 0 and visible_balloons(mission) == 0 and game.missions.objective_point(mission).is_equal_approx(pad), "remote accepted task neither releases nor expires before platform start")
	var waiting_reload := ProgressStore.new(game.catalog, game.store.path)
	check(not waiting_reload.data.assignments[mission.id].started and not game.missions.objective_hint(mission).is_empty(), "waiting-for-start survives reload and has arrival instructions")
	game._perform_action("interact")
	check(game.store.mission_status(mission.id) == "active" and game.missions.challenge_state(mission).started, "actual landed E starts a remotely accepted balloon task")
	game.missions.balloon_popped.connect(func(_point: Vector3, _index: int): pop_events += 1)
	var start: Dictionary = game.store.data.assignments[mission.id].duplicate(true)
	var unreleased := start.duplicate(true)
	unreleased.hits = [0]
	check(not game.store.save_challenge_state(mission.id, unreleased).ok, "unreleased balloons cannot be recorded as hits")
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	check(visible_balloons(mission) == 0, "accepted task waits for its first release")
	game.missions.update_objective(pad, 0, 3.1, false, false)
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	check(visible_balloons(mission) == 1, "first balloon appears after preparation delay")
	game.missions.update_objective(pad, 0, float(mission.challenge.release_interval), false, false)
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	check(visible_balloons(mission) == 2, "second balloon releases later rather than spawning the whole set")
	var first := FlightChallengeRules.balloon_point(mission, 0, 3.1)
	var later := FlightChallengeRules.balloon_point(mission, 0, 6.1)
	check(later.y > first.y + 5 and later.y < first.y + 6, "surface balloons visibly climb at 1.8 metres per second")
	var spaced := true
	for a in mission.checkpoints.size():
		for b in range(a + 1, mission.checkpoints.size()):
			spaced = spaced and mission.checkpoints[a].distance_to(mission.checkpoints[b]) >= 9
	check(spaced, "balloon launch positions have meaningful separation")
	var clock := float(game.missions.challenge_state(mission).elapsed)
	game.missions.track("", pad)
	game.missions.update_objective(pad, 0, 1, false, false)
	check(float(game.missions.challenge_state(mission).elapsed) > clock, "stopping tracking does not freeze balloon ascent")
	clock = float(game.missions.challenge_state(mission).elapsed)
	game.missions.update_objective(pad, 0, 20, false, true)
	check(float(game.missions.challenge_state(mission).elapsed) == clock, "pause freezes releases and ascent")
	game.missions.track(mission.id, pad)
	var saved: Dictionary = game.store.data.assignments[mission.id].duplicate(true)
	game.store.writable = false
	strike(mission, 0)
	check(pop_events == 0 and game.store.data.assignments[mission.id] == saved, "failed hit commit produces neither credit, confetti nor pop sound")
	game.store.writable = true
	var audio_capture: AudioEffectCapture
	var effects_bus := AudioServer.get_bus_index("Effects")
	if DisplayServer.get_name() != "headless":
		audio_capture = AudioEffectCapture.new()
		audio_capture.buffer_length = 1
		AudioServer.add_bus_effect(effects_bus, audio_capture)
		var settings: Dictionary = game.audio_mixer.settings.duplicate(true)
		settings.motors = 0
		settings.music = 0
		game.audio_mixer.apply(settings)
	var balloon := FlightChallengeRules.balloon_point(mission, 0, float(game.missions.challenge_state(mission).elapsed))
	camera.global_position = balloon + Vector3(0, 1, 8) - game.streamer.origin_offset
	camera.look_at(balloon - game.streamer.origin_offset)
	strike(mission, 0)
	for frame in 4:
		game.challenge_view.update_at(pad, game.streamer.origin_offset, true, 0.08)
	check(pop_events == 1 and game.challenge_view.effects.bursts.size() == 1 and game.challenge_view.effects.bursts[0].shards.size() == 36, "committed hit emits exactly one colourful confetti burst")
	check(game.flight_audio.pops[0].bus == "Effects" and game.flight_audio.pops[0].max_distance == 90, "pop sound is spatial and follows the existing effect volume")
	await capture("balloon-pop")
	if audio_capture != null:
		await create_timer(0.2).timeout
		var pcm := audio_capture.get_buffer(audio_capture.get_frames_available())
		var peak := 0.0
		for frame: Vector2 in pcm:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		check(peak > 0.005, "native audio server actually plays the balloon pop")
		AudioServer.remove_bus_effect(effects_bus, AudioServer.get_bus_effect_count(effects_bus) - 1)
		audio_capture = null
	var cash: int = game.store.data.credits
	game.missions.update_objective(pad, 0, 90, false, false)
	check(game.store.mission_status(mission.id) == "failed" and game.store.data.credits == cash and game.store.data.tracked_mission.is_empty(), "missing any balloon at its ceiling fails without reward")
	game.challenge_view.update_at(pad, game.streamer.origin_offset, true)
	check(game.challenge_view.actors[mission.id].balloons.is_empty(), "failed challenge removes remaining balloons and retains retry point")
	var restart := ProgressStore.new(game.catalog, game.store.path)
	check(restart.mission_status(mission.id) == "failed", "balloon failure persists across reload")
	game._perform_action("interact")
	check(game.store.mission_status(mission.id) == "active" and game.missions.challenge_state(mission).get("hits", []).is_empty() and game.missions.challenge_state(mission).get("elapsed", 0) == 0, "landed E retries a failed balloon task from its first release")
	for round_index in 2:
		game.missions.update_objective(pad, 0, FlightChallengeRules.balloon_release_time(mission, mission.checkpoints.size() - 1) + 0.1, false, false)
		for index in mission.checkpoints.size():
			strike(mission, index)
		check(game.store.mission_status(mission.id) == "completed" and game.store.data.credits == cash + game.catalog.entries[mission.reward_id].credits, "complete every released balloon; only first successful round pays " + str(round_index))
		if round_index == 0:
			game._perform_action("interact")
	for index in 60:
		game.challenge_view.effects.update_at(game.streamer.origin_offset, 0.05, false)
	check(game.challenge_view.effects.bursts.is_empty(), "temporary confetti is bounded and automatically removed")
	game.queue_free()
	await create_timer(0.2).timeout

func strike(mission: MissionDefinition, index: int) -> void:
	game.missions.invalidate_motion()
	var elapsed := float(game.missions.challenge_state(mission).get("elapsed", 0)) + 0.08
	var point := FlightChallengeRules.balloon_point(mission, index, elapsed)
	game.missions.update_objective(point - Vector3.RIGHT * 2, 0, 0.04, false, false)
	game.missions.update_objective(point + Vector3.RIGHT * 2, 0, 0.04, false, false)

func visible_balloons(mission: MissionDefinition) -> int:
	var count := 0
	for balloon: Node3D in game.challenge_view.actors[mission.id].balloons.values():
		count += int(balloon.visible)
	return count
