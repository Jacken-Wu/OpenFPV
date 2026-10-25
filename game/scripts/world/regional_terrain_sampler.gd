class_name RegionalTerrainSampler
extends RefCounted
## v3 geography uses seeded fields rather than a fixed starting river or hill.

static func sample(x: float, z: float, seed_value: int, cities: Array[AABB]) -> float:
	var broad := TerrainSampler.smooth_noise(x, z, 256, seed_value + 11)
	var channel := absf(TerrainSampler.smooth_noise(x, z, 320, seed_value + 23) - 0.5)
	var detail := TerrainSampler.smooth_noise(x, z, 24, seed_value + 31)
	var fine := TerrainSampler.smooth_noise(x, z, 8, seed_value + 73)
	var height := lerpf(-12, 18 + broad * 28, smoothstep(0.035, 0.18, channel))
	height += (detail - 0.5) * 5 + (fine - 0.5) * 1.4
	var distance := INF
	for city in cities:
		var dx := maxf(maxf(city.position.x - x, x - city.end.x), 0)
		var dz := maxf(maxf(city.position.z - z, z - city.end.z), 0)
		distance = minf(distance, Vector2(dx, dz).length())
	return height * smoothstep(0, 56, distance)

static func normal_at(x: float, z: float, seed_value: int, cities: Array[AABB]) -> Vector3:
	return Vector3(sample(x - 1, z, seed_value, cities) - sample(x + 1, z, seed_value, cities), 2, sample(x, z - 1, seed_value, cities) - sample(x, z + 1, seed_value, cities)).normalized()
