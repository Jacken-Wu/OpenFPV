class_name RegionalSites
extends RefCounted
## Region-specific task definitions, separate from all persisted assignments.
static func populate(plan: Dictionary, field: BiomeField, catalog: ContentCatalog, entrances: Array[Dictionary]) -> void:
	plan.portal_requirements = []
	if plan.kind != "surface":
		return
	var biome: BiomeDefinition = plan.biomes[0]
	var rules: Array = biome.parameters.get("regional_tasks", [])
	if rules.is_empty():
		return
	var anchor: Vector2 = field.surface_site(plan.key).anchor
	var sampler := BiomeTerrain.new(field, anchor, entrances)
	var rng := field.rng_for(plan.key, 52001)
	var used: Array[Vector3] = []
	for task: MissionDefinition in plan.missions:
		used.append(task.acceptance_point())
	for station: Dictionary in plan.stations:
		used.append(station.point)
	var keep := maxi(0, 5 - rules.size())
	while plan.missions.size() > keep:
		var historical: MissionDefinition = plan.missions.pop_back()
		plan.legacy_missions.append(historical)
		for location: MapLocation in plan.locations.duplicate():
			if location.id == historical.location_id:
				plan.locations.erase(location)
				plan.legacy_locations.append(location)
	for slot in rules.size():
		var rule: Dictionary = rules[slot]
		var selected := Vector3.INF
		for attempt in 220:
			var p := anchor + Vector2(rng.randf_range(-270, 270), rng.randf_range(-270, 270))
			if field.nearest(p).id != plan.id:
				continue
			var point := MissionSites._surface_point(Vector3(p.x, 0, p.y), plan.id, field, sampler, entrances)
			if not point.is_finite():
				continue
			var clear := true
			for landmark: Dictionary in plan.landmarks:
				clear = clear and Vector2(point.x - landmark.point.x, point.z - landmark.point.z).length() > float(landmark.radius) + 8
			for before in used:
				clear = clear and point.distance_to(before) >= 50
			if clear:
				selected = point
				break
		if not selected.is_finite():
			push_error("No regional reception site: " + plan.id)
			continue
		used.append(selected)
		var task := MissionDefinition.new()
		task.id = "proc:4:surface:%d:%d:%d:regional" % [plan.key.x, plan.key.y, 100 + slot]
		task.location_id = task.id + ":target"
		task.kind = "regional"
		task.generated = true
		task.display_name = String(rule.title) + " · " + biome.display_name
		task.description = rule.description
		task.reward_id = catalog.manifest.challenge_templates[0].reward_id
		task.mission_tag = "exploration"
		task.city_tag = "any"
		task.station_id = plan.stations[0].id
		task.source_point = selected + Vector3.UP * 0.08
		task.pickup_platform = {"point": task.source_point, "top": selected.y, "half": 2.75}
		task.challenge = {"mode": rule.mode, "hold": 1.2 if rule.mode == "repair" else 0.35, "radius": 4.0, "max_speed": 3.0 if rule.mode == "repair" else 12.0, "portal_required": rule.get("portal_required", false), "regional_revision": 1}
		if rule.mode == "repair":
			for index in 3:
				var found := selected
				for attempt in 160:
					var p := Vector2(selected.x, selected.z) + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(50, 105)
					var point := MissionSites._surface_point(Vector3(p.x, 0, p.y), plan.id, field, sampler, entrances)
					var clear := point.is_finite() and point.distance_to(selected) > 30
					for landmark: Dictionary in plan.landmarks:
						clear = clear and Vector2(point.x - landmark.point.x, point.z - landmark.point.z).length() > float(landmark.radius) + 8
					for previous: Vector3 in task.checkpoints:
						clear = clear and point.distance_to(previous) >= 24
					if clear:
						found = point
						break
				task.checkpoints.append(found + Vector3.UP * 0.8)
		else:
			var base := megabase(plan, sampler, anchor)
			var orientation := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2)
			if rule.mode == "sequence":
				for p: Vector3 in [Vector3(-34, 29.6, 0), Vector3(18, 69.6, 0), Vector3(70, 109.6, 52), Vector3(18, 149.6, 52)]:
					task.checkpoints.append(Vector3(anchor.x, base, anchor.y) + orientation * p)
			else:
				for p: Vector3 in [Vector3(-52, 16, -52), Vector3(-52, 58, -52), Vector3(0, 58, -52), Vector3(0, 58, 0), Vector3(0, 98, 0), Vector3(52, 98, 0), Vector3(52, 98, 52), Vector3(52, 138, 52), Vector3(0, 138, 52), Vector3(0, 178, 52)]:
					task.checkpoints.append(Vector3(anchor.x, base, anchor.y) + orientation * p)
			plan.megabase = base
		task.target_point = task.checkpoints[0]
		task.target_bounds = AABB(task.target_point - Vector3.ONE * 2, Vector3.ONE * 4)
		plan.missions.append(task)
		if task.challenge.portal_required:
			plan.portal_requirements.append(task.id)
		pad(plan.objects, task.id + "/entry", selected)
		if rule.mode in ["repair", "sequence"]:
			for index in task.checkpoints.size():
				var point := task.checkpoints[index]
				pad(plan.objects, task.id + "/terminal%d" % index, point - Vector3.UP * 0.8)
				plan.objects.append(WorldProvider.box(task.id + "/console%d" % index, point + Vector3(2, 0.4, 0), Vector3(1.1, 2, 1.2), Color("6b8d92"), true, "metal"))
		var location := MapLocation.new()
		location.id = task.location_id
		location.display_name = task.display_name
		location.kind = "mission"
		location.point = task.acceptance_point()
		location.description = task.description
		location.layer = "surface"
		location.structure_id = plan.id
		plan.locations.append(location)

static func megabase(plan: Dictionary, sampler: BiomeTerrain, anchor: Vector2) -> float:
	var height := 0.0
	for x: float in [-160, 0, 160]:
		for z: float in [-160, 0, 160]:
			height = maxf(height, sampler.sample(anchor.x + x, anchor.y + z))
	return minf(65, height + 8)

static func pad(objects: Array, id: String, top: Vector3) -> void:
	objects.append(WorldProvider.box(id + "/pad", top - Vector3.UP * 0.225, Vector3(5.5, 0.45, 5.5), Color("567f83"), true, "metal"))
	objects.append(WorldProvider.box(id + "/mark", top + Vector3.UP * 0.015, Vector3(3.5, 0.02, 3.5), Color("8fc5c7"), false, "screen"))
