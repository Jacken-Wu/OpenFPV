class_name TerrainSampler
extends RefCounted
## Private surface-provider sampling, not the world's public geometry interface.

static func smooth_noise(x: float, z: float, scale: float, seed_value: int) -> float:
	var px := floori(x / scale)
	var pz := floori(z / scale)
	var tx := smoothstep(0, 1, x / scale - px)
	var tz := smoothstep(0, 1, z / scale - pz)
	var a := lerpf(LegacyWorldProvider.noise_at(px, pz, seed_value), LegacyWorldProvider.noise_at(px + 1, pz, seed_value), tx)
	var b := lerpf(LegacyWorldProvider.noise_at(px, pz + 1, seed_value), LegacyWorldProvider.noise_at(px + 1, pz + 1, seed_value), tx)
	return lerpf(a, b, tz)

static func sample(x: float, z: float, seed_value: int, cities: Array[AABB]) -> float:
	var river := absf(x - 240.0 - sin(z * 0.009) * 45.0)
	var large := smooth_noise(x, z, 96, seed_value)
	var detail := smooth_noise(x, z, 24, seed_value + 31)
	var fine := smooth_noise(x, z, 8, seed_value + 73)
	var rim := 17.0 + large * 24.0 + sin(z * 0.016) * 3.0
	var height := lerpf(-13.0 + detail * 2.0, rim, smoothstep(25, 68, river))
	height += (detail - 0.5) * 4.0 + (fine - 0.5) * 1.2
	height += exp(-pow((x - 650.0) / 180.0, 2)) * (13.0 + sin(z * 0.012) * 7.0)
	var distance := INF
	for city in cities:
		var dx := maxf(maxf(city.position.x - x, x - city.end.x), 0)
		var dz := maxf(maxf(city.position.z - z, z - city.end.z), 0)
		distance = minf(distance, Vector2(dx, dz).length())
	return height * smoothstep(0, 56, distance)

static func normal_at(x: float, z: float, seed_value: int, cities: Array[AABB]) -> Vector3:
	return Vector3(sample(x - 1, z, seed_value, cities) - sample(x + 1, z, seed_value, cities), 2, sample(x, z - 1, seed_value, cities) - sample(x, z + 1, seed_value, cities)).normalized()
