class_name WorldExploration
extends RefCounted
## Maps retain visited biome instances; unseen geography is never materialized in UI.
var regions: RegionalWorld
var navigation: MapNavigation
var store: ProgressStore
var definitions: Array[MissionDefinition] = []
var stations: Array[Dictionary] = []
var biomes: Array[BiomeDefinition] = []
var page := Vector2i(999999, 999999)
var original: Array[MapLocation] = []
var physical_key := Vector2i(999999, 999999)
var physical_stations: Array = []
var seen: Dictionary = {}

func _init(progress: ProgressStore, map_navigation: MapNavigation) -> void:
	store = progress
	regions = store.regions
	navigation = map_navigation
	original = navigation.locations.duplicate()
	if regions is BiomeWorld:
		navigation.route_resolver = regions.route

func visit(point: Vector3) -> Dictionary:
	if not regions is BiomeWorld:
		return {}
	var result := store.visit_region(regions.instance_at(point).id)
	if result.get("changed", false):
		refresh(RegionalWorld.key_at(point))
	return result

func refresh(key: Vector2i) -> void:
	page = key
	var selected := navigation.selected()
	var temporary: Array[MapLocation] = navigation.locations.filter(func(location: MapLocation): return location.layer == "temporary")
	navigation.locations = original.duplicate()
	definitions.clear()
	stations.clear()
	biomes.clear()
	seen.clear()
	if regions is BiomeWorld:
		for id: String in store.data.exploration.visited:
			var p: Dictionary = regions.instance(id)
			if p.is_empty():
				continue
			if store.data.exploration.mapped.has(id):
				_add(p)
			else:
				# Only the survey objective is known before the special area's map.
				var task: String = regions.map_task(p)
				var partial := {"missions": [], "stations": [], "biomes": [], "locations": []}
				for mission: MissionDefinition in p.missions:
					if mission.id == task:
						partial.missions.append(mission)
						for location: MapLocation in p.locations:
							if location.id == mission.location_id:
								partial.locations.append(location)
				for location: MapLocation in p.locations:
					if store.portal_unlocked(location.id):
						partial.locations.append(location)
				_add(partial)
	else:
		for x in range(key.x - 1, key.x + 2):
			for z in range(key.y - 1, key.y + 2):
				_add(regions.region(Vector2i(x, z)))
	# Keep historical objectives available for replay, including replaced legacy courses.
	for id: String in store.data.assignments:
		var mission := store.mission_definition(id)
		if mission == null or not mission.generated or seen.has(id):
			continue
		if store.mission_status(id) != "active" and regions is BiomeWorld:
			var parts := id.split(":")
			var instance: Dictionary = regions.instance(":".join([parts[2], parts[3], parts[4]]))
			var replaced := false
			for candidate: MissionDefinition in instance.get("missions", []):
				replaced = replaced or candidate.history_id == id or (not mission.history_id.is_empty() and candidate.history_id == mission.history_id)
			if replaced: continue
		if mission.kind == "race" and mission.history_id.is_empty() and store.mission_status(id) != "active" and regions is BiomeWorld:
			var replacement := regions.mission(id + ":flow")
			if replacement != null and replacement.history_id == id:
				continue
		definitions.append(mission)
		var fields := mission.id.split(":")
		var p: Dictionary = regions.instance(":".join([fields[2], fields[3], fields[4]])) if regions is BiomeWorld else regions.region(RegionalWorld.key_at(mission.source_point))
		for candidate: MapLocation in p.locations + p.get("legacy_locations", []):
			if candidate.id == mission.location_id:
				_upsert(candidate.duplicate() as MapLocation)
	for location in temporary:
		if navigation.find_location(location.id) == null: navigation.locations.append(location)
	if selected != null and navigation.find_location(selected.id) == null and (store.portal_unlocked(selected.id) or selected.layer == "temporary"):
		navigation.locations.append(selected)

func _add(plan: Dictionary) -> void:
	for definition: MissionDefinition in plan.missions:
		if not seen.has(definition.id):
			definitions.append(definition)
			seen[definition.id] = true
	for station: Dictionary in plan.stations:
		if not seen.has(station.id):
			stations.append(station)
			seen[station.id] = true
	for biome: BiomeDefinition in plan.biomes:
		if not seen.has(biome.id):
			biomes.append(biome)
			seen[biome.id] = true
	for location: MapLocation in plan.locations:
		_upsert(location.duplicate() as MapLocation)

func _upsert(location: MapLocation) -> void:
	for index in navigation.locations.size():
		if navigation.locations[index].id == location.id:
			navigation.locations[index] = location
			return
	navigation.locations.append(location)

func station_at(point: Vector3) -> Dictionary:
	var key := RegionalWorld.key_at(point)
	if key != physical_key or physical_stations.is_empty():
		physical_key = key
		physical_stations = regions.region(key).stations
	for station: Dictionary in physical_stations:
		if absf(point.x - station.point.x) <= 5.2 and absf(point.z - station.point.z) <= 5.2 and absf(point.y - station.top) < 0.3:
			return station
	return {}
