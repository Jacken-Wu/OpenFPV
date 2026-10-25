class_name PrecisionCourses
extends RefCounted
## New layouts attach to existing floors/facades. Historical layouts stay playable.
static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	if plan.kind != "surface": return
	var city: bool = plan.biomes[0].provider_id == "base.generator.modular_city"
	var profile: String = plan.biomes[0].parameters.get("feature_profile", "")
	if not city and profile not in ["ruined_grid", "megastructure"]: return
	var obstacles: Array[Dictionary] = plan.objects.duplicate()
	var anchor: Vector2 = field.surface_site(plan.key).anchor
	var city_center := Vector3(anchor.x, 0, anchor.y)
	var city_key := WorldGenerator.key_at(city_center)
	var city_area := Rect2(Vector2((city_key.x - 3) * 64, (city_key.z - 3) * 64), Vector2.ONE * 448).grow(-8)
	if city:
		var cache := {}
		obstacles.append_array(FlowCourses._city_objects(plan, field, entrances, city_center, cache))
		for x in range(city_key.x - 3, city_key.x + 4):
			for z in range(city_key.z - 3, city_key.z + 4):
				if field.nearest(Vector2(x * 64 + 32, z * 64 + 32)).id != plan.id:
					obstacles.append(WorldProvider.box("precision_boundary", Vector3(x * 64 + 32, 150, z * 64 + 32), Vector3(64, 600, 64), Color.WHITE))
	var bins := FlowCourses._prepare_obstacles(obstacles)
	var terminals: Array[Vector3] = []
	var flight: Array[Vector3] = []
	for object in obstacles:
		if not object.get("solid", false) or object.get("primitive", "box") != "box" or object.id.begins_with("proc:"): continue
		var p: Vector3 = object.center
		var size: Vector3 = object.size
		if size.y <= 2 and size.x >= 6 and size.z >= 6 and p.y > 6:
			var point := p + Vector3.UP * (size.y / 2 + 0.9)
			if point.y < 260 and FlowCourses._segment_clear(point, point + Vector3.UP * 1.5, bins): terminals.append(point)
			flight.append(p + Vector3.UP * (size.y / 2 + 4.2))
		if object.id.ends_with("/wall") and size.y >= 8 and size.x >= 10 and size.z >= 10:
			for x: float in [-1, 1]:
				for z: float in [-1, 1]: flight.append(p + Vector3(x * (size.x / 2 + 5), size.y * 0.25, z * (size.z / 2 + 5)))
		if "/ruined_block/" in object.id and "/floor" in object.id:
			var center := Vector3(0, p.y + 4.2, p.z)
			# Floor halves flank a nine-metre open shaft, with open side approaches.
			var fields := String(object.id).split("/")
			center.x = anchor.x + float(fields[2]) * 38
			for offset: float in [-15, 0, 15]: flight.append(center + Vector3.RIGHT * offset)
	if city:
		# Candidate facades can be far from the service pad. Keep the entire
		# flight inside the building inventory we actually checked, centred on
		# the district rather than on that arbitrarily positioned pad.
		flight = flight.filter(func(point: Vector3) -> bool:
			var key := WorldGenerator.key_at(point)
			return city_area.has_point(Vector2(point.x, point.z)) and field.nearest(Vector2(key.x * 64 + 32, key.z * 64 + 32)).id == plan.id)
	var rng := field.rng_for(plan.key, 61001)
	_shuffle(terminals, rng)
	_shuffle(flight, rng)
	if flight.size() > 180: flight.resize(180)
	var reserved: Array[Vector3] = []
	# Clean routes first, so terminal consoles cannot obstruct them later.
	var slots: Array[int] = []
	for index in plan.missions.size():
		if plan.missions[index].kind == "regional" and plan.missions[index].challenge.mode == "clean": slots.push_front(index)
		else: slots.append(index)
	for slot in slots:
		var old: MissionDefinition = plan.missions[slot]
		if old.kind not in ["regional", "race"]: continue
		var mission := old.duplicate() as MissionDefinition
		mission.checkpoints = PackedVector3Array()
		mission.gate_normals = PackedVector3Array()
		mission.challenge = old.challenge.duplicate(true)
		mission.legacy_objects = []
		mission.id = old.id + ":precision"
		mission.location_id = mission.id + ":target"
		mission.history_id = old.history_id if not old.history_id.is_empty() else old.id
		mission.challenge.precision_revision = 1
		if old.kind == "regional":
			if old.challenge.mode == "clean":
				mission.checkpoints = _mega_path(plan, field, rng)
				if not _path_clear(mission.checkpoints, bins): continue
				mission.challenge.radius = 2.0
				mission.description = "沿编号穿行巨构低层廊道、楼板边缘和竖井，跨越不同中庭与楼层。无倒计时，任何真实碰撞或重置都会重开本次路线。"
			else:
				for point in terminals:
					var clear := true
					for previous: Vector3 in mission.checkpoints: clear = clear and previous.distance_to(point) >= 110
					for previous in reserved: clear = clear and previous.distance_to(point) >= 15
					for task: MissionDefinition in plan.missions:
						if task.kind == "regional" and task.challenge.mode == "clean":
							for index in range(1, task.checkpoints.size()): clear = clear and Geometry3D.get_closest_point_to_segment(point, task.checkpoints[index - 1], task.checkpoints[index]).distance_to(point) > 12
					if clear:
						mission.checkpoints.append(point)
						if mission.checkpoints.size() == old.checkpoints.size(): break
				if mission.checkpoints.size() != old.checkpoints.size(): continue
				mission.challenge.radius = 2.3
				mission.description = old.description + "\n终端位于现有残楼、楼层或高架边缘，按导航寻找；相邻终端至少相隔110米。"
				for point: Vector3 in mission.checkpoints: reserved.append(point)
		else:
			mission.challenge.gate_half = 2.2 if profile == "ruined_grid" else 2.5
			var points := _tour(flight, bins, rng, float(mission.challenge.gate_half))
			if profile == "megastructure": points = _mega_path(plan, field, rng)
			if points.size() < 7 or not _frames_clear(points, bins, float(mission.challenge.gate_half)): continue
			mission.checkpoints = points
			mission.challenge.route_revision = 2
			mission.description = "依次穿过贴近现有建筑的有向门，穿行楼层、屋顶或立面旁；长短航段与高差混合。按黄色箭头穿过开口平面，无倒计时。"
		if mission.checkpoints.is_empty(): continue
		var removed: Array[Dictionary] = []
		var retained: Array[Dictionary] = []
		for object: Dictionary in plan.objects:
			if object.id.begins_with(old.id + "/") and not object.id.begins_with(old.id + "/entry"):
				removed.append(object)
			else: retained.append(object)
		old.legacy_objects = removed
		plan.objects = retained
		mission.target_point = mission.checkpoints[0]
		mission.target_bounds = AABB(mission.target_point - Vector3.ONE * 2, Vector3.ONE * 4)
		if mission.kind == "race":
			for index in mission.checkpoints.size():
				var direction := _normal(mission.checkpoints, index)
				mission.gate_normals.append(direction)
				MissionCourses.gate(plan.objects, mission.id + "/gate%d" % index, mission.checkpoints[index], direction, float(mission.challenge.gate_half))
		elif mission.challenge.mode != "clean":
			for index in mission.checkpoints.size():
				var point := mission.checkpoints[index]
				RegionalSites.pad(plan.objects, mission.id + "/terminal%d" % index, point - Vector3.UP * 0.8)
				plan.objects.append(WorldProvider.box(mission.id + "/console%d" % index, point + Vector3(2, 0.4, 0), Vector3(1.1, 2, 1.2), Color("6b8d92"), true, "metal"))
		plan.legacy_missions.append(old)
		plan.missions[slot] = mission
		for location: MapLocation in plan.locations.duplicate():
			if location.id != old.location_id: continue
			plan.locations.erase(location)
			plan.legacy_locations.append(location)
			var replacement := location.duplicate() as MapLocation
			replacement.id = mission.location_id
			replacement.description = mission.description
			plan.locations.append(replacement)

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[other]
		values[other] = value

static func _mega_path(plan: Dictionary, field: BiomeField, rng: RandomNumberGenerator) -> PackedVector3Array:
	var anchor: Vector2 = field.surface_site(plan.key).anchor
	var base: float = plan.megabase
	var rotation := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2)
	var path := PackedVector3Array()
	for p: Vector3 in [Vector3(-156, 33.2, -85.5), Vector3(-52, 33.2, -85.5), Vector3(-52, 33.2, -104), Vector3(-52, 92, -104), Vector3(104, 92, -104), Vector3(104, 92, 52), Vector3(104, 133.2, 52), Vector3(104, 133.2, 70.5), Vector3(-85.5, 133.2, 70.5), Vector3(-104, 133.2, 70.5), Vector3(-104, 133.2, 52), Vector3(-104, 193.2, 52), Vector3(-104, 193.2, -104)]:
		path.append(Vector3(anchor.x, base, anchor.y) + rotation * p)
	return path

static func _normal(points: PackedVector3Array, index: int) -> Vector3:
	var incoming := (points[maxi(0, index - 1)] - points[index]).normalized()
	var outgoing := (points[mini(index + 1, points.size() - 1)] - points[index]).normalized()
	return (outgoing - incoming).normalized()

static func _path_clear(points: PackedVector3Array, bins: Dictionary) -> bool:
	for index in points.size():
		if not FlowCourses._segment_clear(points[maxi(0, index - 1)], points[index], bins): return false
	return true

static func _frames_clear(points: PackedVector3Array, bins: Dictionary, half: float) -> bool:
	if not _path_clear(points, bins): return false
	for index in points.size():
		if not _frame_clear(points, index, bins, half): return false
	return true

static func _frame_clear(points: PackedVector3Array, index: int, bins: Dictionary, half: float) -> bool:
	var basis := FlightChallengeRules.gate_basis(_normal(points, index))
	for x: float in [-half - 0.4, 0, half + 0.4]:
		for y: float in [-half - 0.4, 0, half + 0.4]:
			var probe := points[index] + basis * Vector3(x, y, 0)
			if not FlowCourses._segment_clear(probe, probe, bins): return false
	return true

static func _tour(candidates: Array[Vector3], bins: Dictionary, rng: RandomNumberGenerator, half: float) -> PackedVector3Array:
	if candidates.is_empty(): return PackedVector3Array()
	var best := PackedVector3Array()
	for attempt in 24:
		var path := PackedVector3Array([candidates[rng.randi_range(0, candidates.size() - 1)]])
		for step in 11:
			var choice := Vector3.INF
			var score := -INF
			for point in candidates:
				var distance := path[-1].distance_to(point)
				if distance < 18 or distance > 225 or point.y > 270: continue
				var fresh := true
				for previous: Vector3 in path: fresh = fresh and point.distance_to(previous) >= 14
				if not fresh: continue
				if path.size() > 1 and (path[-1] - path[-2]).normalized().dot((point - path[-1]).normalized()) < -0.01: continue
				if not FlowCourses._segment_clear(path[-1], point, bins): continue
				var candidate := path.duplicate()
				candidate.append(point)
				if not _frame_clear(candidate, candidate.size() - 1, bins, half) or not _frame_clear(candidate, candidate.size() - 2, bins, half): continue
				# Alternate broad sweeps with local facade turns, rather than always
				# jumping to the outermost roof and exhausting nearby continuations.
				var preferred := 145.0 if attempt % 3 == 0 else 65.0
				var value := preferred - absf(distance - preferred) + rng.randf_range(0, 80) + absf(point.y - path[-1].y) * 0.2
				if value > score:
					score = value
					choice = point
			if not choice.is_finite(): break
			path.append(choice)
		if path.size() > best.size(): best = path
		if path.size() >= 9: return path
	return best if best.size() >= 7 else PackedVector3Array()
