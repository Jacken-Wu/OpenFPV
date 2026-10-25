extends SceneTree
var failed := 0
var checked := 0
var report := {"routes": [], "old_gates": 0, "new_gates": 0, "nonplanar": 0, "sharp": 0, "banked": 0, "remaining_dense": []}
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
	await units()
	var catalog := ContentCatalog.new()
	var fingerprint := catalog.fingerprint()
	for seed_value in [271828, 42, 314159, 1919810]:
		var world := BiomeWorld.new(catalog, seed_value)
		var count := 0
		var valid := true
		for x in range(-3, 1):
			for z in range(-3, 1):
				for kind: String in ["surface", "sky"]:
					var plan := world.plan(kind, Vector2i(x, z))
					for task: MissionDefinition in plan.get("missions", []):
						if not task.challenge.has("spatial_revision"):
							if task.challenge.get("acro_revision", 0) == 2: report.remaining_dense.append(task.id)
							continue
						count += 1
						var old := world.mission(task.id.trim_suffix(":spatial"))
						var local_valid := verify(task) and old != null and old.transaction_id() == task.transaction_id()
						if task.challenge.geometry_retained:
							local_valid = local_valid and task.challenge.flight_path == old.challenge.flight_path
						if task.challenge.legacy_frame_constraints:
							for point: Vector3 in task.checkpoints: local_valid = local_valid and point in old.checkpoints
						if kind == "sky":
							for point: Vector3 in task.checkpoints: local_valid = local_valid and world.instance_at(point).id == plan.id
						if not local_valid: print("BAD_SPATIAL_ROUTE ", task.id)
						valid = valid and local_valid
						var points: PackedVector3Array = task.challenge.flight_path
						var nonplanar := plane_error(points)
						var curvature := max_curvature(points)
						var bank := 0.0
						for index in task.checkpoints.size(): bank = maxf(bank, acos(clampf(FlightChallengeRules.gate_basis(task.gate_normals[index]).y.dot(task.challenge.gate_ups[index]), -1, 1)))
						if nonplanar > 2: report.nonplanar += 1
						if curvature > 1.0 / 12: report.sharp += 1
						if bank > deg_to_rad(25): report.banked += 1
						report.old_gates += old.checkpoints.size()
						report.new_gates += task.checkpoints.size()
						report.routes.append({"seed": seed_value, "id": task.id, "old_gates": old.checkpoints.size(), "gates": task.checkpoints.size(), "nonplanarity_m": nonplanar, "max_curvature": curvature, "bank_degrees": rad_to_deg(bank), "geometry_retained": task.challenge.geometry_retained, "legacy_frame_constraints": task.challenge.legacy_frame_constraints, "features": task.challenge.manoeuvres})
		check(valid and count >= 3, "sparse spatial routes, correct banked crossing and unchanged sky ownership seed=" + str(seed_value))
	check(report.new_gates < report.old_gates * 0.70, "key-node gates substantially reduce density: %d -> %d" % [report.old_gates, report.new_gates])
	check(report.remaining_dense.is_empty(), "all sampled 0.23 dense curves receive sparse key-node layouts")
	check(report.nonplanar >= report.routes.size() * 0.4 and report.sharp >= 5 and report.banked >= report.routes.size() * 0.6, "seeded routes combine truly spatial curves, tight turns and explicit bank frames")
	check(catalog.fingerprint() == fingerprint, "spatial generation does not mutate shared definitions")
	if not report.routes.is_empty(): history(catalog, report.routes[0])
	var directory := "res://../.local/test-results/spatial-routes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("routes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("SPATIAL_ROUTES_RESULT failures=%d checks=%d routes=%d gates=%d/%d nonplanar=%d sharp=%d banked=%d" % [failed, checked, report.routes.size(), report.new_gates, report.old_gates, report.nonplanar, report.sharp, report.banked])
	quit(1 if failed else 0)

func verify(task: MissionDefinition) -> bool:
	var path: PackedVector3Array = task.challenge.flight_path
	var ups: PackedVector3Array = task.challenge.flight_ups
	var indices: PackedInt32Array = task.challenge.gate_path_indices
	if ups.size() != path.size() or indices.size() != task.checkpoints.size() or task.checkpoints.size() < 2: return false
	for index in indices.size():
		var p := task.checkpoints[index]
		var normal := task.gate_normals[index]
		var basis := FlightChallengeRules.gate_basis_for(task, index)
		if p != path[indices[index]] or absf(basis.determinant() - 1) > 0.001 or absf(normal.dot(basis.y)) > 0.001: return false
		if index > 0 and p.distance_to(task.checkpoints[index - 1]) < 8: return false
		var before := path[maxi(0, indices[index] - 1)] if index > 0 else p - normal
		var after := path[mini(path.size() - 1, indices[index] + 1)] if index < indices.size() - 1 else p + normal
		if not FlightChallengeRules.passes_gate(task, index, before, after) or FlightChallengeRules.passes_gate(task, index, after, before): return false
	return task.challenge.legacy_frame_constraints or (float(task.challenge.body_push_curvature) <= 1.0 / 40 and float(task.challenge.body_roll_per_meter) <= deg_to_rad(30))

func units() -> void:
	var line := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "keys": [], "features": []}
	ContinuousCourses._line(line, Vector3(0, 120, 0), Vector3(180, 120, 0))
	var sparse := SpatialCourses.finish_path(line)
	check(sparse.gates.size() == 2, "180m straight uses only entry and exit gates")
	var arc := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "keys": [], "features": []}
	for step in 121:
		var t := step / 120.0 * 0.6
		ContinuousCourses._push(arc, Vector3(240 * sin(t), 120, 240 * (1 - cos(t))), Vector3(cos(t), 0, sin(t)))
	sparse = SpatialCourses.finish_path(arc)
	check(sparse.gates.size() <= 4, "wide shallow arc does not become a dense gate corridor")
	var inverted := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "keys": [], "features": []}
	ContinuousCourses._line(inverted, Vector3(-45, 140, 0), Vector3(0, 140, 0))
	for step in 31:
		var angle := step / 30.0 * PI / 2
		ContinuousCourses._push(inverted, Vector3(8 * sin(angle), 140 - 8 * (1 - cos(angle)), 0), Vector3(cos(angle), -sin(angle), 0))
	ContinuousCourses._line(inverted, Vector3(8, 132, 0), Vector3(8, 90, 0))
	var pull := SpatialCourses.finish_path(inverted)
	check(not pull.is_empty() and pull.push_curvature < 0.001 and Vector3(pull.ups[40]).y < -0.8, "tight world-down turn is a positive body pull when inverted")
	var upright_ups := PackedVector3Array()
	for tangent: Vector3 in inverted.tangents: upright_ups.append(Vector3(-tangent.y, tangent.x, 0))
	check(SpatialCourses.body_push_curvature(inverted.tangents, upright_ups, pull.distances) > 0.10, "the same world-down curve is a tight negative pitch when the body stays upright")
	var rotation := Basis.from_euler(Vector3(0.6, 0.4, 1.1))
	var rotated := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "keys": [], "features": []}
	for index in inverted.points.size(): ContinuousCourses._push(rotated, rotation * inverted.points[index], rotation * inverted.tangents[index])
	var other := SpatialCourses.finish_path(rotated)
	check(absf(other.push_curvature - pull.push_curvature) < 0.001, "body pull classification is invariant under arbitrary world rotation")
	var task := MissionDefinition.new()
	task.checkpoints = PackedVector3Array([Vector3.ZERO])
	task.gate_normals = PackedVector3Array([Vector3.FORWARD])
	task.challenge = {"gate_half": 3.0, "gate_ups": PackedVector3Array([Vector3.UP.rotated(Vector3.FORWARD, PI / 4)])}
	var basis := FlightChallengeRules.gate_basis_for(task, 0)
	var inside := basis * Vector3(2.9, 2.9, 0)
	check(FlightChallengeRules.passes_gate(task, 0, inside - Vector3.FORWARD, inside + Vector3.FORWARD), "45-degree banked gate counts its actual opening corners")
	var outside := basis * Vector3(3.3, 0, 0)
	check(not FlightChallengeRules.passes_gate(task, 0, outside - Vector3.FORWARD, outside + Vector3.FORWARD), "banked gate rejects crossing beyond its physical opening")
	for mode in 4:
		var path := SpatialCourses.build(PackedVector3Array([Vector3(0, 140, 0), Vector3(180, 140, 0)]), mode + 4)
		check(not path.is_empty() and path.push_curvature <= 1.0 / 40, "continuous transported frame avoids tight body push-over mode=" + str(mode))
		if path.is_empty(): continue
		var objects: Array[Dictionary] = []
		for index in path.gates.size(): MissionCourses.gate(objects, "test%d" % index, path.gates[index], path.normals[index], 3.0, path.gate_ups[index])
		var host := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": objects}, Vector3.ZERO)
		root.add_child(host)
		await physics_frame
		await physics_frame
		var shape := SphereShape3D.new()
		shape.radius = 0.4
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		var clear := true
		for index in range(1, path.points.size()):
			query.transform = Transform3D(Basis.IDENTITY, path.points[index - 1])
			query.motion = path.points[index] - path.points[index - 1]
			clear = clear and host.get_world_3d().direct_space_state.cast_motion(query)[0] >= 1
		check(clear, "real body envelope clears rolled frames along full spatial curve mode=" + str(mode))
		if DisplayServer.get_name() != "headless": await capture(path, mode)
		host.queue_free()
		await physics_frame

func capture(path: Dictionary, mode: int) -> void:
	var task := MissionDefinition.new()
	task.kind = "race"
	task.checkpoints = path.gates
	task.gate_normals = path.normals
	task.challenge = {"flight_path": path.points, "flight_ups": path.ups, "gate_path_indices": path.indices, "gate_ups": path.gate_ups}
	var guide := RaceRouteGuide.new()
	root.add_child(guide)
	guide.position = task.acceptance_point()
	guide.configure(task, 0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 180
	camera.position = Vector3(90, 240, -180) if mode == 3 else Vector3(210, 240, 180)
	camera.look_at(Vector3(85, 140, 0))
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://../.local/test-results/spatial-routes"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join("spatial%d.png" % mode)) == OK, "capture spatial bank frame mode=" + str(mode))
	guide.queue_free()
	camera.queue_free()

func plane_error(points: PackedVector3Array) -> float:
	var forward := (points[-1] - points[0]).normalized()
	var normal := Vector3.ZERO
	var best := 0.0
	for p in points:
		var cross := forward.cross(p - points[0])
		if cross.length() > best: best = cross.length(); normal = cross.normalized()
	var error := 0.0
	for p in points: error = maxf(error, absf((p - points[0]).dot(normal)))
	return error

func max_curvature(points: PackedVector3Array) -> float:
	var result := 0.0
	for index in range(1, points.size() - 1):
		var incoming := points[index] - points[index - 1]
		var outgoing := points[index + 1] - points[index]
		result = maxf(result, incoming.normalized().distance_to(outgoing.normalized()) / maxf(0.01, (incoming.length() + outgoing.length()) * 0.5))
	return result

func history(catalog: ContentCatalog, record: Dictionary) -> void:
	var world := BiomeWorld.new(catalog, record.seed)
	var current := world.mission(record.id)
	var old := world.mission(current.id.trim_suffix(":spatial"))
	var store := ProgressStore.new(catalog, "user://tests/spatial_%d/progress.json" % Time.get_ticks_usec())
	store.regions = world
	var old_path: PackedVector3Array = old.challenge.get("flight_path", old.checkpoints).duplicate()
	store.accept_mission(old.id)
	var state: Dictionary = store.data.assignments[old.id].duplicate(true)
	state.stage = 1
	store.save_challenge_state(old.id, state)
	var rebuilt := BiomeWorld.new(catalog, record.seed)
	store = ProgressStore.new(catalog, store.path)
	store.regions = rebuilt
	check(rebuilt.mission(old.id).challenge.get("flight_path", old.checkpoints) == old_path and store.data.assignments[old.id].stage == 1 and not old.challenge.has("gate_ups"), "0.23 active layout reloads exact curve, stage and original unbanked frame")
	check(rebuilt.mission(current.id).checkpoints == current.checkpoints and rebuilt.mission(current.id).challenge.flight_ups == current.challenge.flight_ups, "cold generation reproduces sparse gates and body frame exactly")
	state = store.data.assignments[old.id].duplicate(true)
	state.stage = old.checkpoints.size()
	store.save_challenge_state(old.id, state)
	store.complete_mission(old.id)
	var credits: int = store.data.credits
	var accepted := store.accept_mission(current.id)
	state = store.data.assignments[current.id].duplicate(true)
	state.stage = current.checkpoints.size()
	store.save_challenge_state(current.id, state)
	check(accepted.ok and store.complete_mission(current.id).ok and store.data.credits == credits, "sparse spatial replay shares the historical one-time reward after reload")
