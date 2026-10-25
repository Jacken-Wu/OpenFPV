class_name WorldGenerator
extends RefCounted

const CHUNK_SIZE := 64.0
var providers: Dictionary = {}
var biomes: Array[BiomeDefinition] = []
var seed_value: int
var reservations: Array[AABB] = []
var world_version := 4
var regions: RegionalWorld
var queried_key := Vector2i(999999, 999999)
var queried_biomes: Array = []

func _init(content: ContentCatalog, world_seed: int, version: int = 4, preserved_radius: int = 4) -> void:
	seed_value = world_seed
	world_version = version
	var cities: Array[AABB] = []
	for biome in content.biomes:
		if int(biome.parameters.get("min_world_version", 1)) <= world_version:
			biomes.append(biome)
			if biome.provider_id == "base.generator.modular_city":
				cities.append(biome.region_bounds)
	for biome in biomes:
		if biome.parameters.has("surface_reservation"):
			reservations.append(biome.parameters.surface_reservation)
	register_provider("base.generator.modular_city", LegacyWorldProvider.new("city") if version == 1 else WorldProvider.new("city", cities))
	register_provider("base.generator.canyon", LegacyWorldProvider.new("canyon") if version == 1 else WorldProvider.new("canyon", cities))
	register_provider("base.generator.sky_island", LegacyWorldProvider.new("sky") if version == 1 else RegionalWorldProvider.new("sky", cities) if version >= 3 else WorldProvider.new("sky", cities))
	register_provider("base.generator.underground", LegacyWorldProvider.new("underground") if version == 1 else RegionalWorldProvider.new("underground", cities) if version >= 3 else WorldProvider.new("underground", cities))
	register_provider("base.generator.pine_valley", WorldProvider.new("forest", cities))
	biomes.sort_custom(func(a: BiomeDefinition, b: BiomeDefinition) -> bool: return a.priority > b.priority if a.priority != b.priority else a.id < b.id)
	if world_version >= 3:
		regions = BiomeWorld.new(content, world_seed, preserved_radius) if world_version >= 4 else RegionalWorld.new(content, world_seed)

func register_provider(id: String, provider: RefCounted) -> void:
	providers[id] = provider

static func key_at(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))

static func origin_of(key: Vector3i) -> Vector3:
	return Vector3(key) * CHUNK_SIZE

func biome_at(point: Vector3) -> BiomeDefinition:
	if regions is BiomeWorld:
		return regions.biome_at(point)
	if regions != null:
		var key := RegionalWorld.key_at(point)
		if key != queried_key or queried_biomes.is_empty():
			queried_key = key
			queried_biomes = regions.region(key).biomes
		for biome: BiomeDefinition in queried_biomes:
			if biome.parameters.layer == "volume" and biome.region_bounds.has_point(point):
				return biome
		return queried_biomes[0]
	for biome in biomes:
		if biome.parameters.get("layer", "") == "volume" and biome.region_bounds.has_point(point):
			return biome
	return surface_biome_at(point)

func surface_biome_at(point: Vector3) -> BiomeDefinition:
	if regions is BiomeWorld:
		return regions.plan("surface", regions.field.nearest(Vector2(point.x, point.z)).key).biomes[0]
	if regions != null:
		return regions.region(RegionalWorld.key_at(point)).biomes[0]
	for biome in biomes:
		if biome.parameters.get("layer", "") == "surface" and Rect2(Vector2(biome.region_bounds.position.x, biome.region_bounds.position.z), Vector2(biome.region_bounds.size.x, biome.region_bounds.size.z)).has_point(Vector2(point.x, point.z)):
			return biome
	return null

func generate(key: Vector3i) -> Dictionary:
	if regions is BiomeWorld:
		return regions.generate_chunk(key)
	if regions != null:
		return _generate_regional(key)
	var objects: Array[Dictionary] = []
	var center := origin_of(key) + Vector3.ONE * 32
	var surface := surface_biome_at(center)
	if surface != null and providers.has(surface.provider_id):
		objects.append_array(providers[surface.provider_id].generate(key, seed_value, surface, reservations))
	for biome in biomes:
		if biome.parameters.get("layer", "") == "volume" and providers.has(biome.provider_id):
			# Providers own entire structures by stable key; broad bounds include their overhang.
			if biome.region_bounds.grow(CHUNK_SIZE).intersects(AABB(origin_of(key), Vector3.ONE * CHUNK_SIZE)):
				objects.append_array(providers[biome.provider_id].generate(key, seed_value, biome))
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"key": key, "objects": objects, "world_version": world_version}

func _generate_regional(key: Vector3i) -> Dictionary:
	var center := origin_of(key) + Vector3.ONE * 32
	var region_key := RegionalWorld.key_at(center)
	var plan := regions.region(region_key)
	var local_biomes: Array = plan.biomes
	var cities := regions.flattening_regions(region_key)
	var local_reservations: Array[AABB] = []
	for biome: BiomeDefinition in local_biomes:
		if biome.parameters.has("surface_reservation") and not local_reservations.has(biome.parameters.surface_reservation):
			local_reservations.append(biome.parameters.surface_reservation)
	var objects: Array[Dictionary] = []
	var surface := plan.biomes[0] as BiomeDefinition
	if surface != null:
		var kind: String = {"base.generator.modular_city": "city", "base.generator.pine_valley": "forest"}.get(surface.provider_id, "canyon")
		objects.append_array(RegionalWorldProvider.new(kind, cities).generate(key, seed_value, surface, local_reservations))
	for biome: BiomeDefinition in local_biomes:
		if biome.parameters.layer == "volume" and biome.region_bounds.grow(CHUNK_SIZE).intersects(AABB(origin_of(key), Vector3.ONE * CHUNK_SIZE)):
			for object: Dictionary in providers[biome.provider_id].generate(key, seed_value, biome):
				# v3 service platforms replace the old volume provider's landing pad.
				if not object.id.ends_with("/pad"):
					objects.append(object)
	objects.append_array(RegionalWorld.service_objects(plan, key))
	objects.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"key": key, "objects": objects, "world_version": world_version}

func semantic_hash(key: Vector3i) -> int:
	return hash(generate(key))

func extra_visible_chunks(point: Vector3) -> Array[Vector3i]:
	if regions is BiomeWorld:
		return regions.extra_visible_chunks(point)
	var empty: Array[Vector3i] = []
	return empty
