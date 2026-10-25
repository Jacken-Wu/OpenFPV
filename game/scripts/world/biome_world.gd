class_name BiomeWorld
extends RegionalWorld
## v4: pages collect independent biome instances; they do not determine geography.
var field: BiomeField
var plans: Dictionary = {}
var plan_mutex := Mutex.new()
var summaries: Dictionary = {}
var pages: Dictionary = {}

func _init(content: ContentCatalog, world_seed: int, preserved_radius: int = 4) -> void:
	super(content, world_seed)
	field = BiomeField.new(content, world_seed, preserved_radius)

func plan(kind: String, key: Vector2i) -> Dictionary:
	var id := kind + ":%d:%d" % [key.x, key.y]
	plan_mutex.lock()
	var result: Dictionary = plans.get(id, {})
	plan_mutex.unlock()
	if not result.is_empty():
		return result
	result = _build_plan(kind, key)
	if result.is_empty():
		return result
	plan_mutex.lock()
	if plans.has(id):
		result = plans[id]
	else:
		if plans.size() >= 48:
			plans.erase(plans.keys()[0])
		plans[id] = result
		var summary := {}
		for property: String in ["id", "kind", "key", "biomes", "stations", "missions", "locations", "legacy_missions", "legacy_locations", "portal_requirements"]:
			if result.has(property): summary[property] = result[property]
		if summaries.size() >= 128: summaries.erase(summaries.keys()[0])
		summaries[id] = summary
	plan_mutex.unlock()
	return result

func _build_plan(kind: String, key: Vector2i) -> Dictionary:
	var site: Dictionary
	var shape: Dictionary
	var biome: BiomeDefinition
	var rng := field.rng_for(key, 7151 if kind == "surface" else 7177 if kind == "sky" else 7187)
	if kind == "surface":
		site = field.surface_site(key)
		biome = site.biome.duplicate() as BiomeDefinition
		var polygon := field.polygon(site)
		var area := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			area = area.expand(point)
		biome.region_bounds = AABB(Vector3(area.position.x, -64, area.position.y), Vector3(area.size.x, 192, area.size.y))
		if biome.parameters.get("extension", false):
			biome.region_bounds.size.y = 384
		biome.parameters = biome.parameters.duplicate(true)
		biome.parameters.map_polygon = polygon
		var sampler := BiomeTerrain.new(field, site.anchor)
		var nodes: Array[Vector3] = []
		for attempt in 180:
			var angle := rng.randf_range(0, TAU)
			var distance := rng.randf_range(75, 330) if not nodes.is_empty() else 0.0
			var p: Vector2 = site.anchor + Vector2(cos(angle), sin(angle)) * distance
			if biome.provider_id == "base.generator.modular_city":
				p = p.snapped(Vector2.ONE * 64)
			if field.nearest(p).id != site.id:
				continue
			var separated := true
			for previous in nodes:
				separated = separated and Vector2(previous.x, previous.z).distance_to(p) > 55
			if separated:
				nodes.append(Vector3(p.x, sampler.sample(p.x, p.y), p.y))
			if nodes.size() >= 14:
				break
		shape = {"nodes": nodes, "objects": [], "entries": [], "bounds": biome.region_bounds}
	else:
		site = field.volume_site(kind, key)
		if site.is_empty():
			return {}
		biome = field.volumes[kind].duplicate() as BiomeDefinition
		biome.id += ":v4:%d:%d" % [key.x, key.y]
		biome.display_name = "云海浮岛群" if kind == "sky" else "地下迷宫"
		shape = BiomeStructures.sky(site, field) if kind == "sky" else BiomeStructures.maze(site, field)
		biome.region_bounds = shape.bounds
		biome.parameters = biome.parameters.duplicate(true)
		biome.parameters.erase("surface_reservation")
		biome.parameters.world_layer = kind
		if kind == "sky":
			biome.parameters.map_islands = shape.islands
		else:
			var walls := PackedVector2Array()
			for object: Dictionary in shape.objects:
				if "/wall" in object.id:
					var offset := Vector3(object.size.x * 0.5, 0, 0) if object.size.x > object.size.z else Vector3(0, 0, object.size.z * 0.5)
					walls.append(Vector2(object.center.x - offset.x, object.center.z - offset.z))
					walls.append(Vector2(object.center.x + offset.x, object.center.z + offset.z))
			biome.parameters.map_walls = walls
	var result := {"id": site.id, "kind": kind, "key": key, "biomes": [biome], "stations": [], "missions": [], "locations": [], "objects": shape.objects, "shape": shape, "chunks": {}}
	var nodes: Array = shape.nodes
	var station_count := 2 if rng.randf() < (0.35 if kind == "surface" else 0.55) else 1
	if kind == "sky" and shape.islands.size() < 2:
		station_count = 1
	var occupied: Array[int] = []
	for index in station_count:
		var node_index := 0
		if kind == "maze":
			node_index = int(shape.maze.rooms[index % shape.maze.rooms.size()])
		elif index > 0:
			node_index = rng.randi_range(1, shape.islands.size() - 1) * 4 if kind == "sky" else rng.randi_range(1, nodes.size() - 1)
		occupied.append(node_index)
		var point: Vector3 = nodes[node_index]
		if kind == "surface":
			var sampler := BiomeTerrain.new(field, Vector2(point.x, point.z))
			var highest := point.y
			for dx: float in [-6, 0, 6]:
				for dz: float in [-6, 0, 6]:
					highest = maxf(highest, sampler.sample(point.x + dx, point.z + dz))
			point.y = highest
		point.y += 1.2
		_station(result, biome, point, index)
	var choices: Array[int] = []
	for index in catalog.manifest.mission_templates.size():
		choices.append(index)
	for index in range(choices.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var value := choices[index]
		choices[index] = choices[other]
		choices[other] = value
	var task_count := rng.randi_range(2, mini(5, choices.size()))
	for slot in task_count:
		var node_index := rng.randi_range(0, nodes.size() - 1)
		for attempt in 30:
			if not occupied.has(node_index):
				break
			node_index = rng.randi_range(0, nodes.size() - 1)
		occupied.append(node_index)
		var ground: Vector3 = nodes[node_index]
		var mission := catalog.manifest.mission_templates[choices[slot]].duplicate() as MissionDefinition
		mission.id = "proc:4:%s:%d:%d:%d" % [kind, key.x, key.y, slot]
		mission.generated = true
		mission.station_id = result.stations[slot % result.stations.size()].id
		mission.source_point = result.stations[slot % result.stations.size()].point
		mission.location_id = mission.id + ":target"
		mission.display_name += " · " + biome.display_name + " %d,%d" % [key.x, key.y]
		var beacon := ground + Vector3.UP * 2.5
		mission.target_point = beacon if mission.kind == "photo" else ground + Vector3(0, 1.2 if mission.kind in ["courier", "survey", "hold_interact"] else 6, 3)
		mission.target_bounds = AABB(beacon - Vector3(1, 2.5, 1), Vector3(2, 5, 2))
		mission.checkpoints = PackedVector3Array()
		if mission.kind == "courier":
			mission.checkpoints = PackedVector3Array([mission.target_point, mission.source_point])
		elif mission.kind == "circuit":
			var available: Array[int] = []
			for candidate in nodes.size():
				if not occupied.has(candidate):
					available.append(candidate)
			if available.size() < 3:
				available.append(node_index)
			for checkpoint in mini(rng.randi_range(3, 5), available.size()):
				var choice := rng.randi_range(0, available.size() - 1)
				var target := available[choice]
				available.remove_at(choice)
				occupied.append(target)
				mission.checkpoints.append(nodes[target] + Vector3.UP * 6)
			mission.target_point = mission.checkpoints[0]
			mission.description = "跟随导航依次穿过 %d 个实体巡检门，已通过的航点自动保存，无倒计时。" % mission.checkpoints.size()
		_objective_structure(result, mission, ground, kind, rng)
		var location := _location(result, biome, mission.location_id, mission.display_name, "mission", mission.target_point)
		location.description = mission.description
		result.missions.append(mission)
	# Reuse the common platform geometry, without v3's shared decorative mission beacon.
	var service_plan := {"stations": result.stations, "missions": []}
	for station: Dictionary in result.stations:
		var point: Vector3 = station.point
		for object: Dictionary in RegionalWorld.service_objects(service_plan, WorldGenerator.key_at(point)):
			if object.id.ends_with("/beacon"):
				continue
			if "/support" in object.id:
				object.size.y = 3 if kind != "surface" else 12
				object.center.y = float(station.top) - object.size.y * 0.5
			result.objects.append(object)
	# Bucket by geometric ownership before workers request chunks. Mesh sectors sharing
	# a key are merged so a large island does not create hundreds of draw nodes.
	var entrances: Array[Dictionary] = []
	if kind == "surface":
		var bounds: AABB = biome.region_bounds
		for underground_site in field.volume_sites("maze", Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))):
			entrances.append_array(plan("maze", underground_site.key).shape.entries)
	MissionCourses.expand(result, catalog, field, entrances)
	MissionSites.populate(result, field, entrances)
	BiomeLandmarks.populate(result, field, entrances)
	FlowCourses.populate(result, field, entrances)
	FollowCourses.populate(result, field, entrances)
	RegionalSites.populate(result, field, catalog, entrances)
	RegionalFeatures.populate(result, field, entrances)
	PrecisionCourses.populate(result, field, entrances)
	AcroCourses.populate(result, field, entrances)
	CavePassages.populate(result, field, entrances)
	for landmark: Dictionary in result.landmarks:
		if not landmark.get("map_visible", true): continue
		var location := _location(result, biome, landmark.id, landmark.name, "landmark", landmark.marker)
		location.description = "随机特色建筑 · 可自行飞抵探索；非传送点。"
	_bucket(result)
	return result

func _objective_structure(result: Dictionary, mission: MissionDefinition, ground: Vector3, kind: String, rng: RandomNumberGenerator) -> void:
	if mission.kind == "circuit":
		if kind == "maze":
			for index in mission.checkpoints.size():
				result.objects.append(WorldProvider.box(mission.id + "/checkpoint%d" % index, mission.checkpoints[index] + Vector3.UP * 5, Vector3(3, 0.3, 3), Color("dfc482"), true, "screen"))
			mission.description = "沿连通走廊依次抵达 %d 个巡检节点（顶部标灯），逐阶段保存，无倒计时。" % mission.checkpoints.size()
			return
		for index in mission.checkpoints.size():
			var point := mission.checkpoints[index]
			var along_x := rng.randf() < 0.5
			for side: float in [-1, 1]:
				var offset := Vector3(side * 4, 0, 0) if along_x else Vector3(0, 0, side * 4)
				result.objects.append(WorldProvider.box(mission.id + "/gate%d/post%s" % [index, side], point + offset, Vector3(0.6, 8.6, 0.6), Color("d2ac67"), true, "metal"))
				result.objects.append(WorldProvider.box(mission.id + "/gate%d/bar%s" % [index, side], point + Vector3(0, side * 4, 0), Vector3(8.6, 0.6, 0.6) if along_x else Vector3(0.6, 0.6, 8.6), Color("86c8be"), true, "metal"))
		return
	if mission.kind == "photo":
		var height := 6.0 if kind == "maze" else rng.randf_range(8, 13)
		var center := ground + Vector3.UP * height * 0.5
		var size := Vector3(5, height, 5)
		var object := WorldProvider.box(mission.id + "/landmark", center, size, Color("91aba0"), true, "metal")
		object.primitive = "cylinder" if rng.randf() < 0.5 else "box"
		result.objects.append(object)
		result.objects.append(WorldProvider.box(mission.id + "/landmark_crown", ground + Vector3.UP * height, Vector3(6, 0.6, 6), Color("c5af79"), true, "metal"))
		mission.target_point = center
		mission.target_bounds = AABB(ground - Vector3(3.1, 0.1, 3.1), Vector3(6.2, height + 0.8, 6.2))
		mission.display_name = mission.display_name.replace("信标摄影", "地标摄影")
		mission.description = "拍摄当地地标：距离10～45米、中心偏角不超过18°且无遮挡，按F12保存照片。"
		return
	var height := 2.0 if mission.kind in ["courier", "survey"] else 5.0
	var object := WorldProvider.box(mission.id + "/beacon", ground + Vector3.UP * height * 0.5, Vector3(2, height, 2), Color("b5a47b"), true, "metal")
	if mission.kind == "survey":
		object.primitive = "cylinder"
	result.objects.append(object)
	result.objects.append(WorldProvider.box(mission.id + "/panel", ground + Vector3(0, height * 0.75, 1.03), Vector3(1.5, height * 0.25, 0.08), Color("bfe6ba"), true, "screen"))

func _station(result: Dictionary, biome: BiomeDefinition, point: Vector3, index: int) -> void:
	var id: String = "v4:" + result.id + ":p%d" % index
	var title := biome.display_name + " %d,%d / %d" % [result.key.x, result.key.y, index + 1]
	result.stations.append({"id": id, "name": title, "point": point, "top": point.y - 0.7, "biome_id": biome.id, "city_tag": "industrial", "beacon": point, "layer": result.kind})
	var location := _location(result, biome, id, title + " · 服务平台", "teleport", point)
	location.description = "停稳后按 E：商店、套机、更换配件和参数微调。"

func _location(result: Dictionary, biome: BiomeDefinition, id: String, title: String, kind: String, point: Vector3) -> MapLocation:
	var location := MapLocation.new()
	location.id = id
	location.display_name = title
	location.kind = kind
	location.point = point
	location.structure_id = result.id
	location.layer = result.kind
	if result.kind == "maze":
		location.interior_bounds = biome.region_bounds
		var entry: Dictionary = result.shape.entries[0]
		location.approach = PackedVector3Array([entry.top + Vector3.UP * 4, entry.bottom])
	result.locations.append(location)
	return location

func _bucket(result: Dictionary) -> void:
	var merged: Dictionary = {}
	var seen: Dictionary = {}
	for object: Dictionary in result.objects:
		if seen.has(object.id):
			continue
		seen[object.id] = true
		var key := WorldGenerator.key_at(object.center)
		if not result.chunks.has(key):
			result.chunks[key] = []
		if object.get("primitive", "") != "terrain" or object.get("unmerged", false):
			result.chunks[key].append(object)
			continue
		if not merged.has(key):
			merged[key] = {"id": result.id + "/mesh/" + str(key), "primitive": "terrain", "center": object.center, "size": object.size, "solid": true, "color": Color.WHITE, "vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "indices": PackedInt32Array(), "surfaces": PackedInt32Array(), "surface_names": object.surface_names}
		var mesh: Dictionary = merged[key]
		var offset: int = mesh.vertices.size()
		mesh.vertices.append_array(object.vertices)
		mesh.normals.append_array(object.normals)
		mesh.colors.append_array(object.colors)
		mesh.surfaces.append_array(object.surfaces)
		for index: int in object.indices:
			mesh.indices.append(index + offset)
	for key: Vector3i in merged:
		result.chunks[key].append(merged[key])
	result.objects.clear()

func region(key: Vector2i) -> Dictionary:
	plan_mutex.lock()
	var cached: Dictionary = pages.get(key, {})
	plan_mutex.unlock()
	if not cached.is_empty(): return cached
	var area := Rect2(Vector2(key) * SIZE, Vector2.ONE * SIZE)
	var result := {"biomes": [], "stations": [], "missions": [], "locations": []}
	for site in field.sites_near(area.get_center(), 2):
		# The polygon's conservative box is sufficient for paging; the field itself
		# always selects the actual biome at a queried world position.
		var polygon := field.polygon(site)
		var bounds := Rect2(polygon[0], Vector2.ZERO)
		for point in polygon:
			bounds = bounds.expand(point)
		if area.intersects(bounds):
			_merge(result, plan("surface", site.key))
	for kind: String in ["sky", "maze"]:
		for site in field.volume_sites(kind, area):
			var p := plan(kind, site.key)
			var bounds: AABB = p.biomes[0].region_bounds
			if area.intersects(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))):
				_merge(result, p)
	plan_mutex.lock()
	if pages.size() >= 16: pages.erase(pages.keys()[0])
	pages[key] = result
	plan_mutex.unlock()
	return result

func _merge(result: Dictionary, source: Dictionary) -> void:
	for collection: String in ["biomes", "stations", "missions", "locations"]:
		result[collection].append_array(source[collection])

func mission(id: String) -> MissionDefinition:
	var fields := id.split(":")
	if fields.size() < 6: return null
	if fields[-1] == "spatial": fields = fields.slice(0, fields.size() - 1)
	if fields[-1] == "smooth": fields = fields.slice(0, fields.size() - 1)
	var base_fields := fields.slice(0, fields.size() - 1) if fields[-1] == "acro" else fields
	if base_fields[-1] == "precision": base_fields = base_fields.slice(0, base_fields.size() - 1)
	if base_fields.size() not in [6, 7, 8] or (base_fields.size() >= 7 and base_fields[6] not in ["play", "regional"]) or (base_fields.size() == 8 and (base_fields[6] != "play" or base_fields[7] != "flow")) or fields[0] != "proc" or fields[1] != "4" or fields[2] not in ["surface", "sky", "maze"] or not fields[3].is_valid_int() or not fields[4].is_valid_int():
		return null
	var p := instance(":".join([fields[2], fields[3], fields[4]]))
	for definition: MissionDefinition in p.get("missions", []) + p.get("legacy_missions", []):
		if definition.id == id:
			return definition
	return null

func spawn_point() -> Vector3:
	return plan("surface", field.nearest(Vector2.ZERO).key).stations[0].point

func instance(id: String) -> Dictionary:
	var fields := id.split(":")
	if fields.size() != 3 or fields[0] not in ["surface", "sky", "maze"] or not fields[1].is_valid_int() or not fields[2].is_valid_int():
		return {}
	plan_mutex.lock()
	var cached: Dictionary = summaries.get(id, {})
	plan_mutex.unlock()
	return cached if not cached.is_empty() else plan(fields[0], Vector2i(int(fields[1]), int(fields[2])))

func instance_at(point: Vector3) -> Dictionary:
	var area := Rect2(Vector2(point.x, point.z), Vector2.ONE)
	for kind: String in ["sky", "maze"]:
		for site in field.volume_sites(kind, area):
			var p := plan(kind, site.key)
			if p.biomes[0].region_bounds.has_point(point):
				return p
	return plan("surface", field.nearest(Vector2(point.x, point.z)).key)

func biome_at(point: Vector3) -> BiomeDefinition:
	return instance_at(point).biomes[0]

func map_task(p: Dictionary) -> String:
	if p.is_empty() or p.biomes[0].parameters.get("map_unlock", "visit") != "mission":
		return ""
	for kind: String in ["survey", "hold_interact", "courier", "circuit", "photo"]:
		for mission: MissionDefinition in p.missions:
			if mission.kind == kind:
				return mission.id
	# Use an existing deterministic mission so saved objective IDs retain meaning.
	return p.missions[0].id

func generate_chunk(key: Vector3i) -> Dictionary:
	var origin := WorldGenerator.origin_of(key)
	var area := Rect2(Vector2(origin.x, origin.z), Vector2.ONE * 64)
	var objects: Array[Dictionary] = []
	var shafts: Array[Dictionary] = []
	for kind: String in ["sky", "maze"]:
		if kind == "sky" and (key.y < 0 or key.y > 5):
			continue
		if kind == "maze" and (key.y < -3 or key.y > 1):
			continue
		for site in field.volume_sites(kind, area.grow(64)):
			var p := plan(kind, site.key)
			objects.append_array(p.chunks.get(key, []))
			if kind == "maze":
				shafts.append_array(p.shape.entries)
	if key.y in [-2, -1, 0, 1, 2, 3, 4]:
		var sites: Dictionary = {}
		for site in field.sites_near(area.get_center(), 1):
			var polygon := field.polygon(site)
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for vertex in polygon:
				bounds = bounds.expand(vertex)
			# Large landmarks can overhang a biome border into this chunk.
			if bounds.grow(64).intersects(area):
				sites[site.id] = site
		var clearings: Array[Vector3] = []
		var caves: Array[Dictionary] = []
		var landmark_reservations: Array[Rect2] = []
		for site: Dictionary in sites.values():
			var p := plan("surface", site.key)
			caves.append_array(CaveNetworks.flattened(p.get("caves", [])))
			objects.append_array(p.chunks.get(key, []))
			for landmark: Dictionary in p.landmarks:
				landmark_reservations.append(Rect2(Vector2(landmark.point.x - landmark.size.x / 2 - 3, landmark.point.z - landmark.size.z / 2 - 3), Vector2(landmark.size.x + 6, landmark.size.z + 6)))
			landmark_reservations.append_array(p.get("course_reservations", []))
			for station: Dictionary in p.stations:
				clearings.append(station.point)
			for objective: MissionDefinition in p.missions + p.get("legacy_missions", []):
				clearings.append(objective.acceptance_point())
				# Street gates use narrow flight corridors. The ordinary 18m task
				# clearing would erase the very facades these routes pass alongside.
				if objective.challenge.get("route_revision", 0) > 0 and p.biomes[0].provider_id == "base.generator.modular_city":
					continue
				clearings.append(objective.target_point)
				clearings.append_array(objective.checkpoints)
		var site := field.nearest(area.get_center())
		var biome := site.biome.duplicate() as BiomeDefinition
		biome.parameters = biome.parameters.duplicate(true)
		biome.parameters.clearings = clearings
		biome.parameters.landmark_reservations = landmark_reservations
		var provider := BiomeSurfaceProvider.new("city" if biome.provider_id == "base.generator.modular_city" else "forest" if biome.provider_id == "base.generator.pine_valley" else "canyon", field, area.get_center(), shafts)
		provider.caves = caves
		if key.y in [-2, -1, 0, 1, 2, 3, 4]:
			objects.append_array(provider.generate(key, seed_value, biome))
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"key": key, "objects": objects, "world_version": 4}

func extra_visible_chunks(point: Vector3) -> Array[Vector3i]:
	var keys: Array[Vector3i] = []
	# Tall contiguous structures retain their upper decks from ground level.
	for site in field.sites_near(Vector2(point.x, point.z), 1):
		if site.biome.parameters.get("feature_profile", "") != "megastructure":
			continue
		var p := plan("surface", site.key)
		for key: Vector3i in p.chunks:
			var center := WorldGenerator.origin_of(key) + Vector3.ONE * 32
			if absf(center.x - point.x) < 280 and absf(center.z - point.z) < 280 and not keys.has(key):
				keys.append(key)
	if point.y < 80:
		return keys
	for site in field.volume_sites("sky", Rect2(Vector2(point.x, point.z), Vector2.ONE)):
		var p := plan("sky", site.key)
		if Rect2(Vector2(p.shape.bounds.position.x, p.shape.bounds.position.z), Vector2(p.shape.bounds.size.x, p.shape.bounds.size.z)).grow(120).has_point(Vector2(point.x, point.z)):
			for key: Vector3i in p.chunks:
				keys.append(key)
	keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return WorldGenerator.origin_of(a).distance_squared_to(point) < WorldGenerator.origin_of(b).distance_squared_to(point))
	return keys.slice(0, 96)

func route(from: Vector3, location: MapLocation) -> PackedVector3Array:
	var source: Dictionary = {}
	var in_shaft := false
	for site in field.volume_sites("maze", Rect2(Vector2(from.x, from.z), Vector2.ONE)):
		var p := plan("maze", site.key)
		if p.shape.bounds.has_point(from):
			source = p
			break
		for entry: Dictionary in p.shape.entries:
			if entry.hole.has_point(Vector2(from.x, from.z)) and from.y < entry.top.y + 1 and from.y > entry.bottom.y:
				source = p
				in_shaft = true
				break
	var target: Dictionary = {}
	if location.structure_id.begins_with("maze:"):
		var fields := location.structure_id.split(":")
		target = plan("maze", Vector2i(int(fields[1]), int(fields[2])))
	var points := PackedVector3Array()
	if not source.is_empty() and source.id != target.get("id", ""):
		var entry: Dictionary = source.shape.entries[0]
		if in_shaft:
			for candidate: Dictionary in source.shape.entries:
				if candidate.hole.has_point(Vector2(from.x, from.z)):
					entry = candidate
					break
		if not in_shaft:
			var exit_path := BiomeStructures.maze_path(source.shape.maze, BiomeStructures.cell_at(source.shape.maze, from), entry.cell)
			points.append_array(exit_path.slice(1) if exit_path.size() > 1 else exit_path)
		points.append(entry.top + Vector3.UP * 4)
	if not target.is_empty():
		var data: Dictionary = target.shape.maze
		var start: int
		if source.get("id", "") == target.id:
			start = BiomeStructures.cell_at(data, from)
		else:
			var entry: Dictionary = target.shape.entries[0]
			points.append(entry.top + Vector3.UP * 4)
			points.append(entry.bottom)
			start = entry.cell
		var inside_path := BiomeStructures.maze_path(data, start, BiomeStructures.cell_at(data, location.point))
		# Already occupying this cell does not require touching its center first.
		if source.get("id", "") == target.id and inside_path.size() > 1:
			inside_path = inside_path.slice(1)
		points.append_array(inside_path)
	points.append(location.point)
	return points
