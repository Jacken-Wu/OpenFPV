class_name MissionSites
extends RefCounted
## Reception pads move independently of objective geometry and saved route stages.
const MIN_SPACING := 48.0
const PAD_SIZE := 5.5

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	var candidates: Array[Vector3] = []
	var sampler := BiomeTerrain.new(field, Vector2(plan.shape.nodes[0].x, plan.shape.nodes[0].z), entrances)
	if plan.kind == "sky":
		for island: Dictionary in plan.shape.islands:
			candidates.append(island.point + Vector3.UP * 2.1)
			for fraction: float in [0.4, 0.7]:
				for angle in 8:
					var offset := Vector2.from_angle(angle * TAU / 8) * float(island.radius) * fraction
					candidates.append(island.point + Vector3(offset.x, 2.1, offset.y))
	else:
		for node: Vector3 in plan.shape.nodes:
			for offset: Vector2 in ([Vector2(4, 4), Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4)] if plan.kind == "maze" else [Vector2(12, 12), Vector2(-12, -12), Vector2(12, -12), Vector2(-12, 12)]):
				var point := node + Vector3(offset.x, 0, offset.y)
				point.y += 0.5
				candidates.append(point)
	var used: Array[Vector3] = []
	var surface_cache := {}
	for mission: MissionDefinition in plan.missions:
		var selected := Vector3(INF, INF, INF)
		var nearest_cost := INF
		var target_xz := Vector2(mission.target_point.x, mission.target_point.z)
		if plan.kind == "surface":
			# Horizontal distance is a lower bound on the full 3D distance. Only
			# sample terrain/borders while a candidate can still beat the best pad.
			candidates.sort_custom(func(a: Vector3, b: Vector3): return Vector2(a.x, a.z).distance_squared_to(target_xz) < Vector2(b.x, b.z).distance_squared_to(target_xz))
		else:
			candidates.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(mission.target_point) < b.distance_squared_to(mission.target_point))
		for candidate in candidates:
			var point := candidate
			if plan.kind == "surface":
				var key := Vector2(point.x, point.z)
				if key.distance_squared_to(target_xz) > nearest_cost:
					break
				if not surface_cache.has(key):
					surface_cache[key] = _surface_point(point, plan.id, field, sampler, entrances)
				point = surface_cache[key]
				if not point.is_finite():
					continue
			var cost := point.distance_squared_to(mission.target_point)
			if cost >= nearest_cost:
				continue
			var clear := true
			for previous in used:
				clear = clear and point.distance_to(previous) >= MIN_SPACING
			for station: Dictionary in plan.stations:
				clear = clear and point.distance_to(station.point) >= 14
			if not clear or not _clear(plan.objects, point):
				continue
			selected = point
			nearest_cost = cost
			if plan.kind != "surface":
				break
		# Node pools cover the complete island cluster/maze, rather than one room.
		if not selected.is_finite():
			push_error("No separated mission reception pad: " + mission.id)
			continue
		used.append(selected)
		mission.pickup_platform = {"point": selected + Vector3.UP * 0.08, "top": selected.y, "half": PAD_SIZE * 0.5}
		mission.pickup_points = PackedVector3Array()
		var slot := mission.id.split(":")[5]
		for legacy: MissionDefinition in plan.legacy_missions:
			if legacy.id.split(":")[5] == slot:
				legacy.pickup_platform = mission.pickup_platform.duplicate(true)
				legacy.pickup_points = PackedVector3Array()
		var id := mission.id + "/reception"
		plan.objects.append(WorldProvider.box(id + "/pad", selected - Vector3.UP * 0.225, Vector3(PAD_SIZE, 0.45, PAD_SIZE), Color("527c79"), true, "metal"))
		plan.objects.append(WorldProvider.box(id + "/mark", selected + Vector3.UP * 0.012, Vector3(3.6, 0.02, 3.6), Color("a4d5b5"), false, "screen"))
		for side: float in [-1, 1]:
			plan.objects.append(WorldProvider.box(id + "/edge%d" % int(side), selected + Vector3(side * 2.5, 0.02, 0), Vector3(0.12, 0.03, 4.8), Color("e4cb85"), false, "screen"))
		plan.objects.append(WorldProvider.box(id + "/signpost", selected + Vector3(2.9, 1.4, 0), Vector3(0.12, 2.8, 0.12), Color("a2b7af"), true, "metal"))
		if plan.kind == "surface":
			plan.course_reservations.append(Rect2(Vector2(selected.x - 7, selected.z - 7), Vector2.ONE * 14))
		if mission.kind == "balloons":
			_balloons(plan, mission, selected, sampler)
		for location: MapLocation in plan.locations:
			if location.id == mission.location_id:
				location.point = mission.acceptance_point()
				location.description = mission.description

static func _surface_point(point: Vector3, id: String, field: BiomeField, sampler: BiomeTerrain, entrances: Array[Dictionary]) -> Vector3:
	for index in 8:
		if field.nearest(Vector2(point.x, point.z) + Vector2.from_angle(index * TAU / 8) * 32).id != id:
			return Vector3(INF, INF, INF)
	for entry: Dictionary in entrances:
		if Vector2(point.x - entry.top.x, point.z - entry.top.z).length() < 18:
			return Vector3(INF, INF, INF)
	point.y = -INF
	for x: float in [-3, 0, 3]:
		for z: float in [-3, 0, 3]:
			point.y = maxf(point.y, sampler.sample(point.x + x, point.z + z))
	point.y += 0.5
	return point

static func _clear(objects: Array, point: Vector3) -> bool:
	var landing := AABB(point + Vector3(-2.85, 0.04, -2.85), Vector3(5.7, 2.5, 5.7))
	for object: Dictionary in objects:
		if not object.get("solid", true) or object.get("primitive", "box") == "terrain":
			continue
		var box := AABB(object.center - object.size * 0.5, object.size)
		if box.intersects(landing):
			return false
	return true

static func _balloons(plan: Dictionary, mission: MissionDefinition, pad: Vector3, sampler: BiomeTerrain) -> void:
	var count := mission.checkpoints.size()
	mission.checkpoints = PackedVector3Array()
	if plan.kind == "maze":
		var nodes: Array = plan.shape.nodes.duplicate()
		nodes.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(pad) < b.distance_squared_to(pad))
		for node: Vector3 in nodes:
			var point := node + Vector3(4, 3.5, 4)
			var clear := _launch_clear(plan, point)
			for previous: Vector3 in mission.checkpoints:
				clear = clear and previous.distance_to(point) >= 10
			if clear:
				mission.checkpoints.append(point)
			if mission.checkpoints.size() == count:
				break
	else:
		var center := pad
		var radius := 18.0
		if plan.kind == "sky":
			var nearest: Dictionary = plan.shape.islands[0]
			for island: Dictionary in plan.shape.islands:
				if island.point.distance_to(pad) < nearest.point.distance_to(pad):
					nearest = island
			center = nearest.point
			radius = minf(radius, float(nearest.radius) * 0.5)
		for index in 48:
			var angle := index * TAU / count + floorf(float(index) / count) * 0.23
			var point := center + Vector3(cos(angle) * radius, 4, sin(angle) * radius)
			if plan.kind == "surface":
				point.y = sampler.sample(point.x, point.z) + 4
			var clear := _launch_clear(plan, point)
			for previous: Vector3 in mission.checkpoints:
				clear = clear and previous.distance_to(point) >= 9
			if clear:
				mission.checkpoints.append(point)
			if mission.checkpoints.size() == count:
				break
	var highest := pad.y
	for point: Vector3 in mission.checkpoints:
		highest = maxf(highest, point.y)
		if plan.kind == "surface":
			plan.course_reservations.append(Rect2(Vector2(point.x - 3, point.z - 3), Vector2.ONE * 6))
	var limit := minf(295, highest + 45)
	if plan.kind == "maze":
		limit = float(plan.shape.maze.floor) + float(plan.shape.maze.height) - 2.5
	var interval := 1.5 if plan.kind == "maze" else 2.5
	mission.challenge = {"balloon_radius": 1.15, "balloon_revision": 2, "release_delay": 3.0, "release_interval": interval, "rise_speed": 0.7 if plan.kind == "maze" else 1.8, "height_limit": limit}
	mission.description = "可在地图提前接取；到任务平台停稳按 E 才开始放球。3秒准备后每%.1f秒放出一只，持续上升。撞破全部气球；任一超过限高%.1f米则本轮失败，回平台重试。只有首次完成获得奖励。" % [interval, limit]

static func _launch_clear(plan: Dictionary, point: Vector3) -> bool:
	var top := minf(295, point.y + 60) if plan.kind != "maze" else float(plan.shape.maze.floor) + float(plan.shape.maze.height) - 2.5
	var column := AABB(point - Vector3(1.5, 1.2, 1.5), Vector3(3, maxf(0, top - point.y) + 2.4, 3))
	for object: Dictionary in plan.objects:
		if object.get("solid", true) and object.get("primitive", "box") != "terrain" and AABB(object.center - object.size * 0.5, object.size).intersects(column):
			return false
	return true
