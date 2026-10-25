class_name FlowCourses
extends RefCounted
## Versioned routes follow the existing streets, terrain, islands and maze graph.
static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	# Remove every superseded course before routing. A future slot's obsolete
	# tower must not block an earlier slot while this pass is running.
	var retained: Array[Dictionary] = []
	for task: MissionDefinition in plan.missions:
		if task.kind == "race":
			task.legacy_objects = []
	for object: Dictionary in plan.objects:
		var historical := false
		for task: MissionDefinition in plan.missions:
			if task.kind == "race" and (object.id.begins_with(task.id + "/gate") or object.id == task.id + "/course_tower"):
				task.legacy_objects.append(object)
				historical = true
				break
		if not historical:
			retained.append(object)
	plan.objects = retained
	var city_cache := {}
	for slot in plan.missions.size():
		var old: MissionDefinition = plan.missions[slot]
		if old.kind != "race":
			continue
		var mission := old.duplicate() as MissionDefinition
		mission.legacy_objects = []
		mission.id += ":flow"
		mission.history_id = old.id
		mission.location_id = mission.id + ":target"
		mission.checkpoints = PackedVector3Array()
		mission.gate_normals = PackedVector3Array()
		mission.challenge = {"gate_half": 2.5 if plan.kind == "maze" else 3.0, "route_revision": 1}
		var rng := field.rng_for(plan.key, 31471 + slot * 1999 + (71 if plan.kind == "sky" else 139 if plan.kind == "maze" else 0))
		var obstacles: Array[Dictionary] = plan.objects.duplicate()
		var city: bool = plan.kind == "surface" and plan.biomes[0].provider_id == "base.generator.modular_city"
		if city:
			obstacles.append_array(_city_objects(plan, field, entrances, old.acceptance_point(), city_cache))
		for task: MissionDefinition in plan.missions:
			if task.kind == "balloons":
				for launch: Vector3 in task.checkpoints:
					var height := maxf(0, float(task.challenge.height_limit) - launch.y)
					obstacles.append(WorldProvider.box("balloon_clearance", launch + Vector3.UP * height * 0.5, Vector3(3.4, height + 2.4, 3.4), Color.WHITE))
		var collision_index := _prepare_obstacles(obstacles)
		var sampler := BiomeTerrain.new(field, Vector2(old.acceptance_point().x, old.acceptance_point().z), entrances)
		for attempt in 64:
			var points: PackedVector3Array
			if plan.kind == "maze":
				points = _maze(plan, old.acceptance_point(), rng)
			elif plan.kind == "sky":
				points = _sky(plan, old.acceptance_point(), rng)
			else:
				points = _surface(plan, field, sampler, old.acceptance_point(), rng, city, collision_index)
			if _clear(points, collision_index, plan.kind):
				mission.checkpoints = points
				break
		if mission.checkpoints.is_empty():
			# Retain the playable historical course if no safe route fits this site.
			plan.objects.append_array(old.legacy_objects)
			old.legacy_objects.clear()
			continue
		for index in mission.checkpoints.size():
			var incoming := (mission.checkpoints[maxi(0, index - 1)] - mission.checkpoints[index]).normalized()
			var outgoing := (mission.checkpoints[mini(index + 1, mission.checkpoints.size() - 1)] - mission.checkpoints[index]).normalized()
			var direction := (outgoing - incoming).normalized()
			mission.gate_normals.append(direction)
			MissionCourses.gate(plan.objects, mission.id + "/gate%d" % index, mission.checkpoints[index], direction, mission.challenge.gate_half)
			if plan.kind == "surface":
				var basis := FlightChallengeRules.gate_basis(direction)
				for side: float in [-1, 1]:
					var foot := mission.checkpoints[index] + basis * Vector3(side * 3.3, -3.3, 0)
					var floor_y := 0.25 if city else sampler.sample(foot.x, foot.z)
					var height := maxf(0.05, foot.y - floor_y)
					plan.objects.append(WorldProvider.box(mission.id + "/foot%d/%d" % [index, int(side)], Vector3(foot.x, floor_y + height * 0.5, foot.z), Vector3(0.3, height, 0.3), Color("68b7c5"), true, "metal"))
		mission.target_point = mission.checkpoints[0]
		mission.description = "沿当地%s依次穿过%d个门，门朝向衔接前后航段；距离与高度随地点变化，无倒计时。黄色箭头表示通过方向，必须穿过开口平面。" % ["街道与建筑外立面" if city else "地形" if plan.kind == "surface" else "浮岛与遗迹" if plan.kind == "sky" else "连通走廊", mission.checkpoints.size()]
		plan.legacy_missions.append(old)
		for location: MapLocation in plan.locations.duplicate():
			if location.id == old.location_id:
				plan.locations.erase(location)
				plan.legacy_locations.append(location)
				var replacement := location.duplicate() as MapLocation
				replacement.id = mission.location_id
				replacement.description = mission.description
				plan.locations.append(replacement)
		plan.missions[slot] = mission
		if plan.kind == "surface":
			for index in range(1, mission.checkpoints.size()):
				var a := mission.checkpoints[index - 1]
				var b := mission.checkpoints[index]
				var steps := ceili(a.distance_to(b) / 10.0)
				for step in steps + 1:
					var point := a.lerp(b, float(step) / steps)
					var clearance := 4.5 if city else 9.0
					plan.course_reservations.append(Rect2(Vector2(point.x - clearance, point.z - clearance), Vector2.ONE * clearance * 2))

static func _city_objects(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary], start: Vector3, cache: Dictionary) -> Array[Dictionary]:
	var biome: BiomeDefinition = plan.biomes[0].duplicate() as BiomeDefinition
	biome.parameters = biome.parameters.duplicate(true)
	biome.parameters.clearings = []
	biome.parameters.landmark_reservations = plan.course_reservations.duplicate()
	for landmark: Dictionary in plan.landmarks:
		biome.parameters.landmark_reservations.append(Rect2(Vector2(landmark.point.x - landmark.size.x / 2 - 3, landmark.point.z - landmark.size.z / 2 - 3), Vector2(landmark.size.x + 6, landmark.size.z + 6)))
	for station: Dictionary in plan.stations:
		biome.parameters.clearings.append(station.point)
	for task: MissionDefinition in plan.missions + plan.legacy_missions:
		biome.parameters.clearings.append(task.acceptance_point())
		if task.challenge.get("route_revision", 0) > 0:
			continue
		biome.parameters.clearings.append(task.target_point)
		biome.parameters.clearings.append_array(task.checkpoints)
	var provider := BiomeSurfaceProvider.new("city", field, Vector2(start.x, start.z), entrances)
	var key := WorldGenerator.key_at(start)
	var objects: Array[Dictionary] = []
	for x in range(key.x - 3, key.x + 4):
		for z in range(key.z - 3, key.z + 4):
			var chunk := Vector3i(x, 0, z)
			if not cache.has(chunk):
				cache[chunk] = provider.generate(chunk, field.seed_value, biome)
			objects.append_array(cache[chunk])
	return objects

static func _surface(plan: Dictionary, field: BiomeField, sampler: BiomeTerrain, start: Vector3, rng: RandomNumberGenerator, city: bool, obstacles: Dictionary) -> PackedVector3Array:
	if city:
		return _streets(plan, field, start, rng, obstacles)
	var points := PackedVector3Array()
	var point := Vector2(start.x, start.z)
	var heading := rng.randf_range(0, TAU)
	point += Vector2.from_angle(heading) * rng.randf_range(16, 28)
	var wanted := rng.randi_range(7, 12)
	for index in wanted:
		if index > 0:
			heading += rng.randf_range(-0.55, 0.55)
			point += Vector2.from_angle(heading) * rng.randf_range(14, 52)
		if point.distance_to(Vector2(start.x, start.z)) > 220 or field.nearest(point).id != plan.id:
			break
		var height := sampler.sample(point.x, point.y) + rng.randf_range(5.2, 7.5)
		for offset: Vector2 in [Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4)]:
			height = maxf(height, sampler.sample(point.x + offset.x, point.y + offset.y) + 5.2)
		var candidate := Vector3(point.x, height, point.y)
		if not points.is_empty():
			var previous := points[-1]
			var top := -INF
			var steps := ceili(previous.distance_to(candidate) / 4.0)
			for sample_index in steps + 1:
				var probe := previous.lerp(candidate, float(sample_index) / maxf(1, steps))
				top = maxf(top, sampler.sample(probe.x, probe.z) + 5.2)
			candidate.y = maxf(candidate.y, top)
			points[-1].y = maxf(points[-1].y, top)
			if not _segment_clear(points[-1], candidate, obstacles):
				break
		points.append(candidate)
	return points if points.size() >= 6 else PackedVector3Array()

static func _streets(plan: Dictionary, field: BiomeField, start: Vector3, rng: RandomNumberGenerator, obstacles: Dictionary) -> PackedVector3Array:
	var point := Vector2(start.x, start.z).snapped(Vector2.ONE * 32) + Vector2(rng.randi_range(-2, 2), rng.randi_range(-2, 2)) * 32
	var street := rng.randi_range(0, 3)
	var points := PackedVector3Array([Vector3(point.x, rng.randf_range(5.2, 6.7), point.y)])
	for index in rng.randi_range(6, 11):
		var found := false
		for attempt in 12:
			var turn := rng.randi_range(0, 3)
			var direction := posmod(street + (-1 if turn == 0 else 1 if turn == 1 else 0), 4)
			var next := point + Vector2.from_angle(direction * PI / 2).round() * 32 * (2 if rng.randf() < 0.25 else 1)
			if next.distance_to(Vector2(start.x, start.z)) > 190 or field.nearest(next).id != plan.id:
				continue
			var candidate := Vector3(next.x, rng.randf_range(5.2, 6.7), next.y)
			var revisited := false
			for previous: Vector3 in points:
				revisited = revisited or previous.distance_to(candidate) < 12
			if revisited or not _segment_clear(points[-1], candidate, obstacles):
				continue
			street = direction
			point = next
			points.append(candidate)
			found = true
			break
		if not found:
			break
	return points if points.size() >= 6 else PackedVector3Array()

static func _sky(plan: Dictionary, start: Vector3, rng: RandomNumberGenerator) -> PackedVector3Array:
	var candidates: Array = plan.shape.islands.filter(func(item: Dictionary): return item.point.y <= 280)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.point.distance_squared_to(start) < b.point.distance_squared_to(start))
	var island: Dictionary = candidates[rng.randi_range(0, mini(2, candidates.size() - 1))]
	var points := PackedVector3Array()
	var angle := rng.randf_range(0, TAU)
	var direction := -1 if rng.randf() < 0.5 else 1
	var radius: float = maxf(17, island.radius * rng.randf_range(0.44, 0.66))
	for index in rng.randi_range(7, 11):
		angle += direction * rng.randf_range(0.5, 0.8)
		points.append(island.point + Vector3(cos(angle) * radius, rng.randf_range(6, 11), sin(angle) * radius))
	return points

static func _maze(plan: Dictionary, start: Vector3, rng: RandomNumberGenerator) -> PackedVector3Array:
	var maze: Dictionary = plan.shape.maze
	var start_cell := BiomeStructures.cell_at(maze, start)
	if rng.randf() < 0.8:
		start_cell = rng.randi_range(0, maze.doors.size() - 1)
	var path := BiomeStructures.maze_path(maze, start_cell, rng.randi_range(0, maze.doors.size() - 1))
	var points := PackedVector3Array()
	for index in mini(path.size(), rng.randi_range(10, 20)):
		if index > 0 and index < path.size() - 1 and (path[index] - path[index - 1]).normalized().dot((path[index + 1] - path[index]).normalized()) > 0.99 and rng.randf() < 0.6:
			continue
		var point := path[index]
		point.y = float(maze.floor) + 5.5
		points.append(point)
	return points if points.size() >= 6 else PackedVector3Array()

static func _prepare_obstacles(objects: Array[Dictionary]) -> Dictionary:
	# Route probes touch only a few 16m cells. Scanning every building on each
	# attempt made cold, distant city plans block the main thread for ~0.9s.
	var bins := {}
	var identifier := 0
	for object: Dictionary in objects:
		if not object.get("solid", true) or object.get("primitive", "box") == "terrain":
			continue
		var rotation: Vector3 = object.get("rotation", Vector3.ZERO)
		var rotated := not rotation.is_zero_approx()
		var box := AABB((-object.size * 0.5) if rotated else object.center - object.size * 0.5, object.size).grow(0.75)
		var basis := Basis.from_euler(rotation)
		var bounds: AABB = Transform3D(basis, object.center) * box if rotated else box
		var record := {"box": box, "rotated": rotated, "inverse": basis.inverse() if rotated else Basis.IDENTITY, "center": object.center, "index": identifier}
		identifier += 1
		var first := Vector3i((bounds.position / 16.0).floor())
		var last := Vector3i((bounds.end / 16.0).floor())
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for z in range(first.z, last.z + 1):
					var key := Vector3i(x, y, z)
					if not bins.has(key):
						bins[key] = []
					bins[key].append(record)
	return bins

static func _segment_clear(a: Vector3, b: Vector3, bins: Dictionary) -> bool:
	var first := Vector3i((a.min(b) / 16.0).floor())
	var last := Vector3i((a.max(b) / 16.0).floor())
	var seen := {}
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			for z in range(first.z, last.z + 1):
				for object: Dictionary in bins.get(Vector3i(x, y, z), []):
					if seen.has(object.index):
						continue
					seen[object.index] = true
					var local_a: Vector3 = object.inverse * (a - object.center) if object.rotated else a
					var local_b: Vector3 = object.inverse * (b - object.center) if object.rotated else b
					var box: AABB = object.box
					if box.has_point(local_a) or box.has_point(local_b) or box.intersects_segment(local_a, local_b) != null:
						return false
	return true

static func _clear(points: PackedVector3Array, objects: Dictionary, kind: String) -> bool:
	if points.size() < 6:
		return false
	for index in points.size():
		var incoming := (points[maxi(0, index - 1)] - points[index]).normalized()
		var outgoing := (points[mini(index + 1, points.size() - 1)] - points[index]).normalized()
		if index > 0 and index < points.size() - 1 and incoming.dot(outgoing) > 0.01:
			return false
		var basis := FlightChallengeRules.gate_basis((outgoing - incoming).normalized())
		var half := 2.9 if kind == "maze" else 3.4
		for x: float in [-half, 0, half]:
			for y: float in [-half, 0, half]:
				var probe := points[index] + basis * Vector3(x, y, 0)
				if not _segment_clear(probe, probe, objects):
					return false
		if index > 0 and not _segment_clear(points[index - 1], points[index], objects):
			return false
	return true
