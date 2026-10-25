class_name BiomeLocator
extends RefCounted
## Searches procedural sites, including undiscovered geography, without unlocking it.
const MAX_RING := 12
var world: BiomeWorld

func _init(value: BiomeWorld) -> void:
	world = value

func choices() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for biome: BiomeDefinition in world.field.surfaces:
		result.append({"biome": biome, "kind": "surface", "name": biome.display_name})
	for kind: String in world.field.volumes:
		var biome: BiomeDefinition = world.field.volumes[kind]
		result.append({"biome": biome, "kind": kind, "name": "云海浮岛群" if kind == "sky" else "地下迷宫"})
	return result

func resolve(query: String) -> Dictionary:
	query = query.strip_edges().to_lower()
	var matches: Array[Dictionary] = []
	for choice in choices():
		var biome: BiomeDefinition = choice.biome
		var aliases: Array[String] = [biome.id.to_lower(), biome.id.get_slice(".", 2).trim_suffix("_fixture"), biome.display_name.to_lower(), String(choice.name).to_lower()]
		if choice.kind != "surface":
			aliases.append(choice.kind)
		if aliases.has(query):
			return choice
		if not query.is_empty() and (String(choice.name).contains(query) or biome.display_name.contains(query)):
			matches.append(choice)
	return matches[0] if matches.size() == 1 else {}

func locate(query: String, from: Vector3) -> Dictionary:
	var choice := resolve(query)
	if choice.is_empty() or not from.is_finite():
		return {"ok": false, "message": "找不到唯一群系；使用 /location list 查看名称与 ID。"}
	var field := world.field
	var kind: String = choice.kind
	var spacing := float(field.rules.get(kind + "_spacing", 768 if kind == "surface" else 1536 if kind == "sky" else 1280))
	var point := Vector2(from.x, from.z)
	var center := Vector2i(floori(point.x / spacing), floori(point.y / spacing))
	if choice.biome.parameters.get("extension", false) and field.extension_radius > MAX_RING - 2 and maxi(absi(center.x), absi(center.y)) < field.extension_radius:
		return _outer(choice, from, center)
	var distance := INF
	var best: Dictionary = {}
	var certified := false
	for radius in range(MAX_RING + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			for z in range(center.y - radius, center.y + radius + 1):
				if radius > 0 and maxi(absi(x - center.x), absi(z - center.y)) != radius:
					continue
				var site := field.surface_site(Vector2i(x, z)) if kind == "surface" else field.volume_site(kind, Vector2i(x, z))
				if site.is_empty():
					continue
				if kind == "surface" and not String(site.biome.id).begins_with(String(choice.biome.id) + ":"):
					continue
				var anchor: Vector2 = site.anchor if kind == "surface" else site.pos
				var candidate := point.distance_to(anchor)
				if candidate < distance:
					distance = candidate
					best = site
		# An unsearched anchor cannot cross this cell rectangle by more than warp.
		var left := float(center.x - radius) * spacing
		var top := float(center.y - radius) * spacing
		var right := float(center.x + radius + 1) * spacing
		var bottom := float(center.y + radius + 1) * spacing
		var bound := minf(minf(point.x - left, right - point.x), minf(point.y - top, bottom - point.y))
		if kind == "surface":
			bound -= sqrt(2.0) * float(field.rules.get("warp", 110))
		if distance < bound:
			certified = true
			break
	if not certified:
		return {"ok": false, "message": "在 %d 圈范围内未能确认最近实例；请换一个位置重试。" % MAX_RING}
	var plan := world.plan(kind, best.key)
	var target: Vector3 = plan.stations[0].point
	return {"ok": true, "id": plan.id, "kind": kind, "key": best.key, "name": choice.name, "point": target, "anchor": best.anchor if kind == "surface" else best.pos, "distance": distance,
		"message": "%s · 最近生成中心水平距离 %.0f m\n实例 %s · 平台坐标 %.1f, %.1f, %.1f\n使用 /tp location 前往该平台；定位不会提前解锁地图。" % [choice.name, distance, plan.id, target.x, target.y, target.z]}

func _outer(choice: Dictionary, from: Vector3, center: Vector2i) -> Dictionary:
	# Upgraded saves can preserve a core wider than the ordinary local search.
	# Search bounded boxes around all four nearest boundary projections, rather
	# than iterating the potentially enormous empty interior of that core.
	var radius := world.field.extension_radius
	var anchors: Array[Vector2i] = [Vector2i(radius, clampi(center.y, -radius, radius)), Vector2i(-radius, clampi(center.y, -radius, radius)), Vector2i(clampi(center.x, -radius, radius), radius), Vector2i(clampi(center.x, -radius, radius), -radius)]
	var best := {}
	var distance := INF
	for anchor in anchors:
		for x in range(anchor.x - MAX_RING, anchor.x + MAX_RING + 1):
			for z in range(anchor.y - MAX_RING, anchor.y + MAX_RING + 1):
				if maxi(absi(x), absi(z)) < radius:
					continue
				var site := world.field.surface_site(Vector2i(x, z))
				if not String(site.biome.id).begins_with(String(choice.biome.id) + ":"):
					continue
				var candidate: float = Vector2(from.x, from.z).distance_to(site.anchor)
				if candidate < distance:
					distance = candidate
					best = site
	if best.is_empty():
		return {"ok": false, "message": "外围搜索范围内未找到该群系，请到更远处重试。"}
	var plan := world.plan("surface", best.key)
	var target: Vector3 = plan.stations[0].point
	return {"ok": true, "id": plan.id, "kind": "surface", "key": best.key, "name": choice.name, "point": target, "anchor": best.anchor, "distance": distance, "message": "%s · 找到外围生成实例（已保留原探索范围）\n水平距离 %.0f m · 平台 %.1f, %.1f, %.1f\n使用 /tp location 前往，不会提前解锁地图。" % [choice.name, distance, target.x, target.y, target.z]}
