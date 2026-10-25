extends SceneTree
var failed := 0
var checked := 0
var report := {"routes": [], "features": {}, "fallbacks": 0}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func run() -> void:
	if DisplayServer.get_name() != "headless":
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("172638")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.8
		root.add_child(environment)
	await manoeuvres()
	var selected: MissionDefinition
	var catalog := ContentCatalog.new()
	var fingerprint := catalog.fingerprint()
	for seed_value in [271828, 42, 314159, 1919810]:
		var world := BiomeWorld.new(catalog, seed_value)
		var valid := true
		var local_routes := 0
		for x in range(-3, 1):
			for z in range(-3, 1):
				for kind: String in ["surface", "sky"]:
					var plan := world.plan(kind, Vector2i(x, z))
					for task: MissionDefinition in plan.get("missions", []) + plan.get("legacy_missions", []):
						if task.kind != "race": continue
						if task.challenge.get("acro_revision", 0) != 2:
							continue
						local_routes += 1
						selected = task if selected == null else selected
						var old := world.mission(task.id.trim_suffix(":smooth"))
						var identity_ok: bool = old != null and old.transaction_id() == task.transaction_id() and world.mission(task.id).checkpoints == task.checkpoints
						var path_ok := follows_path(task)
						if kind == "sky":
							for point: Vector3 in task.checkpoints: path_ok = path_ok and world.instance_at(point).id == plan.id
						if not identity_ok or not path_ok: print("INVALID_ROUTE ", seed_value, " ", task.id, " identity=", identity_ok, " path=", path_ok)
						valid = valid and identity_ok and path_ok
						for feature: String in task.challenge.manoeuvres: report.features[feature] = int(report.features.get(feature, 0)) + 1
						report.routes.append({"seed": seed_value, "id": task.id, "gates": task.checkpoints.size(), "features": task.challenge.manoeuvres})
		check(valid and local_routes >= 3, "continuous paths, tangent gates, bounded spacing and legacy resolution seed=" + str(seed_value))
	check(report.features.has("pull_loop") and report.features.has("horizontal_orbit") and report.features.has("s_bend") and report.features.has("split_s"), "seeded courses include loops, orbits, S bends and split-S where space allows")
	check(catalog.fingerprint() == fingerprint, "procedural routes leave shared content resources unchanged")
	var replay := BiomeWorld.new(catalog, 271828)
	check(replay.mission("smooth") == null and replay.mission("acro:smooth") == null, "malformed version suffixes do not index empty identifiers")
	if selected != null:
		var rebuilt := replay.mission(selected.id)
		check(rebuilt.checkpoints == selected.checkpoints and rebuilt.gate_normals == selected.gate_normals and rebuilt.challenge.flight_path == selected.challenge.flight_path, "cold generation reproduces gates, normals and full flight curve exactly")
	if selected != null: history(selected)
	# Actual public geometry is now covered by spatial/refinement/gameplay.
	# This suite retains v0.23's curve, save and original-frame contracts.
	var directory := "res://../.local/test-results/continuous-routes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("routes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("CONTINUOUS_ROUTES_RESULT failures=%d checks=%d routes=%d features=%s fallbacks=%d" % [failed, checked, report.routes.size(), report.features, report.fallbacks])
	quit(1 if failed else 0)

func production_curves(catalog: ContentCatalog) -> void:
	for feature: String in ["pull_loop", "split_s"]:
		var task: MissionDefinition
		var world: BiomeWorld
		for record: Dictionary in report.routes:
			if feature in record.features:
				world = BiomeWorld.new(catalog, record.seed)
				task = world.mission(record.id)
				break
		if task == null: check(false, "production sample exists for " + feature); continue
		var path: PackedVector3Array = task.challenge.flight_path
		var keys := {}
		for point in path:
			var key := WorldGenerator.key_at(point)
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2): keys[key + Vector3i(x, y, z)] = true
		var host := Node3D.new()
		root.add_child(host)
		for key: Vector3i in keys:
			var descriptor := world.generate_chunk(key)
			if not descriptor.objects.is_empty(): host.add_child(WorldGeometry.create_chunk(descriptor, Vector3.ZERO))
		await physics_frame
		await physics_frame
		var body := SphereShape3D.new()
		body.radius = 0.4
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body
		var clear := true
		for index in range(1, path.size()):
			query.transform = Transform3D(Basis.IDENTITY, path[index - 1])
			query.motion = path[index] - path[index - 1]
			var fraction: float = host.get_world_3d().direct_space_state.cast_motion(query)[0]
			if fraction < 1: print("PRODUCTION_BLOCKED ", feature, " ", index, " ", path[index]); clear = false; break
		check(clear, "real generated terrain, buildings, island bodies and frames clear the full " + feature)
		host.queue_free()
		await physics_frame

func follows_path(task: MissionDefinition) -> bool:
	var points: PackedVector3Array = task.challenge.flight_path
	var indices: PackedInt32Array = task.challenge.gate_path_indices
	if task.checkpoints.size() < 7 or task.checkpoints.size() > ContinuousCourses.MAX_GATES or indices.size() != task.checkpoints.size(): return false
	for index in indices.size():
		var p := task.checkpoints[index]
		var normal := task.gate_normals[index]
		if not normal.is_finite() or absf(normal.length() - 1) > 0.001 or p != points[indices[index]]: return false
		var before := points[maxi(0, indices[index] - 1)] if index > 0 else p - normal
		var after := points[mini(points.size() - 1, indices[index] + 1)] if index < indices.size() - 1 else p + normal
		if (after - before).normalized().dot(normal) < 0.995:
			print("TANGENT_MISMATCH ", index, " dot=", (after - before).normalized().dot(normal)); return false
		if not FlightChallengeRules.passes_gate(task, index, before, after) or FlightChallengeRules.passes_gate(task, index, after, before):
			print("CROSSING_MISMATCH ", index); return false
		if index > 0:
			var chord := p - task.checkpoints[index - 1]
			if chord.length() < 8 or chord.normalized().dot(normal) < 0.70 or chord.normalized().dot(task.gate_normals[index - 1]) < 0.70: return false
	return true

func manoeuvres() -> void:
	var source := PackedVector3Array([Vector3(0, 120, 0), Vector3(180, 120, 0)])
	for mode in 4:
		var path := ContinuousCourses.build(source, mode)
		check(not path.is_empty() and ContinuousCourses.clear(path, {}, null, 3.0), "unobstructed manoeuvre and every frame fit curve and chords mode=" + str(mode))
		if path.is_empty(): continue
		var task := MissionDefinition.new()
		task.checkpoints = path.gates
		task.gate_normals = path.normals
		task.challenge = {"gate_half": 3.0, "flight_path": path.points, "gate_path_indices": path.indices}
		check(follows_path(task), "curved traversal counts each directed gate, reverse traversal fails mode=" + str(mode))
		var tangents: PackedVector3Array = path.tangents
		var smooth := true
		for index in range(1, tangents.size()): smooth = smooth and tangents[index - 1].dot(tangents[index]) > cos(deg_to_rad(10))
		check(smooth, "no tangent jumps at entry, inverted apex or exit mode=" + str(mode))
		if mode == 0:
			var rising := false
			var falling := false
			for normal: Vector3 in path.normals:
				rising = rising or normal.y > 0.95
				falling = falling or normal.y < -0.95
			check(rising and falling, "pull loop has genuinely vertical gates and continuous inverted descent")
		if mode == 3:
			check(Vector3(path.normals[-1]).dot(path.normals[0]) < -0.99 and path.gates[-1].y < path.gates[0].y - 40, "split-S descends in a half-loop and exits reversed horizontally")
		var objects: Array[Dictionary] = []
		for index in path.gates.size(): MissionCourses.gate(objects, "test%d" % index, path.gates[index], path.normals[index], 3.0)
		var host := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": objects}, Vector3.ZERO)
		root.add_child(host)
		await physics_frame
		await physics_frame
		var query := PhysicsShapeQueryParameters3D.new()
		var body := SphereShape3D.new()
		body.radius = 0.4
		query.shape = body
		var clear := true
		for index in range(1, path.points.size()):
			query.transform = Transform3D(Basis.IDENTITY, path.points[index - 1])
			query.motion = path.points[index] - path.points[index - 1]
			clear = clear and host.get_world_3d().direct_space_state.cast_motion(query)[0] >= 1
		check(clear, "real drone envelope traverses the manoeuvre without touching any frame mode=" + str(mode))
		if DisplayServer.get_name() != "headless": await capture_manoeuvre(task, mode)
		host.queue_free()
		await physics_frame
	var descent := ContinuousCourses.build(PackedVector3Array([Vector3(0, 160, 0), Vector3(100, 160, 0), Vector3(180, 90, 0)]), 2)
	check(not descent.is_empty() and descent.features.has("wide_descent"), "upright pitch-down corner becomes a broad descent arc")
	if not descent.is_empty():
		var max_down_acceleration := 0.0
		for index in range(1, descent.points.size()):
			var distance: float = Vector3(descent.points[index]).distance_to(descent.points[index - 1])
			max_down_acceleration = maxf(max_down_acceleration, -(descent.tangents[index].y - descent.tangents[index - 1].y) / distance * pow(ContinuousCourses.DESIGN_SPEED, 2))
		check(max_down_acceleration <= 9.81, "upright downward bending stays below gravity at design speed: " + str(max_down_acceleration))
	check(ContinuousCourses.build(PackedVector3Array([Vector3(0, 100, 0), Vector3(18, 100, 0), Vector3(18, 70, 0)]), 2).is_empty(), "reject short level-to-vertical push-over")
	var obstructed := ContinuousCourses.build(source, 0)
	var blocker := WorldProvider.box("inside_curve", obstructed.points[obstructed.points.size() / 2], Vector3.ONE * 2, Color.WHITE)
	var obstacles: Array[Dictionary] = [blocker]
	check(not ContinuousCourses.clear(obstructed, FlowCourses._prepare_obstacles(obstacles), null, 3), "clearance checks the curve, including obstacles between gates")

func capture_manoeuvre(task: MissionDefinition, mode: int) -> void:
	var guide := RaceRouteGuide.new()
	root.add_child(guide)
	guide.position = task.acceptance_point()
	guide.configure(task, 0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 225
	camera.position = Vector3(90, 245 if mode == 1 else 150, 180)
	camera.look_at(Vector3(90, 105 if mode == 3 else 135, 10))
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://../.local/test-results/continuous-routes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join("manoeuvre%d.png" % mode)) == OK, "normal window capture mode=" + str(mode))
	guide.queue_free()
	camera.queue_free()

func history(task: MissionDefinition) -> void:
	var catalog := ContentCatalog.new()
	var store := ProgressStore.new(catalog, "user://tests/continuous_%d/progress.json" % Time.get_ticks_usec())
	var old := store.mission_definition(task.id.trim_suffix(":smooth"))
	if old == null: check(false, "legacy definition exists"); return
	var points := old.checkpoints.duplicate()
	var normals := old.gate_normals.duplicate()
	store.accept_mission(old.id)
	var state: Dictionary = store.data.assignments[old.id].duplicate(true)
	state.stage = 2
	store.save_challenge_state(old.id, state)
	store = ProgressStore.new(catalog, store.path)
	check(store.mission_definition(old.id).checkpoints == points and store.mission_definition(old.id).gate_normals == normals and store.data.assignments[old.id].stage == 2, "active v1 acro task reloads exact gates, normals and stage")
	state = store.data.assignments[old.id].duplicate(true)
	state.stage = points.size()
	store.save_challenge_state(old.id, state)
	store.complete_mission(old.id)
	var credits: int = store.data.credits
	var accepted := store.accept_mission(task.id)
	state = store.data.assignments[task.id].duplicate(true)
	state.stage = task.checkpoints.size()
	store.save_challenge_state(task.id, state)
	check(accepted.ok and store.complete_mission(task.id).ok and store.data.credits == credits, "continuous layout shares the old task's one-time reward after reload")
