class_name BiomeField
extends RefCounted
## Warped Voronoi cells describe geography, independently of chunks and map pages.
var seed_value: int
var rules: Dictionary
var surfaces: Array[BiomeDefinition] = []
var volumes: Dictionary = {}
var site_cache: Dictionary = {}
var polygon_cache: Dictionary = {}
var cache_mutex := Mutex.new()
var extension_radius := 4

func _init(content: ContentCatalog, world_seed: int, preserved_radius: int = 4) -> void:
	seed_value = world_seed
	extension_radius = preserved_radius
	rules = content.manifest.generation_rules
	for biome: BiomeDefinition in content.biomes:
		if biome.parameters.layer == "surface":
			surfaces.append(biome)
		elif biome.tags.has("sky"):
			volumes.sky = biome
		elif biome.tags.has("underground"):
			volumes.maze = biome
	surfaces.sort_custom(func(a: BiomeDefinition, b: BiomeDefinition) -> bool: return a.id < b.id)

func roll(key: Vector2i, salt: int) -> float:
	return WorldProvider.noise_at(key.x, key.y, seed_value + salt)

func rng_for(key: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = posmod(key.x * 374761 + key.y * 668265 + seed_value * 127 + salt * 104729, 2147483647)
	return rng

func expanded_at(point: Vector2) -> bool:
	var key: Vector2i = nearest(point).key
	return maxi(absi(key.x), absi(key.y)) >= extension_radius

func warp(point: Vector2) -> Vector2:
	var strength := float(rules.get("warp", 110))
	return point + Vector2(TerrainSampler.smooth_noise(point.x, point.y, 1700, seed_value + 801) - 0.5, TerrainSampler.smooth_noise(point.x, point.y, 1700, seed_value + 907) - 0.5) * strength * 2

func unwarp(point: Vector2) -> Vector2:
	var result := point
	for iteration in 4:
		result += point - warp(result)
	return result

func surface_site(key: Vector2i) -> Dictionary:
	cache_mutex.lock()
	var cached: Dictionary = site_cache.get(key, {})
	cache_mutex.unlock()
	if not cached.is_empty():
		return cached
	var spacing := float(rules.get("surface_spacing", 768))
	var pos := (Vector2(key) + Vector2(0.24 + roll(key, 101) * 0.52, 0.24 + roll(key, 103) * 0.52)) * spacing
	var climate := Vector3(TerrainSampler.smooth_noise(pos.x, pos.y, 2200, seed_value + 1103), TerrainSampler.smooth_noise(pos.x, pos.y, 1800, seed_value + 1201), roll(key, 1237))
	var chosen: BiomeDefinition = surfaces[0]
	var score := INF
	for prototype in surfaces:
		if prototype.parameters.get("extension", false):
			continue
		var preferred: Vector3 = prototype.parameters.get("climate", Vector3(0.5, 0.5, 0.5))
		var distance := climate.distance_squared_to(preferred)
		if distance < score:
			score = distance
			chosen = prototype
	# Keep the original climate competition intact in the preserved world core.
	if maxi(absi(key.x), absi(key.y)) >= extension_radius and roll(key, 41003) < 0.62:
		var extensions := surfaces.filter(func(value: BiomeDefinition): return value.parameters.get("extension", false))
		if not extensions.is_empty():
			chosen = extensions[mini(extensions.size() - 1, int(roll(key, 41011) * extensions.size()))]
	var biome := chosen.duplicate() as BiomeDefinition
	biome.id += ":s4:%d:%d" % [key.x, key.y]
	biome.parameters = biome.parameters.duplicate(true)
	biome.parameters.start_clearing = false
	cached = {"key": key, "pos": pos, "anchor": unwarp(pos), "biome": biome, "id": "surface:%d:%d" % [key.x, key.y]}
	cache_mutex.lock()
	if site_cache.size() >= 256:
		site_cache.erase(site_cache.keys()[0])
	site_cache[key] = cached
	cache_mutex.unlock()
	return cached

func sites_near(point: Vector2, radius: int = 1) -> Array[Dictionary]:
	var p := warp(point) / float(rules.get("surface_spacing", 768))
	var key := Vector2i(floori(p.x), floori(p.y))
	var result: Array[Dictionary] = []
	for x in range(key.x - radius, key.x + radius + 1):
		for z in range(key.y - radius, key.y + radius + 1):
			result.append(surface_site(Vector2i(x, z)))
	return result

func nearest(point: Vector2, sites: Array[Dictionary] = []) -> Dictionary:
	var candidates := sites_near(point) if sites.is_empty() else sites
	var p := warp(point)
	var best: Dictionary = candidates[0]
	var distance := INF
	for site in candidates:
		var d := p.distance_squared_to(site.pos)
		if d < distance:
			distance = d
			best = site
	return best

func polygon(site: Dictionary) -> PackedVector2Array:
	cache_mutex.lock()
	var cached: PackedVector2Array = polygon_cache.get(site.key, PackedVector2Array())
	cache_mutex.unlock()
	if not cached.is_empty():
		return cached
	var pos: Vector2 = site.pos
	var size := float(rules.get("surface_spacing", 768)) * 1.6
	var points := PackedVector2Array([pos + Vector2(-size, -size), pos + Vector2(size, -size), pos + Vector2(size, size), pos + Vector2(-size, size)])
	for other in sites_near(site.anchor, 2):
		if other.id == site.id:
			continue
		var normal: Vector2 = other.pos - pos
		var limit: float = (Vector2(other.pos).length_squared() - pos.length_squared()) * 0.5
		var next := PackedVector2Array()
		for index in points.size():
			var a := points[index]
			var b := points[(index + 1) % points.size()]
			var da := a.dot(normal) - limit
			var db := b.dot(normal) - limit
			if da <= 0:
				next.append(a)
			if (da < 0 and db > 0) or (da > 0 and db < 0):
				next.append(a.lerp(b, da / (da - db)))
		points = next
	var result := PackedVector2Array()
	# Densify before unwarping so map borders follow the same curved geography.
	for index in points.size():
		for step in 5:
			result.append(unwarp(points[index].lerp(points[(index + 1) % points.size()], step / 5.0)))
	cache_mutex.lock()
	if polygon_cache.size() >= 256:
		polygon_cache.erase(polygon_cache.keys()[0])
	polygon_cache[site.key] = result
	cache_mutex.unlock()
	return result

func volume_site(kind: String, key: Vector2i) -> Dictionary:
	var spacing := float(rules.get(kind + "_spacing", 1536 if kind == "sky" else 1280))
	var chance := float(rules.get(kind + "_chance", 0.33 if kind == "sky" else 0.42))
	var salt := 2003 if kind == "sky" else 3001
	if roll(key, salt) > chance:
		return {}
	var pos := (Vector2(key) + Vector2(0.18 + roll(key, salt + 2) * 0.64, 0.18 + roll(key, salt + 4) * 0.64)) * spacing
	return {"kind": kind, "key": key, "pos": pos, "id": kind + ":%d:%d" % [key.x, key.y]}

func volume_sites(kind: String, area: Rect2) -> Array[Dictionary]:
	var spacing := float(rules.get(kind + "_spacing", 1536 if kind == "sky" else 1280))
	var first := Vector2i(floori(area.position.x / spacing) - 1, floori(area.position.y / spacing) - 1)
	var last := Vector2i(floori(area.end.x / spacing) + 1, floori(area.end.y / spacing) + 1)
	var result: Array[Dictionary] = []
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var key := Vector2i(x, z)
			var site := volume_site(kind, key)
			if site.is_empty():
				continue
			if area.grow(360 if kind == "sky" else 210).has_point(site.pos):
				result.append(site)
	return result
