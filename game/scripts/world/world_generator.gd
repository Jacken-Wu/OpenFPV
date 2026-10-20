class_name WorldGenerator
extends RefCounted

const CHUNK_SIZE := 64.0
var providers: Dictionary = {}
var biomes: Array[BiomeDefinition] = []
var seed_value: int
var reservations: Array[AABB] = []

func _init(content: ContentCatalog, world_seed: int) -> void:
	seed_value = world_seed
	biomes = content.biomes.duplicate()
	for biome in biomes:
		if biome.parameters.has("surface_reservation"):
			reservations.append(biome.parameters.surface_reservation)
	register_provider("base.generator.modular_city", WorldProvider.new("city"))
	register_provider("base.generator.canyon", WorldProvider.new("canyon"))
	register_provider("base.generator.sky_island", WorldProvider.new("sky"))
	register_provider("base.generator.underground", WorldProvider.new("underground"))
	biomes.sort_custom(func(a: BiomeDefinition, b: BiomeDefinition) -> bool: return a.priority > b.priority if a.priority != b.priority else a.id < b.id)

func register_provider(id: String, provider: WorldProvider) -> void:
	providers[id] = provider

static func key_at(point: Vector3) -> Vector3i:
	return Vector3i(floori(point.x / CHUNK_SIZE), floori(point.y / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))

static func origin_of(key: Vector3i) -> Vector3:
	return Vector3(key) * CHUNK_SIZE

func biome_at(point: Vector3) -> BiomeDefinition:
	for biome in biomes:
		if biome.parameters.get("layer", "") == "volume" and biome.region_bounds.has_point(point):
			return biome
	return surface_biome_at(point)

func surface_biome_at(point: Vector3) -> BiomeDefinition:
	for biome in biomes:
		if biome.parameters.get("layer", "") == "surface" and Rect2(Vector2(biome.region_bounds.position.x, biome.region_bounds.position.z), Vector2(biome.region_bounds.size.x, biome.region_bounds.size.z)).has_point(Vector2(point.x, point.z)):
			return biome
	return null

func generate(key: Vector3i) -> Dictionary:
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
	return {"key": key, "objects": objects, "world_version": 1}

func semantic_hash(key: Vector3i) -> int:
	return hash(generate(key))
