class_name ContinuousCourses
extends RefCounted
## Build a C1 flight path first; gates, guide and clearance use that same path.
const MAX_GATES := 96
const GATE_SPACING := 12.0
const DESIGN_SPEED := 14.0
const DOWN_RADIUS := 40.0
const SAMPLE_STEP := 1.25

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	if plan.kind not in ["surface", "sky"]: return
	var city: bool = plan.kind == "surface" and plan.biomes[0].provider_id == "base.generator.modular_city"
	var cache := {}
	for slot in plan.missions.size():
		var old: MissionDefinition = plan.missions[slot]
		if old.kind != "race": continue
		# The old acro spikes remain available only to already accepted tasks.
		var source := old
		if old.id.ends_with(":acro"):
			for historical: MissionDefinition in plan.legacy_missions:
				if historical.id == old.id.trim_suffix(":acro"): source = historical; break
		var obstacles: Array[Dictionary] = []
		for object: Dictionary in plan.objects:
			if not object.id.begins_with(old.id + "/") or object.id.begins_with(old.id + "/entry"): obstacles.append(object)
		# Flow's box index deliberately skips terrain meshes. Conservative sector
		# bounds make descending sky manoeuvres respect the actual island bodies.
		if plan.kind == "sky":
			for object: Dictionary in plan.objects:
				if object.get("primitive", "box") == "terrain": obstacles.append(WorldProvider.box("island_clearance", object.center, object.size, Color.WHITE))
		if city:
			var anchor: Vector2 = field.surface_site(plan.key).anchor
			var center := Vector3(anchor.x, 0, anchor.y) if source.challenge.get("precision_revision", 0) > 0 else source.acceptance_point()
			obstacles.append_array(FlowCourses._city_objects(plan, field, entrances, center, cache))
			var center_key := WorldGenerator.key_at(center)
			for x in range(center_key.x - 3, center_key.x + 4):
				for z in range(center_key.z - 3, center_key.z + 4):
					if field.nearest(Vector2(x * 64 + 32, z * 64 + 32)).id != plan.id:
						obstacles.append(WorldProvider.box("district_boundary", Vector3(x * 64 + 32, 150, z * 64 + 32), Vector3(64, 600, 64), Color.WHITE))
			for axis in [Vector3.RIGHT, Vector3.BACK]:
				for sign_value: float in [-1, 1]:
					var midpoint := Vector3(center_key.x * 64 + 32, 150, center_key.z * 64 + 32)
					obstacles.append(WorldProvider.box("checked_boundary", midpoint + axis * sign_value * 222, Vector3(4, 600, 448) if axis == Vector3.RIGHT else Vector3(448, 600, 4), Color.WHITE))
		for other: MissionDefinition in plan.missions:
			if other.kind != "balloons": continue
			for launch: Vector3 in other.checkpoints:
				var height := maxf(0, float(other.challenge.height_limit) - launch.y)
				obstacles.append(WorldProvider.box("balloon_clearance", launch + Vector3.UP * height * 0.5, Vector3(3.4, height + 2.4, 3.4), Color.WHITE))
		var bins := FlowCourses._prepare_obstacles(obstacles)
		var sampler := BiomeTerrain.new(field, Vector2(source.target_point.x, source.target_point.z), entrances)
		var rng := field.rng_for(plan.key, 83117 + slot * 1999)
		var half := float(source.challenge.gate_half)
		var chosen := {}
		var flight_bounds: AABB = plan.biomes[0].region_bounds.grow(-2) if plan.kind == "sky" else AABB()
		var phase := rng.randi_range(0, 3)
		var controls := source.checkpoints.duplicate()
		var lowest := INF
		var highest := -INF
		for p: Vector3 in controls:
			lowest = minf(lowest, p.y)
			highest = maxf(highest, p.y)
		# Remove small random altitude jitter before making a flyable curve.
		# Real floor changes remain, while level tours no longer demand push-overs.
		if highest - lowest < 12 and highest < 270:
			for index in controls.size(): controls[index].y = highest + 2
		if plan.kind == "sky" and phase == 3:
			var closest: Dictionary = plan.shape.islands[0]
			for island: Dictionary in plan.shape.islands:
				if Vector3(island.point).distance_to(controls[0]) < Vector3(closest.point).distance_to(controls[0]): closest = island
			var away := (controls[0] - Vector3(closest.point)) * Vector3(1, 0, 1)
			if away.is_zero_approx(): away = Vector3.RIGHT
			for angle: float in [0, 0.6, -0.6, PI]:
				var departure := away.normalized().rotated(Vector3.UP, angle)
				var candidate := build(PackedVector3Array([controls[0], controls[0] + departure * 120]), 3)
				if not candidate.is_empty() and clear(candidate, bins, sampler, half, flight_bounds): chosen = candidate; break
		# Bounded search: shorten an obstructed tour, never force a curve through a wall.
		for start in mini(4, controls.size() - 1):
			if not chosen.is_empty(): break
			for finish in range(controls.size(), start + 1, -1):
				for variant in 4:
					var candidate := build(controls.slice(start, finish), (phase + variant) % 4, 1.0 - variant * 0.3)
					if not candidate.is_empty() and clear(candidate, bins, sampler, half, flight_bounds): chosen = candidate; break
				if not chosen.is_empty(): break
			if not chosen.is_empty(): break
		if chosen.is_empty():
			# A narrow historical building course may not fit a continuous replacement.
			# Revert its public slot to the environmental layout, not the v1 spikes.
			if source != old: _restore_source(plan, slot, old, source)
			continue
		var task := source.duplicate() as MissionDefinition
		task.id = old.id + ":smooth"
		task.location_id = task.id + ":target"
		task.history_id = source.history_id if not source.history_id.is_empty() else source.id
		task.checkpoints = chosen.gates
		task.gate_normals = chosen.normals
		task.challenge = source.challenge.duplicate(true)
		task.challenge.acro_revision = 2
		task.challenge.route_revision = 4
		task.challenge.flight_path = chosen.points
		task.challenge.gate_path_indices = chosen.indices
		task.challenge.manoeuvres = chosen.features
		task.challenge.design_speed = DESIGN_SPEED
		var names := PackedStringArray()
		var labels := {"s_bend": "S弯", "rounded_turn": "连续转弯", "wide_descent": "宽弧下降", "pull_loop": "大回环", "horizontal_orbit": "水平环绕", "split_s": "破S"}
		for feature: String in chosen.features:
			if not labels[feature] in names: names.append(labels[feature])
		task.description = "沿连续曲线依次穿门，门面顺着当地飞行方向。本航线包含%s，无倒计时。" % "、".join(names)
		if "split_s" in chosen.features: task.description += "破S前在直线段横滚至倒飞，再持续拉杆完成下降半回环，反方向水平出弯。"
		task.legacy_objects = []
		_retire(plan, old)
		for index in task.checkpoints.size():
			MissionCourses.gate(plan.objects, task.id + "/gate%d" % index, task.checkpoints[index], task.gate_normals[index], half)
		task.target_point = task.checkpoints[0]
		task.target_bounds = AABB(task.target_point - Vector3.ONE * 2, Vector3.ONE * 4)
		plan.missions[slot] = task
		_replace_location(plan, old, task)

static func _retire(plan: Dictionary, task: MissionDefinition) -> void:
	var retained: Array[Dictionary] = []
	task.legacy_objects = []
	for object: Dictionary in plan.objects:
		if object.id.begins_with(task.id + "/") and not object.id.begins_with(task.id + "/entry"): task.legacy_objects.append(object)
		else: retained.append(object)
	plan.objects = retained
	if not plan.legacy_missions.has(task): plan.legacy_missions.append(task)

static func _restore_source(plan: Dictionary, slot: int, old: MissionDefinition, source: MissionDefinition) -> void:
	_retire(plan, old)
	plan.objects.append_array(source.legacy_objects)
	source.legacy_objects = []
	plan.legacy_missions.erase(source)
	plan.missions[slot] = source
	_replace_location(plan, old, source)

static func _replace_location(plan: Dictionary, old: MissionDefinition, task: MissionDefinition) -> void:
	for location: MapLocation in plan.locations.duplicate():
		if location.id != old.location_id: continue
		plan.locations.erase(location)
		plan.legacy_locations.append(location)
		var replacement := location.duplicate() as MapLocation
		replacement.id = task.location_id
		replacement.description = task.description
		plan.locations.append(replacement)

static func build(source: PackedVector3Array, pattern: int, scale: float = 1.0) -> Dictionary:
	if source.size() < 2: return {}
	var path := {"points": PackedVector3Array(), "tangents": PackedVector3Array(), "features": []}
	var entries := source.duplicate()
	var exits := source.duplicate()
	var handles := PackedFloat32Array()
	handles.resize(source.size())
	for index in range(1, source.size() - 1):
		var incoming := (source[index] - source[index - 1]).normalized()
		var outgoing := (source[index + 1] - source[index]).normalized()
		var turn := acos(clampf(incoming.dot(outgoing), -1, 1))
		if turn < 0.01: continue
		if turn > deg_to_rad(145): return {}
		# An upright push-over needs a wider arc than a bank or pull-up.
		var radius := DOWN_RADIUS if outgoing.y < incoming.y - 0.08 else 12.0 if outgoing.y > incoming.y + 0.08 else 10.0
		var trim := radius * tan(turn * 0.5)
		if trim > minf(source[index].distance_to(source[index - 1]), source[index].distance_to(source[index + 1])) * 0.45: return {}
		entries[index] -= incoming * trim
		exits[index] += outgoing * trim
		handles[index] = 4.0 / 3.0 * radius * tan(turn * 0.25)
	for leg in range(1, source.size()):
		var a := exits[leg - 1]
		var b := entries[leg]
		var mode := (pattern + leg - 1) % 4
		straight(path, a, b, mode, scale, leg == source.size() - 1)
		if path.get("terminal", false): break
		if leg < source.size() - 1 and handles[leg] > 0:
			var incoming := (source[leg] - source[leg - 1]).normalized()
			var outgoing := (source[leg + 1] - source[leg]).normalized()
			_bezier(path, entries[leg], entries[leg] + incoming * handles[leg], exits[leg] - outgoing * handles[leg], exits[leg])
			path.features.append("wide_descent" if outgoing.y < incoming.y - 0.08 else "rounded_turn")
	return _gates(path)

static func straight(path: Dictionary, a: Vector3, b: Vector3, mode: int, scale: float, terminal: bool = false) -> void:
	var distance := a.distance_to(b)
	if distance < 0.01: return
	var forward := (b - a).normalized()
	var side := forward.cross(Vector3.UP).normalized()
	if side.is_zero_approx(): side = Vector3.RIGHT
	var up := side.cross(forward).normalized()
	# Loops use one continuous pull, including the inverted downward half.
	# Forward drift separates entry/exit frames instead of stacking two gates.
	if mode in [0, 1] and distance >= 88 and absf(forward.y) < 0.25:
		var radius := maxf(22.0, 24.0 * scale)
		var advance := radius * 2.0
		var begin := a.lerp(b, 0.5) - forward * advance * 0.5
		_line(path, a, begin)
		var plane := up if mode == 0 else side
		var steps := ceili((TAU * radius + advance) / SAMPLE_STEP)
		for step in steps + 1:
			var theta := TAU * step / steps
			_push(path, begin + forward * (radius * sin(theta) + advance * theta / TAU) + plane * radius * (1 - cos(theta)), forward * (radius * cos(theta) + advance / TAU) + plane * radius * sin(theta))
		_line(path, begin + forward * advance, b)
		path.features.append("pull_loop" if mode == 0 else "horizontal_orbit")
	elif mode == 3 and terminal and distance >= 75 and a.y > 65 and absf(forward.y) < 0.15:
		# Roll inverted on the straight approach, then pull through a descending
		# half-loop. Exit horizontally in the opposite direction (a split-S).
		var radius := maxf(22.0, 24.0 * scale)
		_line(path, a, b - forward * radius)
		var begin := b - forward * radius
		var steps := ceili(PI * radius / SAMPLE_STEP)
		for step in steps + 1:
			var theta := PI * step / steps
			_push(path, begin + forward * radius * sin(theta) - up * radius * (1 - cos(theta)), forward * cos(theta) - up * sin(theta))
		_line(path, begin - up * radius * 2, begin - up * radius * 2 - forward * 18)
		path.features.append("split_s")
		path.terminal = true
	else:
		var width := minf(minf(18.0, distance * 0.10), distance * distance / (6 * PI * PI * 12)) * scale
		var steps := ceili(distance * 1.5 / SAMPLE_STEP)
		for step in steps + 1:
			var t := float(step) / steps
			# Two lobes, with zero lateral velocity at both joins.
			var offset := width * sin(TAU * t) * pow(sin(PI * t), 2)
			var slope := width * (TAU * cos(TAU * t) * pow(sin(PI * t), 2) + PI * sin(TAU * t) * sin(TAU * t))
			_push(path, a.lerp(b, t) + side * offset, forward * distance + side * slope)
		path.features.append("s_bend")

static func _line(path: Dictionary, a: Vector3, b: Vector3) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / SAMPLE_STEP))
	for step in steps + 1: _push(path, a.lerp(b, float(step) / steps), b - a)

static func _bezier(path: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var steps := maxi(4, ceili((a.distance_to(b) + b.distance_to(c) + c.distance_to(d)) / SAMPLE_STEP))
	for step in steps + 1:
		var t := float(step) / steps
		var u := 1 - t
		_push(path, a * u * u * u + b * 3 * u * u * t + c * 3 * u * t * t + d * t * t * t, (b - a) * 3 * u * u + (c - b) * 6 * u * t + (d - c) * 3 * t * t)

static func _push(path: Dictionary, point: Vector3, tangent: Vector3) -> void:
	if not path.points.is_empty() and Vector3(path.points[-1]).distance_to(point) < 0.001: return
	path.points.append(point)
	path.tangents.append(tangent.normalized())

static func _gates(path: Dictionary) -> Dictionary:
	if path.points.size() < 2: return {}
	var gates := PackedVector3Array([path.points[0]])
	var normals := PackedVector3Array([path.tangents[0]])
	var indices := PackedInt32Array([0])
	var length := 0.0
	var since := 0.0
	for index in range(1, path.points.size()):
		var delta: float = Vector3(path.points[index]).distance_to(path.points[index - 1])
		length += delta
		since += delta
		if since >= GATE_SPACING and Vector3(path.points[index]).distance_to(gates[-1]) >= 8:
			gates.append(path.points[index])
			normals.append(path.tangents[index])
			indices.append(index)
			since = 0
	if indices[-1] != path.points.size() - 1:
		if Vector3(path.points[-1]).distance_to(gates[-1]) < 8 and gates.size() > 1:
			gates.remove_at(gates.size() - 1)
			normals.remove_at(normals.size() - 1)
			indices.remove_at(indices.size() - 1)
		gates.append(path.points[-1])
		normals.append(path.tangents[-1])
		indices.append(path.points.size() - 1)
	if gates.size() < 7 or gates.size() > MAX_GATES or length < 80: return {}
	path.gates = gates
	path.normals = normals
	path.indices = indices
	return path

static func clear(path: Dictionary, bins: Dictionary, sampler: BiomeTerrain, half: float, bounds: AABB = AABB(), curve_only: bool = false) -> bool:
	var frames: Array[Dictionary] = []
	for index in path.gates.size():
		var p: Vector3 = path.gates[index]
		var normal: Vector3 = path.normals[index]
		if index > 0 and p.distance_to(path.gates[index - 1]) < 8: return false
		# Both chords and the actual tangent must cross the opening head-on.
		if not curve_only:
			if index > 0 and (p - Vector3(path.gates[index - 1])).normalized().dot(normal) < 0.70: return false
			if index < path.gates.size() - 1 and (Vector3(path.gates[index + 1]) - p).normalized().dot(normal) < 0.70: return false
		var up_hint: Vector3 = path.gate_ups[index] if path.has("gate_ups") else path.ups[path.indices[index]] if path.has("ups") else Vector3.ZERO
		MissionCourses.gate(frames, "frame%d" % index, p, normal, half, up_hint)
	var frame_bins := FlowCourses._prepare_obstacles(frames)
	# Check entire frame edges, not just isolated corner probes.
	for frame in frames:
		var basis := Basis.from_euler(frame.rotation)
		var axis := Vector3.RIGHT if frame.size.x > frame.size.y else Vector3.UP
		var extent: float = maxf(frame.size.x, frame.size.y) * 0.5
		var a: Vector3 = frame.center - basis * axis * extent
		var b: Vector3 = frame.center + basis * axis * extent
		if not FlowCourses._segment_clear(a, b, bins): return false
		if sampler != null:
			for step in 9:
				var probe := a.lerp(b, step / 8.0)
				if probe.y < sampler.sample(probe.x, probe.z) + 0.3: return false
	for index in path.points.size():
		var p: Vector3 = path.points[index]
		var previous: Vector3 = path.points[maxi(0, index - 1)]
		if not p.is_finite() or p.y > 275: return false
		if bounds.has_volume() and not bounds.has_point(p): return false
		if sampler != null and p.y < sampler.sample(p.x, p.z) + 1.0: return false
		if not FlowCourses._segment_clear(previous, p, bins) or not FlowCourses._segment_clear(previous, p, frame_bins): return false
	# The approach, gate-to-gate chords and all other frames must also be safe.
	for index in path.gates.size():
		if curve_only and index > 0: continue
		var p: Vector3 = path.gates[index]
		var previous: Vector3 = path.gates[index - 1] if index > 0 else p - Vector3(path.normals[0]) * 14
		if not FlowCourses._segment_clear(previous, p, bins) or not FlowCourses._segment_clear(previous, p, frame_bins): return false
		if sampler != null:
			var steps := maxi(1, ceili(previous.distance_to(p) / SAMPLE_STEP))
			for step in steps + 1:
				var probe := previous.lerp(p, float(step) / steps)
				if probe.y < sampler.sample(probe.x, probe.z) + 1.0: return false
	return true
