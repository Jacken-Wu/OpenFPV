class_name BiomeLandmarks
extends RefCounted

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary] = []) -> void:
	plan.landmarks = []
	var biome: BiomeDefinition = plan.biomes[0]
	var pool: Array = biome.parameters.get("landmark_pool", [])
	if not field.expanded_at(Vector2(plan.shape.nodes[0].x, plan.shape.nodes[0].z)) and plan.kind == "surface":
		pool = pool.filter(func(rule: Dictionary): return rule.kind != "construction")
	var instances: Array[Dictionary] = []
	for rule: Dictionary in pool:
		for index in int(rule.get("count", 1)):
			var entry := rule.duplicate()
			entry.suffix = "_%d" % index if rule.get("count", 1) > 1 else ""
			instances.append(entry)
	var rng := field.rng_for(plan.key, 19001 if plan.kind == "surface" else 19013 if plan.kind == "sky" else 19031)
	var protected: Array[Vector3] = []
	for station: Dictionary in plan.stations:
		protected.append(station.point)
	for mission: MissionDefinition in plan.missions + plan.get("legacy_missions", []):
		protected.append(mission.acceptance_point())
		protected.append(mission.target_point)
		protected.append_array(mission.checkpoints)
	var candidates: Array[Vector3] = []
	if plan.kind == "surface":
		var site := field.surface_site(plan.key)
		var sampler := BiomeTerrain.new(field, site.anchor)
		for attempt in (64 if biome.parameters.get("extension", false) else 40):
			var p: Vector2 = site.anchor + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
			if field.nearest(p).id == plan.id:
				candidates.append(Vector3(p.x, sampler.sample(p.x, p.y), p.y))
	elif plan.kind == "maze":
		for cell: int in plan.shape.maze.rooms:
			candidates.append(plan.shape.nodes[cell])
	else:
		candidates.assign(plan.shape.nodes)
	for rule: Dictionary in instances:
		if rng.randf() > float(rule.chance) or not Architecture.TYPES.has(rule.kind):
			continue
		var size: Vector3 = Architecture.TYPES[rule.kind].size
		var radius := Vector2(size.x, size.z).length() * 0.5
		for attempt in candidates.size():
			var index := rng.randi_range(0, candidates.size() - 1)
			var point := candidates[index]
			candidates.remove_at(index)
			var clear := true
			var footprint := Rect2(Vector2(point.x - size.x / 2, point.z - size.z / 2), Vector2(size.x, size.z))
			for entrance in entrances:
				clear = clear and not footprint.grow(5).intersects(entrance.hole)
			for target in protected:
				clear = clear and Vector2(point.x - target.x, point.z - target.z).length() > radius + (12 if plan.kind == "surface" else 7)
			for existing: Dictionary in plan.landmarks:
				clear = clear and point.distance_to(existing.point) > radius + float(existing.radius) + 8
			if plan.kind == "sky":
				var fits_island := false
				for island: Dictionary in plan.shape.islands:
					fits_island = fits_island or (absf(point.y - float(island.point.y)) < 3 and Vector2(point.x - island.point.x, point.z - island.point.z).length() + radius < float(island.radius) * 0.85)
				clear = clear and fits_island and point.y + size.y < 299
			if not clear:
				continue
			if plan.kind == "surface":
				var sampler := BiomeTerrain.new(field, Vector2(point.x, point.z))
				var low := point.y
				for dx: float in [-size.x * 0.5, 0, size.x * 0.5]:
					for dz: float in [-size.z * 0.5, 0, size.z * 0.5]:
						var y := sampler.sample(point.x + dx, point.z + dz)
						low = minf(low, y)
						point.y = maxf(point.y, y)
				if point.y - low > (32 if biome.parameters.get("extension", false) else 13):
					continue
				plan.objects.append(WorldProvider.box(plan.id + "/landmark_base/" + rule.kind + rule.suffix, Vector3(point.x, (low + point.y) / 2 - 0.5, point.z), Vector3(size.x + 2, point.y - low + 1, size.z + 2), Color("a99b82"), true, "concrete"))
			var id: String = plan.id + "/landmark/" + rule.kind + rule.suffix
			var objects := Architecture.build(rule.kind, id, point, rng.randf())
			plan.objects.append_array(objects)
			var marker: Vector3 = point + Vector3(0, size.y + 3, 0)
			if plan.kind == "maze":
				marker = point + Vector3.UP * BiomeStructures.NAV_HEIGHT
			marker.y = minf(marker.y, 299)
			plan.landmarks.append({"id": id, "kind": rule.kind, "name": Architecture.TYPES[rule.kind].name, "point": point, "size": size, "radius": radius, "marker": marker})
			break
