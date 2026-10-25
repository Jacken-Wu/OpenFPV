class_name RegionalWorld
extends RefCounted
## Stateless region plans: safe in generation workers and reproducible after a restart.

const SIZE := 512
var catalog: ContentCatalog
var seed_value: int
var surfaces: Array[BiomeDefinition] = []
var volumes: Array[BiomeDefinition] = []

func _init(content: ContentCatalog, world_seed: int) -> void:
	catalog = content
	seed_value = world_seed
	for biome: BiomeDefinition in content.biomes:
		if biome.parameters.layer == "surface":
			surfaces.append(biome)
		else:
			volumes.append(biome)
	surfaces.sort_custom(func(a: BiomeDefinition, b: BiomeDefinition) -> bool: return a.id < b.id)
	volumes.sort_custom(func(a: BiomeDefinition, b: BiomeDefinition) -> bool: return a.id < b.id)

static func key_at(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / SIZE), floori(point.z / SIZE))

func _surface_index(key: Vector2i) -> int:
	return mini(int(WorldProvider.noise_at(key.x, key.y, seed_value + 211) * surfaces.size()), surfaces.size() - 1)

func region(key: Vector2i) -> Dictionary:
	var plan := {"biomes": [], "stations": [], "missions": [], "locations": []}
	var origin := Vector3(key.x * SIZE, 0, key.y * SIZE)
	var biome := surfaces[_surface_index(key)].duplicate() as BiomeDefinition
	biome.id += ":%d:%d" % [key.x, key.y]
	biome.region_bounds = AABB(origin + Vector3(0, -64, 0), Vector3(SIZE, 192, SIZE))
	biome.parameters = biome.parameters.duplicate(true)
	biome.parameters.start_clearing = false
	biome.parameters.clearings = [origin + Vector3(256, 0, 256), origin + Vector3(128, 0, 128)]
	plan.biomes.append(biome)
	var cities := flattening_regions(key)
	var count := 2 if WorldProvider.noise_at(key.x, key.y, seed_value + 7) > 0.65 else 1
	for index in count:
		var point := origin + (Vector3(256, 0, 256) if index == 0 else Vector3(128, 0, 128))
		point.y = 1.2
		if biome.provider_id != "base.generator.modular_city":
			var highest := -INF
			for dx: float in [-6, 0, 6]:
				for dz: float in [-6, 0, 6]:
					highest = maxf(highest, RegionalTerrainSampler.sample(point.x + dx, point.z + dz, seed_value, cities))
			point.y = highest + 1.2
		_add_station(plan, "region:%d:%d:%d" % [key.x, key.y, index], biome.display_name + " %d,%d / %d" % [key.x, key.y, index + 1], point, biome, key, index)
	for index in volumes.size():
		var volume := volumes[index].duplicate() as BiomeDefinition
		var underground := volume.parameters.has("surface_reservation")
		var anchor := origin + (Vector3(352, -24, 352) if underground else Vector3(128, 108, 128))
		var offset: Vector3 = anchor - volume.parameters.anchor
		volume.id += ":%d:%d" % [key.x, key.y]
		volume.region_bounds.position += offset
		volume.parameters = volume.parameters.duplicate(true)
		volume.parameters.anchor = anchor
		volume.parameters.layout_variant = int(WorldProvider.noise_at(key.x, key.y, seed_value + 409) * 65535) % 3
		if underground:
			volume.parameters.surface_reservation = AABB(origin + Vector3(320, -2, 320), Vector3(64, 4, 64))
		plan.biomes.append(volume)
		var point := anchor + (Vector3(-6, -19, -16) if underground else Vector3(-12, 7, 12))
		_add_station(plan, "region:%d:%d:%d" % [key.x, key.y, index + 2], volume.display_name + " %d,%d" % [key.x, key.y], point, volume, key, index + 2)
	return plan

func flattening_regions(key: Vector2i) -> Array[AABB]:
	var result: Array[AABB] = []
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.y - 1, key.y + 2):
			var nearby := Vector2i(x, z)
			var origin := Vector3(x * SIZE, 0, z * SIZE)
			if surfaces[_surface_index(nearby)].provider_id == "base.generator.modular_city":
				result.append(AABB(origin, Vector3(SIZE, 1, SIZE)))
			result.append(AABB(origin + Vector3(320, 0, 320), Vector3(64, 1, 64)))
	return result

func _add_station(plan: Dictionary, id: String, title: String, point: Vector3, biome: BiomeDefinition, key: Vector2i, index: int) -> void:
	var direction := 1.0 if biome.parameters.has("surface_reservation") else -1.0
	var beacon := _clear_air(point + Vector3(0, 8, 16 * direction), biome)
	var station := {"id": id, "name": title, "point": point, "top": point.y - 0.7, "biome_id": biome.id, "city_tag": "industrial", "beacon": beacon}
	plan.stations.append(station)
	var portal := MapLocation.new()
	portal.id = id
	portal.display_name = title + " · 服务平台"
	portal.kind = "teleport"
	portal.point = point
	portal.description = "停稳在平台上按 E：购买配件 / 套机、更换装备、微调参数。"
	if biome.parameters.has("surface_reservation"):
		var anchor: Vector3 = biome.parameters.anchor
		portal.interior_bounds = AABB(anchor + Vector3(-30, -24, -30), Vector3(60, 24, 60))
		portal.approach = PackedVector3Array([anchor + Vector3(0, 32, 0), anchor + Vector3(0, -19, 0)])
	plan.locations.append(portal)
	for slot in 2:
		var template_index := posmod(index * 2 + slot + int(WorldProvider.noise_at(key.x, key.y, seed_value + 313) * 65535), catalog.manifest.mission_templates.size())
		var mission := catalog.manifest.mission_templates[template_index].duplicate() as MissionDefinition
		mission.id = "proc:3:%d:%d:%d:%d" % [key.x, key.y, index, slot]
		mission.generated = true
		mission.station_id = id
		mission.location_id = mission.id + ":target"
		mission.display_name = mission.display_name + " · " + title
		mission.source_point = point
		mission.target_point = beacon
		mission.target_bounds = AABB(mission.target_point - Vector3(1, 1.5, 1), Vector3(2, 3, 2))
		mission.checkpoints = PackedVector3Array([point + Vector3(-7, 9, 4 * direction), point + Vector3(0, 12, 16 * direction), point + Vector3(7, 9, 4 * direction)])
		for checkpoint in mission.checkpoints.size():
			mission.checkpoints[checkpoint] = _clear_air(mission.checkpoints[checkpoint], biome)
		if mission.kind == "courier":
			mission.checkpoints = PackedVector3Array([mission.target_point, point])
		if mission.kind == "circuit":
			mission.target_point = mission.checkpoints[0]
		var location := MapLocation.new()
		location.id = mission.location_id
		location.kind = "mission"
		location.point = mission.target_point
		location.display_name = mission.display_name
		location.description = mission.description
		location.interior_bounds = portal.interior_bounds
		location.approach = portal.approach
		plan.locations.append(location)
		plan.missions.append(mission)

func _clear_air(point: Vector3, biome: BiomeDefinition) -> Vector3:
	if biome.parameters.layer == "surface" and biome.provider_id != "base.generator.modular_city":
		point.y = maxf(point.y, RegionalTerrainSampler.sample(point.x, point.z, seed_value, flattening_regions(key_at(point))) + 4)
	return point

func mission(id: String) -> MissionDefinition:
	var fields := id.split(":")
	if fields.size() < 5 or fields[0] != "proc" or fields[1] != "3":
		return null
	var plan: Dictionary
	if fields.size() == 6 and fields[2].is_valid_int() and fields[3].is_valid_int():
		plan = region(Vector2i(int(fields[2]), int(fields[3])))
	else:
		return null
	for definition: MissionDefinition in plan.missions:
		if definition.id == id:
			return definition
	return null

static func service_objects(plan: Dictionary, key: Vector3i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for station: Dictionary in plan.stations:
		if WorldGenerator.key_at(station.point) != key:
			continue
		var point: Vector3 = station.point
		out.append(WorldProvider.box(station.id + "/service_pad", Vector3(point.x, station.top - 0.3, point.z), Vector3(12, 0.6, 12), Color("76ada4"), true, "landing"))
		for side: float in [-1, 1]:
			out.append(WorldProvider.box(station.id + "/edge" + str(side), point + Vector3(side * 5.5, -0.67, 0), Vector3(0.25, 0.06, 10), Color("e9c773"), false, "screen"))
		out.append(WorldProvider.box(station.id + "/terminal", point + Vector3(-4.5, 0.5, -4.5), Vector3(1, 2.4, 1), Color("365563"), true, "metal"))
		out.append(WorldProvider.box(station.id + "/display", point + Vector3(-4.5, 1, -3.98), Vector3(0.8, 0.7, 0.04), Color("8ce3cf"), false, "screen"))
		for side: float in [-1, 1]:
			out.append(WorldProvider.box(station.id + "/support" + str(side), point + Vector3(side * 4, -24.7, -4), Vector3(1, 48, 1), Color("566d70"), true, "metal"))
	for station: Dictionary in plan.stations:
		if WorldGenerator.key_at(station.beacon) == key:
			out.append(WorldProvider.box(station.id + "/beacon", station.beacon, Vector3(2, 3, 2), Color("deb274"), false, "screen"))
	return out
