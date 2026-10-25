class_name AcroCourses
extends RefCounted
## Versioned close manoeuvres preserve the existing, already checked district route.
const MAX_GATES := 36
const MAX_TURN := 132.0

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	if plan.kind not in ["surface", "sky"]: return
	var rng := field.rng_for(plan.key, 71339)
	var city: bool = plan.kind == "surface" and plan.biomes[0].provider_id == "base.generator.modular_city"
	var city_cache := {}
	for slot in plan.missions.size():
		var old: MissionDefinition = plan.missions[slot]
		if old.kind != "race": continue
		var obstacles: Array[Dictionary] = []
		for object: Dictionary in plan.objects:
			if not object.id.begins_with(old.id + "/") or object.id.begins_with(old.id + "/entry"): obstacles.append(object)
		if city:
			var anchor: Vector2 = field.surface_site(plan.key).anchor
			var center := Vector3(anchor.x, 0, anchor.y) if old.challenge.get("precision_revision", 0) > 0 else old.acceptance_point()
			obstacles.append_array(FlowCourses._city_objects(plan, field, entrances, center, city_cache))
		var bins := FlowCourses._prepare_obstacles(obstacles)
		var sampler: BiomeTerrain = BiomeTerrain.new(field, Vector2(old.target_point.x, old.target_point.z), entrances) if plan.kind == "surface" else null
		var half := float(old.challenge.gate_half)
		var points := _layout(old.checkpoints, bins, sampler, half, rng)
		if points == old.checkpoints or points.size() < 7: continue
		var task := old.duplicate() as MissionDefinition
		task.id = old.id + ":acro"
		task.location_id = task.id + ":target"
		task.history_id = old.history_id if not old.history_id.is_empty() else old.id
		task.checkpoints = points
		task.gate_normals = PackedVector3Array()
		task.challenge = old.challenge.duplicate(true)
		task.challenge.acro_revision = 1
		task.challenge.route_revision = 3
		task.description = "依次穿门，沿引导线完成近距转向、上下叠门和升降变线；长短航段混合，无倒计时。箭头是穿门方向，仍需观察实体障碍。"
		task.legacy_objects = []
		var retained: Array[Dictionary] = []
		old.legacy_objects = []
		for object: Dictionary in plan.objects:
			if object.id.begins_with(old.id + "/") and not object.id.begins_with(old.id + "/entry"): old.legacy_objects.append(object)
			else: retained.append(object)
		plan.objects = retained
		for index in points.size():
			var normal := gate_normal(points, index)
			task.gate_normals.append(normal)
			MissionCourses.gate(plan.objects, task.id + "/gate%d" % index, points[index], normal, half)
		task.target_point = points[0]
		task.target_bounds = AABB(points[0] - Vector3.ONE * 2, Vector3.ONE * 4)
		plan.legacy_missions.append(old)
		plan.missions[slot] = task
		for location: MapLocation in plan.locations.duplicate():
			if location.id != old.location_id: continue
			plan.locations.erase(location)
			plan.legacy_locations.append(location)
			var replacement := location.duplicate() as MapLocation
			replacement.id = task.location_id
			replacement.description = task.description
			plan.locations.append(replacement)

static func _layout(original: PackedVector3Array, bins: Dictionary, sampler: BiomeTerrain, half: float, rng: RandomNumberGenerator) -> PackedVector3Array:
	var path := PackedVector3Array([original[0]])
	for leg in range(1, original.size()):
		var a := original[leg - 1]
		var b := original[leg]
		var delta := b - a
		var length := delta.length()
		var side := delta.normalized().cross(Vector3.UP).normalized()
		var remaining := MAX_GATES - path.size() - (original.size() - leg)
		var chosen := PackedVector3Array()
		var first := rng.randi_range(0, 3)
		if length >= 24 and remaining >= 2:
			for attempt in 4:
				var pattern := (first + attempt) % 4
				var extra := PackedVector3Array()
				var groups := mini(ceili(length / 65), remaining / 2)
				for group in groups:
					var t := float(group + 1) / (groups + 1)
					var center := a.lerp(b, t)
					if pattern < 2:
						var lift := minf(13, length / (groups + 1) * 0.55)
						center += side * (rng.randf_range(-4, 4) if pattern == 0 else 0)
						extra.append(center + Vector3.UP * 2)
						extra.append(center + Vector3.UP * (2 + lift))
					else:
						var spread := minf(0.12, 7 / length)
						var width: float = rng.randf_range(5, 8) if pattern == 2 else 0.0
						extra.append(a.lerp(b, t - spread) + side * width + Vector3.UP * (8 if pattern == 3 else 5))
						extra.append(a.lerp(b, t + spread) - side * width + Vector3.UP * 2)
				var trial := path.duplicate()
				trial.append_array(extra)
				trial.append(b)
				if _clear(trial, maxi(0, path.size() - 1), bins, sampler, half): chosen = trial; break
		if chosen.is_empty():
			chosen = path.duplicate()
			chosen.append(b)
			if not _clear(chosen, maxi(0, path.size() - 1), bins, sampler, half): return original
		path = chosen
	return path

static func _clear(points: PackedVector3Array, start: int, bins: Dictionary, sampler: BiomeTerrain, half: float) -> bool:
	for index in range(start, points.size()):
		var p := points[index]
		if p.y > 275: return false
		if index > 0:
			var previous := points[index - 1]
			if p.distance_to(previous) < 8 or not FlowCourses._segment_clear(previous, p, bins): return false
			if sampler != null:
				var steps := ceili(previous.distance_to(p) / 4)
				for step in steps + 1:
					var probe := previous.lerp(p, float(step) / maxi(1, steps))
					if probe.y < sampler.sample(probe.x, probe.z) + 0.8: return false
		if index > 0 and index < points.size() - 1:
			var incoming := (p - points[index - 1]).normalized()
			var outgoing := (points[index + 1] - p).normalized()
			if incoming.dot(outgoing) < cos(deg_to_rad(MAX_TURN)): return false
		var basis := FlightChallengeRules.gate_basis(gate_normal(points, index))
		for x: float in [-half - 0.4, 0, half + 0.4]:
			for y: float in [-half - 0.4, 0, half + 0.4]:
				var probe := p + basis * Vector3(x, y, 0)
				if not FlowCourses._segment_clear(probe, probe, bins): return false
				if sampler != null and probe.y < sampler.sample(probe.x, probe.z) + 0.2: return false
	return true

static func gate_normal(points: PackedVector3Array, index: int) -> Vector3:
	if index == 0: return (points[1] - points[0]).normalized()
	var incoming := (points[index] - points[index - 1]).normalized()
	if index == points.size() - 1: return incoming
	var outgoing := (points[index + 1] - points[index]).normalized()
	var normal := (incoming + outgoing).normalized()
	var axis := incoming.cross(outgoing).normalized()
	if axis.is_zero_approx(): return normal
	# Alternate the frame tilt, but leave both entry and exit clear. A gate
	# facing only the incoming leg can put its top/side bar across a sharp exit.
	var half_angle := acos(clampf(incoming.dot(outgoing), -1, 1)) * 0.5
	var bias := minf(deg_to_rad(12), maxf(0, deg_to_rad(70) - half_angle))
	return normal.rotated(axis, bias if index % 2 else -bias)
