class_name SpatialCourses
extends RefCounted
## Spatial centreline + transported body frame + sparse geometric landmarks.
const MAX_GATES := 64
const STEP := 1.1
const MIN_SPACING := 8.0
const LANDMARK_ERROR := 5.0
const TURN_BUDGET := 80.0

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	if plan.kind not in ["surface", "sky"]: return
	var cache := {}
	for slot in plan.missions.size():
		var old: MissionDefinition = plan.missions[slot]
		if old.kind != "race": continue
		var source := old
		var base_id := old.id.trim_suffix(":smooth").trim_suffix(":acro")
		for historical: MissionDefinition in plan.legacy_missions:
			if historical.id == base_id: source = historical; break
		var environment := _environment(plan, field, entrances, old, source, cache)
		var rng := field.rng_for(plan.key, 94127 + slot * 1999)
		var phase := rng.randi_range(0, 31)
		var chosen := {}
		var half := float(old.challenge.gate_half)
		for finish in range(source.checkpoints.size(), 1, -1):
			for variant in 5:
				var controls := source.checkpoints.slice(0, finish)
				# Clearance is tested after deformation; never flatten the whole tour.
				var lift: float = [12, 24, 6, 0, 3][variant]
				for index in controls.size(): controls[index] += Vector3.UP * lift
				var candidate := build(controls, phase + variant, 1.0 - variant * 0.18)
				if not candidate.is_empty() and _clear(candidate, environment, half): chosen = candidate; break
			if not chosen.is_empty(): break
		if chosen.is_empty() and old.challenge.has("flight_path"):
			# Tight buildings can retain their checked centreline while removing
			# redundant gates and adding a continuous body-relative bank frame.
			var points: PackedVector3Array = old.challenge.flight_path.duplicate()
			var tangents := PackedVector3Array()
			for index in points.size(): tangents.append((points[mini(index + 1, points.size() - 1)] - points[maxi(0, index - 1)]).normalized())
			for response: float in [8, 4, 2, 1]:
				var candidate := finish_path({"points": points, "tangents": tangents, "features": ["retained_curve"], "keys": []}, response)
				if candidate.is_empty(): continue
				if _clear(candidate, environment, half): chosen = candidate; break
				_snap_legacy(candidate, old)
				if _clear(candidate, environment, half): chosen = candidate; break
			if chosen.is_empty():
				var retained := finish_path({"points": points, "tangents": tangents, "features": [], "keys": []})
				if not retained.is_empty():
					_snap_legacy(retained, old)
					retained.retained = true
					if _clear(retained, environment, half): chosen = retained
		if chosen.is_empty(): continue
		var task := old.duplicate() as MissionDefinition
		task.id = old.id + ":spatial"
		task.location_id = task.id + ":target"
		task.history_id = old.history_id if not old.history_id.is_empty() else old.id
		task.checkpoints = chosen.gates
		task.gate_normals = chosen.normals
		task.challenge = old.challenge.duplicate(true)
		task.challenge.acro_revision = 3
		task.challenge.spatial_revision = 1
		task.challenge.route_revision = 5
		task.challenge.flight_path = chosen.points
		task.challenge.flight_ups = chosen.ups
		task.challenge.gate_ups = chosen.gate_ups
		task.challenge.gate_path_indices = chosen.indices
		task.challenge.manoeuvres = chosen.features
		task.challenge.body_push_curvature = chosen.push_curvature
		task.challenge.body_roll_per_meter = chosen.roll_rate
		task.challenge.geometry_retained = "retained_curve" in chosen.features or "key_nodes_only" in chosen.features
		task.challenge.legacy_frame_constraints = chosen.get("retained", false)
		task.description = "依次穿过关键节点的门，直线与缓弯保留自由走线空间；沿曲线预判急缓变化和三维转向。门框倾斜提示推荐的横滚姿态，倒飞时仍以机体上方作为拉杆方向。无倒计时。"
		task.legacy_objects = []
		ContinuousCourses._retire(plan, old)
		for index in task.checkpoints.size(): MissionCourses.gate(plan.objects, task.id + "/gate%d" % index, task.checkpoints[index], task.gate_normals[index], half, chosen.gate_ups[index])
		task.target_point = task.checkpoints[0]
		task.target_bounds = AABB(task.target_point - Vector3.ONE * 2, Vector3.ONE * 4)
		plan.missions[slot] = task
		ContinuousCourses._replace_location(plan, old, task)

static func _environment(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary], old: MissionDefinition, source: MissionDefinition, cache: Dictionary) -> Dictionary:
	var obstacles: Array[Dictionary] = []
	for object: Dictionary in plan.objects:
		if object.id.begins_with(old.id + "/") and not object.id.begins_with(old.id + "/entry"): continue
		obstacles.append(object)
		if plan.kind == "sky" and object.get("primitive", "box") == "terrain": obstacles.append(WorldProvider.box("island_clearance", object.center, object.size, Color.WHITE))
	if plan.kind == "surface" and plan.biomes[0].provider_id == "base.generator.modular_city":
		var anchor: Vector2 = field.surface_site(plan.key).anchor
		var center := Vector3(anchor.x, 0, anchor.y) if source.challenge.get("precision_revision", 0) > 0 else source.acceptance_point()
		obstacles.append_array(FlowCourses._city_objects(plan, field, entrances, center, cache))
		var key := WorldGenerator.key_at(center)
		for x in range(key.x - 3, key.x + 4):
			for z in range(key.z - 3, key.z + 4):
				if field.nearest(Vector2(x * 64 + 32, z * 64 + 32)).id != plan.id: obstacles.append(WorldProvider.box("district_boundary", Vector3(x * 64 + 32, 150, z * 64 + 32), Vector3(64, 600, 64), Color.WHITE))
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			for sign_value: float in [-1, 1]:
				var center_point := Vector3(key.x * 64 + 32, 150, key.z * 64 + 32)
				obstacles.append(WorldProvider.box("checked_boundary", center_point + axis * sign_value * 222, Vector3(4, 600, 448) if axis == Vector3.RIGHT else Vector3(448, 600, 4), Color.WHITE))
	for task: MissionDefinition in plan.missions:
		if task.kind != "balloons": continue
		for launch: Vector3 in task.checkpoints:
			var height := maxf(0, float(task.challenge.height_limit) - launch.y)
			obstacles.append(WorldProvider.box("balloon_clearance", launch + Vector3.UP * height * 0.5, Vector3(3.4, height + 2.4, 3.4), Color.WHITE))
	var reserved: Array[PackedVector3Array] = []
	for task: MissionDefinition in plan.missions:
		if task.kind == "race" and task.id != old.id: reserved.append(task.challenge.get("flight_path", task.checkpoints))
	return {"bins": FlowCourses._prepare_obstacles(obstacles), "sampler": BiomeTerrain.new(field, Vector2(source.target_point.x, source.target_point.z), entrances), "bounds": plan.biomes[0].region_bounds.grow(-2) if plan.kind == "sky" else AABB(), "reserved_paths": reserved}

static func _clear(path: Dictionary, environment: Dictionary, half: float) -> bool:
	if not path.get("retained", false) and (path.push_curvature > 1.0 / 40 or path.roll_rate > deg_to_rad(30)): return false
	if not ContinuousCourses.clear(path, environment.bins, environment.sampler, half, environment.bounds, true): return false
	var frames: Array[Dictionary] = []
	for index in path.gates.size(): MissionCourses.gate(frames, "reserve%d" % index, path.gates[index], path.normals[index], half, path.gate_ups[index])
	var bins := FlowCourses._prepare_obstacles(frames)
	for other: PackedVector3Array in environment.reserved_paths:
		for index in range(1, other.size()):
			if not FlowCourses._segment_clear(other[index - 1], other[index], bins): return false
	return true

static func _snap_legacy(path: Dictionary, old: MissionDefinition) -> void:
	var old_indices: PackedInt32Array = old.challenge.gate_path_indices
	var selected := {0: true, old_indices.size() - 1: true}
	for index: int in path.indices:
		var closest := 0
		for gate in old_indices.size():
			if absi(old_indices[gate] - index) < absi(old_indices[closest] - index): closest = gate
		selected[closest] = true
	var ordered := selected.keys()
	ordered.sort()
	path.indices = PackedInt32Array()
	path.gates = PackedVector3Array()
	path.normals = PackedVector3Array()
	path.gate_ups = PackedVector3Array()
	for gate: int in ordered:
		path.indices.append(old_indices[gate])
		path.gates.append(old.checkpoints[gate])
		path.normals.append(old.gate_normals[gate])
		path.gate_ups.append(FlightChallengeRules.gate_basis_for(old, gate).y)
	path.features = ["key_nodes_only"]
	# A narrow legacy passage keeps its original frame orientations. Transport
	# and smoothly distribute the bank between these anchors, rather than snap
	# to world-up at every dense sample.
	var ups: PackedVector3Array = path.ups.duplicate()
	for gate in range(1, path.indices.size()):
		var first: int = path.indices[gate - 1]
		var last: int = path.indices[gate]
		var carried := PackedVector3Array([FlightChallengeRules.gate_basis(path.tangents[first], path.gate_ups[gate - 1]).y])
		for index in range(first + 1, last + 1): carried.append((Quaternion(path.tangents[index - 1], path.tangents[index]) * carried[-1]).normalized())
		var target := FlightChallengeRules.gate_basis(path.tangents[last], path.gate_ups[gate]).y
		var bank: float = Vector3(carried[-1]).signed_angle_to(target, path.tangents[last])
		for index in range(first, last + 1):
			var t: float = (path.distances[index] - path.distances[first]) / maxf(0.001, path.distances[last] - path.distances[first])
			ups[index] = Vector3(carried[index - first]).rotated(path.tangents[index], bank * t * t * (3 - 2 * t))
	path.ups = ups
	path.push_curvature = body_push_curvature(path.tangents, ups, path.distances)
	path.roll_rate = _roll_rate(path.tangents, ups, path.distances)

static func build(source: PackedVector3Array, style: int, scale: float = 1.0) -> Dictionary:
	if source.size() < 2: return {}
	var path := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "features": [], "keys": []}
	var entries := source.duplicate()
	var exits := source.duplicate()
	var handles := PackedFloat32Array()
	handles.resize(source.size())
	var sharp := {}
	for index in range(1, source.size() - 1):
		var incoming := (source[index] - source[index - 1]).normalized()
		var outgoing := (source[index + 1] - source[index]).normalized()
		var turn := acos(clampf(incoming.dot(outgoing), -1, 1))
		if turn < 0.01: continue
		if turn > deg_to_rad(145): return {}
		# Radius belongs to the manoeuvre, never the sign of world-space Y.
		var radius: float = [8.0, 15.0, 32.0][posmod(style + index, 3)]
		var trim := radius * tan(turn * 0.5)
		if trim > minf(source[index].distance_to(source[index - 1]), source[index].distance_to(source[index + 1])) * 0.45: return {}
		entries[index] -= incoming * trim
		exits[index] += outgoing * trim
		handles[index] = 4.0 / 3.0 * radius * tan(turn * 0.25)
		sharp[index] = radius <= 15 and turn > deg_to_rad(35)
	for leg in range(1, source.size()):
		_leg(path, exits[leg - 1], entries[leg], style + leg - 1, scale, leg == source.size() - 1)
		if path.get("terminal", false): break
		if leg < source.size() - 1 and handles[leg] > 0:
			var begin: int = path.points.size() - 1
			var incoming := (source[leg] - source[leg - 1]).normalized()
			var outgoing := (source[leg + 1] - source[leg]).normalized()
			ContinuousCourses._bezier(path, entries[leg], entries[leg] + incoming * handles[leg], exits[leg] - outgoing * handles[leg], exits[leg])
			if sharp[leg]: path.keys.append((begin + path.points.size() - 1) / 2)
			path.features.append("tight_turn" if sharp[leg] else "wide_turn")
	return finish_path(path)

static func _leg(path: Dictionary, a: Vector3, b: Vector3, style: int, scale: float, terminal: bool) -> void:
	var length := a.distance_to(b)
	if length < 0.01: return
	var forward := (b - a).normalized()
	var side := forward.cross(Vector3.UP if absf(forward.y) < 0.95 else Vector3.FORWARD).normalized()
	var up := side.cross(forward)
	var bank := 0.45 + posmod(style, 7) * 0.47
	var plane := side * cos(bank) + up * sin(bank)
	var mode := posmod(style, 4)
	if mode == 0 and length >= 80:
		var radius := 16.0 if posmod(style / 4, 2) == 0 else 28.0
		var advance := radius * 2
		var begin := a.lerp(b, 0.5) - forward * advance * 0.5
		ContinuousCourses._line(path, a, begin)
		var steps := ceili((TAU * radius + advance) / STEP)
		for step in steps + 1:
			var angle := TAU * step / steps
			ContinuousCourses._push(path, begin + forward * (radius * sin(angle) + advance * angle / TAU) + plane * radius * (1 - cos(angle)), forward * (radius * cos(angle) + advance / TAU) + plane * radius * sin(angle))
		ContinuousCourses._line(path, begin + forward * advance, b)
		path.features.append("inclined_loop")
	elif mode == 3 and terminal and length >= 85:
		var radius := 18.0 + posmod(style, 3) * 5
		var begin := b - forward * radius
		ContinuousCourses._line(path, a, begin)
		var steps := ceili(PI * radius / STEP)
		for step in steps + 1:
			var angle := PI * step / steps
			ContinuousCourses._push(path, begin + forward * radius * sin(angle) - plane * radius * (1 - cos(angle)), forward * cos(angle) - plane * sin(angle))
		ContinuousCourses._line(path, begin - plane * radius * 2, begin - plane * radius * 2 - forward * 20)
		path.features.append("banked_split_s")
		path.terminal = true
	else:
		var width := minf(minf(30, length * 0.26), length * length / (6 * PI * PI * 7)) * scale
		var steps := maxi(4, ceili(length * 2.0 / STEP))
		for step in steps + 1:
			var t := float(step) / steps
			var envelope := pow(sin(PI * t), 2)
			var envelope_slope := PI * sin(TAU * t)
			var angle := bank + (TAU * t if mode == 1 else 0.9 * envelope * (-1 if style % 2 else 1))
			var angle_slope := TAU if mode == 1 else 0.9 * envelope_slope * (-1 if style % 2 else 1)
			var radial := side * cos(angle) + up * sin(angle)
			var radial_slope := (-side * sin(angle) + up * cos(angle)) * angle_slope
			var wave := envelope if mode == 1 else sin(TAU * t) * envelope
			var wave_slope := envelope_slope if mode == 1 else TAU * cos(TAU * t) * envelope + sin(TAU * t) * envelope_slope
			ContinuousCourses._push(path, a.lerp(b, t) + radial * width * wave, forward * length + (radial * wave_slope + radial_slope * wave) * width)
		path.features.append("corkscrew" if mode == 1 else "spatial_s")

static func finish_path(path: Dictionary, roll_response: float = 8.0) -> Dictionary:
	if path.points.size() < 2: return {}
	_frames(path, roll_response)
	var selected := {0: true, path.points.size() - 1: true}
	for key: int in path.get("keys", []): selected[key] = true
	# RDP finds spatially meaningful extrema; a straight has only its two ends.
	var stack := [Vector2i(0, path.points.size() - 1)]
	while not stack.is_empty():
		var pair: Vector2i = stack.pop_back()
		var worst := LANDMARK_ERROR
		var split := -1
		for index in range(pair.x + 1, pair.y):
			var distance: float = Vector3(path.points[index]).distance_to(Geometry3D.get_closest_point_to_segment(path.points[index], path.points[pair.x], path.points[pair.y]))
			if distance > worst: worst = distance; split = index
		if split >= 0:
			selected[split] = true
			stack.append(Vector2i(pair.x, split))
			stack.append(Vector2i(split, pair.y))
	var turning := 0.0
	var turns := PackedFloat32Array([0])
	for index in range(1, path.points.size()):
		var angle := acos(clampf(Vector3(path.tangents[index - 1]).dot(path.tangents[index]), -1, 1))
		turning += angle
		turns.append(turns[-1] + angle)
		if turning >= deg_to_rad(TURN_BUDGET): selected[index] = true; turning = 0
	var ordered := selected.keys()
	ordered.sort()
	var indices := PackedInt32Array([0])
	for index: int in ordered:
		if index == 0: continue
		if Vector3(path.points[index]).distance_to(path.points[indices[-1]]) < MIN_SPACING:
			if index == path.points.size() - 1 and indices.size() > 1: indices[-1] = index
			continue
		indices.append(index)
	if indices[-1] != path.points.size() - 1: return {}
	# Merge overlapping curvature/geometry picks. Tight apex landmarks survive;
	# broad arcs need only enough nodes to describe their shape and direction.
	for slot in range(indices.size() - 2, 0, -1):
		if indices[slot] in path.get("keys", []): continue
		var a: int = indices[slot - 1]
		var b: int = indices[slot + 1]
		if turns[b] - turns[a] > deg_to_rad(85): continue
		var redundant := true
		for index in range(a + 1, b):
			if Vector3(path.points[index]).distance_to(Geometry3D.get_closest_point_to_segment(path.points[index], path.points[a], path.points[b])) > LANDMARK_ERROR: redundant = false; break
		if redundant: indices.remove_at(slot)
	# A self-crossing is allowed; a frame on one branch must not obstruct the
	# other branch. Drop such a frame instead of forbidding the manoeuvre.
	for slot in range(indices.size() - 2, 0, -1):
		if _frame_obstructs_path(path, indices[slot]): indices.remove_at(slot)
	if indices.size() < 2 or indices.size() > MAX_GATES or path.distances[-1] < 70: return {}
	path.indices = indices
	path.gates = PackedVector3Array()
	path.normals = PackedVector3Array()
	path.gate_ups = PackedVector3Array()
	for index in indices:
		path.gates.append(path.points[index])
		path.normals.append(path.tangents[index])
		path.gate_ups.append(path.ups[index])
	return path

static func _frame_obstructs_path(path: Dictionary, index: int) -> bool:
	var inverse := FlightChallengeRules.gate_basis(path.tangents[index], path.ups[index]).inverse()
	var center: Vector3 = path.points[index]
	var previous: Vector3 = inverse * (path.points[0] - center)
	# Conservative largest supported course frame; the final clearance pass
	# still checks the actual aperture and all environmental geometry.
	var boxes: Array[AABB] = []
	for side: float in [-1, 1]:
		boxes.append(AABB(Vector3(side * 3.3 - 0.225, -3.5, -0.225), Vector3(0.45, 7, 0.45)).grow(0.75))
		boxes.append(AABB(Vector3(-3.5, side * 3.3 - 0.225, -0.225), Vector3(7, 0.45, 0.45)).grow(0.75))
	for point in range(1, path.points.size()):
		var next: Vector3 = inverse * (path.points[point] - center)
		if minf(previous.z, next.z) <= 1 and maxf(previous.z, next.z) >= -1:
			for box in boxes:
				if box.has_point(previous) or box.has_point(next) or box.intersects_segment(previous, next) != null: return true
		previous = next
	return false

static func _frames(path: Dictionary, roll_response: float = 8.0) -> void:
	var count: int = path.points.size()
	var reference := PackedVector3Array([FlightChallengeRules.gate_basis(path.tangents[0]).y])
	var distances := PackedFloat32Array([0])
	for index in range(1, count):
		var rotation := Quaternion(path.tangents[index - 1], path.tangents[index])
		reference.append((rotation * reference[-1]).normalized())
		distances.append(distances[-1] + Vector3(path.points[index]).distance_to(path.points[index - 1]))
	var angles := PackedFloat32Array()
	angles.resize(count)
	var previous := -1
	for index in count:
		var before := maxi(0, index - 1)
		var after := mini(count - 1, index + 1)
		var bend: Vector3 = path.tangents[after] - path.tangents[before]
		if bend.length() / maxf(0.001, distances[after] - distances[before]) < 0.003: continue
		var forward: Vector3 = path.tangents[index]
		bend = (bend - forward * bend.dot(forward)).normalized()
		var angle := reference[index].signed_angle_to(bend, forward)
		if previous >= 0: angle = angles[previous] + wrapf(angle - angles[previous], -PI, PI)
		for gap in range(previous + 1, index + 1): angles[gap] = lerpf(angles[previous], angle, (distances[gap] - distances[previous]) / maxf(0.001, distances[index] - distances[previous])) if previous >= 0 else angle
		previous = index
	for gap in range(maxi(0, previous + 1), count): angles[gap] = angles[previous] if previous >= 0 else 0
	var ups := PackedVector3Array()
	for index in count:
		var total := 0.0
		var weights := 0.0
		for neighbor in range(maxi(0, index - 20), mini(count, index + 21)):
			var weight := maxf(0, 1 - absf(distances[neighbor] - distances[index]) / roll_response)
			total += angles[neighbor] * weight
			weights += weight
		ups.append(reference[index].rotated(path.tangents[index], total / maxf(0.001, weights)).normalized())
	path.ups = ups
	path.distances = distances
	path.push_curvature = body_push_curvature(path.tangents, ups, distances)
	path.roll_rate = _roll_rate(path.tangents, ups, distances)

static func _roll_rate(tangents: PackedVector3Array, ups: PackedVector3Array, distances: PackedFloat32Array) -> float:
	var result := 0.0
	for index in range(1, tangents.size()):
		var transported: Vector3 = Quaternion(tangents[index - 1], tangents[index]) * ups[index - 1]
		result = maxf(result, absf(transported.signed_angle_to(ups[index], tangents[index])) / maxf(0.001, distances[index] - distances[index - 1]))
	return result

static func body_push_curvature(tangents: PackedVector3Array, ups: PackedVector3Array, distances: PackedFloat32Array) -> float:
	var push := 0.0
	for index in range(1, tangents.size()):
		var curvature := (tangents[index] - tangents[index - 1]) / maxf(0.001, distances[index] - distances[index - 1])
		push = maxf(push, -curvature.dot((ups[index] + ups[index - 1]).normalized()))
	return push
