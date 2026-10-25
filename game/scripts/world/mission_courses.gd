class_name MissionCourses
extends RefCounted
## Separate random stream and versioned keys preserve every legacy objective.
static func expand(plan: Dictionary, catalog: ContentCatalog, field: BiomeField, entrances: Array[Dictionary]) -> void:
	plan.legacy_missions = plan.missions.duplicate()
	plan.legacy_locations = []
	plan.course_reservations = []
	if catalog.manifest.challenge_templates.is_empty():
		return
	var map_task := ""
	if plan.biomes[0].parameters.get("map_unlock", "visit") == "mission":
		for kind: String in ["survey", "hold_interact", "courier", "circuit", "photo"]:
			for legacy: MissionDefinition in plan.legacy_missions:
				if map_task.is_empty() and legacy.kind == kind:
					map_task = legacy.id
	for slot in plan.missions.size():
		var legacy: MissionDefinition = plan.missions[slot]
		if legacy.id == map_task:
			continue
		var rng := field.rng_for(plan.key, 20713 + slot * 997 + (71 if plan.kind == "sky" else 139 if plan.kind == "maze" else 0))
		var choice := rng.randi_range(0, 8)
		if choice < 5 and legacy.kind != "circuit":
			continue
		var template: MissionDefinition = catalog.manifest.challenge_templates[0 if legacy.kind == "circuit" else (choice - 5) % catalog.manifest.challenge_templates.size()]
		if plan.kind == "maze" and template.kind == "follow":
			template = catalog.manifest.challenge_templates[1]
		var mission := template.duplicate() as MissionDefinition
		mission.id = legacy.id + ":play"
		mission.generated = true
		mission.location_id = mission.id + ":target"
		mission.station_id = legacy.station_id
		mission.source_point = legacy.source_point
		mission.display_name += " · " + plan.biomes[0].display_name
		mission.checkpoints = PackedVector3Array()
		mission.gate_normals = PackedVector3Array()
		mission.challenge = {}
		mission.pickup_points = legacy.checkpoints.duplicate() if legacy.kind == "circuit" else PackedVector3Array()
		if mission.pickup_points.is_empty():
			mission.pickup_points.append(legacy.target_point)
		var ground: Vector3 = plan.shape.nodes[0]
		for point: Vector3 in plan.shape.nodes:
			if Vector2(point.x - legacy.target_point.x, point.z - legacy.target_point.z).length_squared() < Vector2(ground.x - legacy.target_point.x, ground.z - legacy.target_point.z).length_squared():
				ground = point
		# High islands retain their original tasks rather than placing a course in cutoff.
		if plan.kind == "sky" and ground.y > 250:
			continue
		var center := ground + Vector3.UP * (6 if plan.kind == "maze" else 18)
		if plan.kind == "maze" and mission.kind == "orbit":
			center.y = ground.y + 10
		if plan.kind == "surface":
			var sampler := BiomeTerrain.new(field, Vector2(center.x, center.z), entrances)
			for dx: float in [-40, -20, 0, 20, 40]:
				for dz: float in [-40, -20, 0, 20, 40]:
					center.y = maxf(center.y, sampler.sample(center.x + dx, center.z + dz) + 15)
		elif plan.kind == "sky":
			center.y = minf(292, center.y)
		mission.target_point = center
		mission.target_bounds = AABB(center - Vector3.ONE * 1.3, Vector3.ONE * 2.6)
		match mission.kind:
			"race":
				_race(plan, mission, ground, center, rng)
			"balloons":
				var radius := 4.2 if plan.kind == "maze" else 12.0
				for index in rng.randi_range(5, 7):
					var angle := index * TAU / 7
					mission.checkpoints.append(center + Vector3(cos(angle) * radius, (index % 3 - 1) * (1.3 if plan.kind == "maze" else 2.2), sin(angle) * radius))
				mission.target_point = mission.checkpoints[0]
				mission.challenge = {"balloon_radius": 1.15}
			"orbit":
				mission.challenge = {"radius_min": 3.0 if plan.kind == "maze" else 6.0, "radius_max": 7.0 if plan.kind == "maze" else 28.0, "height_tolerance": 3.0 if plan.kind == "maze" else 6.0, "view_angle": 55.0}
				mission.description += "\n半径%.0f～%.0f米，高度差允许±%.0f米，镜头朝向目标（偏角≤55°）。偏离或遮挡只暂停累计，不清零；继续绕满360°即可。" % [mission.challenge.radius_min, mission.challenge.radius_max, mission.challenge.height_tolerance]
			"follow":
				mission.challenge = {"path_radius": 12.0, "radius_min": 5.0, "radius_max": 22.0, "height_tolerance": 4.0, "view_angle": 22.0, "follow_distance": 60.0}
				mission.description += "\n保持5～22米距离，跟在观测机后方同向飞行60米；失去目标超过1秒重新累计。无完成时限。"
		# Keep original structures for old active assignments; only replace the public slot.
		for location: MapLocation in plan.locations.duplicate():
			if location.id == legacy.location_id:
				plan.locations.erase(location)
				plan.legacy_locations.append(location)
				var replacement := location.duplicate() as MapLocation
				replacement.id = mission.location_id
				replacement.display_name = mission.display_name
				replacement.point = mission.acceptance_point()
				replacement.description = mission.description
				plan.locations.append(replacement)
		plan.missions[slot] = mission
		if plan.kind == "sky":
			# New roof gates and flying subjects belong to this sky biome as well.
			var bounds: AABB = plan.biomes[0].region_bounds
			var padding := 36.0 if mission.kind == "follow" else 32.0 if mission.kind == "orbit" else 4.0
			var height_padding := 7.0 if mission.kind == "orbit" else 5.0
			for point: Vector3 in mission.checkpoints + PackedVector3Array([mission.target_point, mission.acceptance_point()]):
				bounds = bounds.expand(point - Vector3(padding, height_padding, padding))
				bounds = bounds.expand(point + Vector3(padding, height_padding, padding))
			plan.biomes[0].region_bounds = bounds
		if plan.kind == "surface":
			var bounds := Rect2(Vector2(center.x, center.z), Vector2.ZERO)
			for point: Vector3 in mission.checkpoints:
				bounds = bounds.expand(Vector2(point.x, point.z))
			plan.course_reservations.append(bounds.grow(24))

static func _race(plan: Dictionary, mission: MissionDefinition, ground: Vector3, center: Vector3, rng: RandomNumberGenerator) -> void:
	if plan.kind == "maze":
		var maze: Dictionary = plan.shape.maze
		var start := BiomeStructures.cell_at(maze, ground)
		var route := PackedVector3Array()
		for attempt in 12:
			route = BiomeStructures.maze_path(maze, start, rng.randi_range(0, maze.doors.size() - 1))
			if route.size() >= 5:
				break
		if route.size() < 2:
			route = BiomeStructures.maze_path(maze, start, (start + 1) % maze.doors.size())
		mission.checkpoints = route.slice(0, mini(10, route.size()))
		for index in mission.checkpoints.size():
			mission.checkpoints[index].y = float(maze.floor) + 10
	else:
		# A dedicated tower supplies side passes and a roof dive without moving old gates.
		center += Vector3(18, 0, 18)
		var roof := minf(center.y + 13, 286) if plan.kind == "sky" else center.y + 13
		var bottom := minf(center.y - 9, roof - 6)
		plan.objects.append(WorldProvider.box(mission.id + "/course_tower", Vector3(center.x, (bottom + roof) * 0.5, center.z), Vector3(8, roof - bottom, 8), Color("607d90"), true, "metal"))
		var rotation := rng.randf_range(0, TAU)
		for index in 8:
			var angle := rotation + index * TAU / 8
			var height := minf(294, center.y + [0.0, 4.0, 8.0, 3.0, 10.0, 5.0, 12.0, 8.0][index])
			mission.checkpoints.append(Vector3(center.x + cos(angle) * 18, height, center.z + sin(angle) * 18))
		mission.checkpoints.append(Vector3(center.x, minf(294, roof + 12), center.z))
		# Final gate is a horizontal roof dive, safely above the tower.
		mission.checkpoints.append(Vector3(center.x, roof + 5, center.z))
	mission.challenge = {"gate_half": 2.5 if plan.kind == "maze" else 3.4}
	var source_points := mission.checkpoints.duplicate()
	for index in mission.checkpoints.size():
		var normal := (source_points[1] - source_points[0]).normalized() if index == 0 else (source_points[index] - source_points[index - 1]).normalized()
		if plan.kind == "maze":
			# Legacy ceiling markers stay at cell centres; move gates clear of them.
			mission.checkpoints[index] = source_points[index] + normal * 3
		mission.gate_normals.append(normal)
		gate(plan.objects, mission.id + "/gate%d" % index, mission.checkpoints[index], normal, mission.challenge.gate_half)
	mission.target_point = mission.checkpoints[0]
	mission.description += "\n共%d门，黄色箭头为通过方向；进入门框附近不计数，需穿过开口平面。" % mission.checkpoints.size()

static func gate(objects: Array, id: String, center: Vector3, normal: Vector3, half: float = 3.4, up_hint: Vector3 = Vector3.ZERO) -> void:
	var basis := FlightChallengeRules.gate_basis(normal, up_hint)
	for side: float in [-1, 1]:
		for horizontal in [false, true]:
			var edge := half + FlightChallengeRules.GATE_EDGE_OFFSET
			var offset := Vector3(0, side * edge, 0) if horizontal else Vector3(side * edge, 0, 0)
			var width := FlightChallengeRules.GATE_BAR_WIDTH
			var size := Vector3(edge * 2 + 0.4, width, width) if horizontal else Vector3(width, edge * 2 + 0.4, width)
			var object := WorldProvider.box(id + "/%s/%s" % [horizontal, side], center + basis * offset, size, Color("68b7c5"), true, "metal")
			object.rotation = basis.get_euler()
			objects.append(object)
