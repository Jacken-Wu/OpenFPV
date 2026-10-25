extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/challenge-feedback"
var orbits := {}
var race: MissionDefinition
var passed: Array[int] = []
var finishes := 0

class FinishProbe extends ProgressStore:
	var reject_finish := false
	func _init(content: ContentCatalog, save_path: String) -> void:
		super(content, save_path)
	func complete_mission(id: String, evidence: Dictionary = {}) -> Dictionary:
		return {"ok": false, "message": "test completion write failure"} if reject_finish else super.complete_mission(id, evidence)

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)

func cross(controller: MissionController, mission: MissionDefinition, index: int) -> void:
	controller.invalidate_motion()
	var point := mission.checkpoints[index]
	var normal := mission.gate_normals[index]
	controller.update_objective(point - normal, 0, 0.02, false, false)
	controller.update_objective(point + normal, 0, 0.02, false, false)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	var store := ProgressStore.new(catalog, "user://tests/feedback_%d/progress.json" % Time.get_ticks_usec())
	for kind: String in ["surface", "sky", "maze"]:
		for x in range(-3, 4):
			for z in range(-3, 4):
				if orbits.has(kind):
					continue
				var plan: Dictionary = store.regions.plan(kind, Vector2i(x, z))
				for mission: MissionDefinition in plan.get("missions", []):
					if mission.kind == "orbit":
						orbits[kind] = mission
					if race == null and mission.kind == "race":
						race = mission
	check(orbits.size() == 3 and race != null, "generated orbit targets cover surface, sky and maze")
	await edges()
	await orbit_visuals(store)
	orbit_leniency()
	feedback(catalog)
	await production_audio()
	var file := FileAccess.open(directory.path_join("feedback.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checked, "failures": failed, "orbit_layers": orbits.keys(), "native_gate_poses": 4, "edge_and_corner_sweeps": 32, "gate_opening_margin_old_m": 0.325, "scope": "native collision sweeps, world transforms, orbit rules, durable cue events and native Effects playback; not human RC flight"}, "\t"))
	print("CHALLENGE_FEEDBACK_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)

func edges() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var normals: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, Vector3(0.6, 0.3, -0.7).normalized()]
	var mission := MissionDefinition.new()
	mission.kind = "race"
	mission.challenge = {"gate_half": 3.0}
	for index in normals.size():
		var center := Vector3(-160 + index * 20, 10, -192)
		mission.checkpoints = PackedVector3Array([center])
		mission.gate_normals = PackedVector3Array([normals[index]])
		var objects: Array[Dictionary] = []
		MissionCourses.gate(objects, "edge%d" % index, center, normals[index], 3)
		host.add_child(WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": objects}, Vector3.ZERO))
	await physics_frame
	await physics_frame
	var space := host.get_world_3d().direct_space_state
	var body := BoxShape3D.new()
	body.size = Vector3(0.3, 0.3, 0.3)
	for index in normals.size():
		var center := Vector3(-160 + index * 20, 10, -192)
		mission.checkpoints = PackedVector3Array([center])
		mission.gate_normals = PackedVector3Array([normals[index]])
		var basis := FlightChallengeRules.gate_basis(normals[index])
		var edge := FlightChallengeRules.gate_opening_half(mission) - 0.16
		var clear := true
		var counts := true
		for offset: Vector2 in [Vector2(edge, 0), Vector2(-edge, 0), Vector2(0, edge), Vector2(0, -edge), Vector2(edge, edge), Vector2(-edge, edge), Vector2(edge, -edge), Vector2(-edge, -edge)]:
			var from := center + basis * Vector3(offset.x, offset.y, 0) - normals[index]
			var to := from + normals[index] * 2
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body
			query.transform = Transform3D(basis, from)
			query.motion = to - from
			query.margin = 0.001
			clear = clear and space.cast_motion(query)[0] > 0.99
			counts = counts and FlightChallengeRules.passes_gate(mission, 0, from, to)
		check(clear and counts, "actual body clears inner edges/corners and all crossings count pose=" + str(index))
		var outside := center + basis.x * (FlightChallengeRules.gate_opening_half(mission) + 0.06)
		check(not FlightChallengeRules.passes_gate(mission, 0, outside - normals[index], outside + normals[index]) and not FlightChallengeRules.passes_gate(mission, 0, center + normals[index], center - normals[index]), "outside frame and reverse crossings remain rejected pose=" + str(index))
	host.queue_free()
	await physics_frame

func orbit_visuals(store: ProgressStore) -> void:
	var host := Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.current = true
	var controller := MissionController.new(store.catalog, store, MapNavigation.new(4))
	var view := MissionChallengeView.new()
	view.controller = controller
	host.add_child(view)
	for kind: String in orbits:
		var mission: MissionDefinition = orbits[kind]
		controller.accept(mission.id, mission.acceptance_point())
		var aligned := true
		for origin: Vector3 in [Vector3.ZERO, Vector3(-20000, 16, 20000)]:
			camera.global_position = mission.target_point + Vector3(12, 3, 12) - origin
			camera.look_at(mission.target_point - origin)
			view.update_at(mission.acceptance_point(), origin, true)
			var target: Node3D = view.actors[mission.id].target
			var guides := target.get_children().filter(func(child: Node): return child is MeshInstance3D and child.mesh is ImmediateMesh)
			aligned = aligned and (target.global_position + origin).distance_to(mission.target_point) < 0.005 and guides.size() == 1 and guides[0].global_position.distance_to(target.global_position) < 0.005
		check(aligned and mission.target_point.distance_to(mission.acceptance_point()) > 1, "target sphere, orbit guide and detector coincide across origin shifts " + kind)
		if DisplayServer.get_name() != "headless" and kind == "surface":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(directory.path_join("orbit-aligned.png")) == OK, "capture aligned world target and guide")
	host.queue_free()
	await process_frame

func orbit_leniency() -> void:
	var mission: MissionDefinition = orbits.surface
	check(mission.challenge.radius_min <= 6 and mission.challenge.radius_max >= 28 and mission.challenge.height_tolerance >= 6 and mission.challenge.view_angle >= 55, "surface orbit accepts wider distance, height and framing")
	var state := {"status": "active", "kind": "orbit", "orbit": PI, "direction": 1}
	var point := mission.target_point + Vector3(25, 5, 0)
	for index in 100:
		state = FlightChallengeRules.step(mission, state, point, point, 0.02, {"origin": point, "forward": Vector3.RIGHT, "clear": false})
	check(is_equal_approx(float(state.orbit), PI), "two seconds of lost framing preserves accumulated orbit")
	state = {"status": "active", "kind": "orbit"}
	for index in range(1, 901):
		var angle := index * TAU / 720
		var previous_angle := (index - 1) * TAU / 720
		var a := mission.target_point + Vector3(cos(previous_angle) * 25, sin(previous_angle) * 5, sin(previous_angle) * 25)
		var b := mission.target_point + Vector3(cos(angle) * 25, sin(angle) * 5, sin(angle) * 25)
		var visible := not (index in range(200, 240) or index in range(450, 490))
		state = FlightChallengeRules.step(mission, state, a, b, 0.16, {"origin": b, "forward": (mission.target_point - b).normalized().rotated(Vector3.UP, deg_to_rad(40)), "clear": visible})
	check(FlightChallengeRules.finished(mission, state), "imperfect wide orbit with height drift, loose framing, missed frames and interruptions can finish")
	var still := {"status": "active", "kind": "orbit"}
	still = FlightChallengeRules.step(mission, still, point, point, 0.16, {"origin": point, "forward": (mission.target_point - point).normalized(), "clear": true})
	check(not FlightChallengeRules.finished(mission, still) and still.get("orbit", 0) == 0, "stationary aiming still cannot complete an orbit")

func feedback(catalog: ContentCatalog) -> void:
	var store := FinishProbe.new(catalog, "user://tests/race_cues_%d/progress.json" % Time.get_ticks_usec())
	var mission := store.mission_definition(race.id)
	var controller := MissionController.new(catalog, store, MapNavigation.new(4))
	controller.race_gate_passed.connect(func(stage: int): passed.append(stage))
	controller.race_finished.connect(func(): finishes += 1)
	controller.accept(mission.id, mission.acceptance_point())
	store.writable = false
	cross(controller, mission, 0)
	check(passed.is_empty() and finishes == 0 and store.data.assignments[mission.id].get("stage", 0) == 0, "failed gate commit produces no false audio event")
	store.writable = true
	for index in mission.checkpoints.size() - 1:
		cross(controller, mission, index)
	check(passed.size() == mission.checkpoints.size() - 1 and finishes == 0, "each committed intermediate gate emits one progress cue")
	store.reject_finish = true
	cross(controller, mission, mission.checkpoints.size() - 1)
	check(finishes == 0 and FlightChallengeRules.finished(mission, store.data.assignments[mission.id]), "saved final gate waits for successful completion transaction before victory cue")
	store.reject_finish = false
	controller.update_objective(mission.checkpoints[-1], 0, 0.02, false, false)
	controller.finish(mission.id)
	check(finishes == 1 and store.mission_status(mission.id) == "completed", "completion retry emits one distinct finish event; duplicate finish stays silent")

func production_audio() -> void:
	var game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(true)
	game.set_process(false)
	game.flight_audio.set_process(false)
	for motor: AudioStreamPlayer in game.flight_audio.motors:
		motor.stop()
	var mission: MissionDefinition = game.store.mission_definition(race.id)
	game.missions.accept(mission.id, game._world_position())
	check(game.missions.race_gate_passed.is_connected(game._on_race_gate_passed) and game.missions.race_finished.is_connected(game._on_race_finished), "production controller wires gate and completion cues to flight audio")
	check(game.flight_audio.gate_chime.bus == "Effects" and game.flight_audio.finish_chime.bus == "Effects" and game.flight_audio.gate_chime.stream.get_length() < 0.2 and game.flight_audio.finish_chime.stream.get_length() > 0.5, "short gate cue and distinct longer finish melody use Effects volume")
	var bus := AudioServer.get_bus_index("Effects")
	var capture: AudioEffectCapture
	if DisplayServer.get_name() != "headless":
		capture = AudioEffectCapture.new()
		capture.buffer_length = 2
		AudioServer.add_bus_effect(bus, capture)
		await create_timer(0.15).timeout
		capture.clear_buffer()
	cross(game.missions, mission, 0)
	if capture != null:
		await create_timer(0.25).timeout
		check(peak(capture) > 0.01, "actual committed gate plays audible native Effects output")
	for index in range(1, mission.checkpoints.size() - 1):
		cross(game.missions, mission, index)
	if capture != null:
		await create_timer(0.25).timeout
		capture.clear_buffer()
	cross(game.missions, mission, mission.checkpoints.size() - 1)
	if capture != null:
		await create_timer(0.7).timeout
		check(peak(capture) > 0.01, "actual final crossing plays the native finish melody")
		AudioServer.set_bus_mute(bus, true)
		game.flight_audio.play_race_gate()
		game.flight_audio.play_race_finish()
		await create_timer(0.7).timeout
		# Capture precedes bus mute in Godot; the ordinary mixer mute is the authority.
		check(AudioServer.is_bus_mute(bus), "race cues obey the shared Effects mute")
		AudioServer.set_bus_mute(bus, false)
		AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	game.flight_audio.gate_chime.stream.save_to_wav(directory.path_join("gate-pass.wav"))
	game.flight_audio.finish_chime.stream.save_to_wav(directory.path_join("race-finish.wav"))
	game.queue_free()
	await create_timer(0.2).timeout

func peak(capture: AudioEffectCapture) -> float:
	var value := 0.0
	for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
		value = maxf(value, maxf(absf(frame.x), absf(frame.y)))
	return value
