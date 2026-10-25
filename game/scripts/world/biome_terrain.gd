class_name BiomeTerrain
extends RefCounted
var field: BiomeField
var sites: Array[Dictionary]
var entrances: Array[Dictionary]

func _init(biome_field: BiomeField, point: Vector2, shafts: Array[Dictionary] = []) -> void:
	field = biome_field
	sites = field.sites_near(point, 2)
	entrances = shafts

func sample(x: float, z: float) -> float:
	var height := base_height(x, z)
	for entrance in entrances:
		var center: Vector3 = entrance.top
		var distance := maxf(absf(x - center.x), absf(z - center.z))
		height = lerpf(float(center.y), height, smoothstep(10, 34, distance))
	return height

func base_height(x: float, z: float) -> float:
	var p := field.warp(Vector2(x, z))
	var best: Dictionary = sites[0]
	var nearest := INF
	for site in sites:
		var distance := p.distance_squared_to(site.pos)
		if distance < nearest:
			nearest = distance
			best = site
	var city_distance := INF
	for site in sites:
		if site.biome.provider_id != "base.generator.modular_city":
			continue
		if site.id == best.id:
			city_distance = 0
			break
		var separation: float = Vector2(site.pos).distance_to(best.pos)
		city_distance = minf(city_distance, (p.distance_squared_to(site.pos) - nearest) / (2 * separation))
	var base := RegionalTerrainSampler.sample(x, z, field.seed_value, [])
	var style: String = best.biome.parameters.get("terrain_style", "")
	if not style.is_empty():
		var edge := INF
		for site in sites:
			if site.id != best.id:
				edge = minf(edge, (p.distance_squared_to(site.pos) - nearest) / (2 * Vector2(site.pos).distance_to(best.pos)))
		var local: Vector2 = Vector2(x, z) - Vector2(best.anchor)
		var ridge := 1.0 - absf(TerrainSampler.smooth_noise(x, z, 150, field.seed_value + 42001) * 2 - 1)
		var detail := TerrainSampler.smooth_noise(x, z, 42, field.seed_value + 42013)
		var shaped := base
		match style:
			"alpine": shaped = 30 + ridge * ridge * 125 + detail * 12
			"snow_peak": shaped = 45 + pow(ridge, 3) * 145 + detail * 8
			"snowfield": shaped = 8 + TerrainSampler.smooth_noise(x, z, 280, field.seed_value + 42019) * 14 + detail * 2
			"gobi": shaped = 12 + ridge * 24 + detail * 6
			"ravine": shaped = 16 + smoothstep(0.12, 0.48, absf(sin(local.x / 65 + sin(local.y / 150)))) * 65 + detail * 4
			"volcano":
				var radius := local.length()
				shaped = 12 + exp(-pow((radius - 115) / 65, 2)) * 148 + detail * 8
			"ruined_city": shaped = base * 0.25 + 6
			"monument": shaped = 14 + ridge * 16
		base = lerpf(base, shaped, smoothstep(0, 100, edge))
	return base * smoothstep(80, 160, city_distance)

func normal_at(x: float, z: float) -> Vector3:
	return Vector3(sample(x - 4, z) - sample(x + 4, z), 8, sample(x, z - 4) - sample(x, z + 4)).normalized()
