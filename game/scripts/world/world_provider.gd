class_name WorldProvider
extends RefCounted
## Pure descriptors. No nodes, scene-tree access or shared RNG in generation jobs.

var kind: String
const SIZE := 64.0

func _init(provider_kind: String) -> void:
	kind = provider_kind

func generate(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB] = []) -> Array[Dictionary]:
	match kind:
		"city": return _city(key, seed_value, biome, reservations)
		"canyon": return _canyon(key, seed_value, biome, reservations)
		"sky": return _sky(key, biome)
		"underground": return _underground(key, biome)
	return []

static func box(id: String, center: Vector3, size: Vector3, color: Color, solid: bool = true) -> Dictionary:
	return {"id": id, "center": center, "size": size, "color": color, "solid": solid}

static func noise_at(x: int, z: int, seed_value: int) -> float:
	# Small bounded integers avoid platform-dependent overflow and mutable RNG state.
	var value := posmod(x * 374761 + z * 668265 + seed_value * 127, 2147483647)
	value = posmod((value ^ (value >> 13)) * 127, 2147483647)
	return float(value % 65536) / 65535.0

func _city(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base := Vector3(key.x * SIZE, 0, key.z * SIZE)
	var prefix := biome.id + "/" + str(key) + "/"
	var colors := biome.palette
	for reservation in reservations:
		var footprint := Rect2(Vector2(base.x, base.z), Vector2(64, 64))
		var reserved := Rect2(Vector2(reservation.position.x, reservation.position.z), Vector2(reservation.size.x, reservation.size.z))
		if footprint.intersects(reserved):
			return out
	if key.y == -1:
		out.append(box(prefix + "ground", base + Vector3(32, -1, 32), Vector3(64, 2, 64), colors[0].darkened(0.25)))
		return out
	if key.y != 0:
		return out
	for x in [16, 48]:
		for z in [16, 48]:
			var center := base + Vector3(x, 0, z)
			if Vector2(center.x, center.z - 16).length() < 38:
				continue
			var n := noise_at(int(center.x), int(center.z), seed_value)
			var height := snappedf(lerpf(float(biome.parameters.building_min), float(biome.parameters.building_max), n), 2.0)
			out.append(box(prefix + str(x) + ":" + str(z), center + Vector3(0, height * 0.5, 0), Vector3(20, height, 20), colors[0].lightened(0.08 if n > 0.5 else 0.0)))
			out.append(box(prefix + "roof" + str(x) + str(z), center + Vector3(0, height + 0.5, 0), Vector3(22, 1, 22), colors[1]))
			for floor_index in range(1, int(height / 5)):
				out.append(box(prefix + "band" + str(x) + str(z) + str(floor_index), center + Vector3(0, floor_index * 5, 0), Vector3(20.2, 0.35, 20.2), colors[2], false))
			out.append(box(prefix + "antenna" + str(x) + str(z), center + Vector3(5, height + 3, 5), Vector3(0.6, 6, 0.6), colors[2]))
	# One owner per complete bridge. Adjacent chunks' collision halo includes overhangs.
	var bridge_center := base + Vector3(0, 0, 32)
	for side: float in [-1.0, 1.0]:
		out.append(box(prefix + "pillar" + str(side), bridge_center + Vector3(side * 8, 6, 0), Vector3(2, 12, 3), colors[1]))
	out.append(box(prefix + "bridge", bridge_center + Vector3(0, 12, 0), Vector3(20, 1.5, 5), colors[1]))
	for z in [8, 24, 40, 56]:
		out.append(box(prefix + "road" + str(z), base + Vector3(0, 0.015, z), Vector3(0.25, 0.025, 3), colors[2], false))
	return out

func _canyon(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if key.y < -1 or key.y > 0:
		return out
	for x in [8, 24, 40, 56]:
		for z in [8, 24, 40, 56]:
			var wx: int = key.x * 64 + x
			var wz: int = key.z * 64 + z
			var river := absf(float(wx) - 240.0 - sin(float(wz) * 0.009) * 45.0)
			var distance_from_city := maxf(maxf(float(wx - 128), float(-256 - wx)), maxf(float(wz - 256), float(-256 - wz)))
			var height := lerpf(0.0, -18.0 if river < 34 else 10 + noise_at(wx, wz, seed_value) * 36, clampf(distance_from_city / 80, 0, 1))
			height = snappedf(height, 2)
			var center := Vector3(wx, (-48 + height) * 0.5, wz)
			if WorldGenerator.key_at(center) != key:
				continue
			var blocked := false
			for reservation in reservations:
				blocked = blocked or Rect2(Vector2(wx - 8, wz - 8), Vector2(16, 16)).intersects(Rect2(Vector2(reservation.position.x, reservation.position.z), Vector2(reservation.size.x, reservation.size.z)))
			if blocked:
				continue
			var color := biome.palette[0 if river < 34 else 1]
			out.append(box(biome.id + "/column/" + str(wx) + "/" + str(wz), center, Vector3(16, 48 + height, 16), color))
	return out

func _sky(key: Vector3i, biome: BiomeDefinition) -> Array[Dictionary]:
	var anchor: Vector3 = biome.parameters.get("anchor", Vector3(112, 108, -80))
	if key != WorldGenerator.key_at(anchor):
		return []
	var p := biome.palette
	var out: Array[Dictionary] = [box(biome.id + "/cap", Vector3(112, 109, -80), Vector3(72, 10, 64), p[1]),
		box(biome.id + "/base", Vector3(112, 98, -80), Vector3(48, 12, 44), p[0]),
		box(biome.id + "/keel", Vector3(112, 88, -80), Vector3(24, 10, 22), p[0]),
		box(biome.id + "/station", Vector3(130, 122, -94), Vector3(15, 16, 14), p[0]),
		box(biome.id + "/beacon", Vector3(130, 135, -94), Vector3(2, 10, 2), p[2]),
		box(biome.id + "/pad", Vector3(100, 114.25, -68), Vector3(12, 0.5, 12), p[2])]
	return _translate(out, anchor - Vector3(112, 108, -80))

func _underground(key: Vector3i, biome: BiomeDefinition) -> Array[Dictionary]:
	var anchor: Vector3 = biome.parameters.get("anchor", Vector3(-96, -24, -96))
	if key != WorldGenerator.key_at(anchor):
		return []
	var p := biome.palette
	var prefix := biome.id
	var out: Array[Dictionary] = [box(prefix + "/floor", Vector3(-96, -49, -96), Vector3(64, 2, 64), p[0])]
	for side: float in [-1, 1]:
		out.append(box(prefix + "/wall_x" + str(side), Vector3(-96 + 31 * side, -24, -96), Vector3(2, 48, 64), p[0]))
		out.append(box(prefix + "/wall_z" + str(side), Vector3(-96, -24, -96 + 31 * side), Vector3(64, 48, 2), p[0]))
		out.append(box(prefix + "/roof_x" + str(side), Vector3(-96 + 20 * side, -1, -96), Vector3(24, 2, 64), p[0]))
		out.append(box(prefix + "/roof_z" + str(side), Vector3(-96, -1, -96 + 20 * side), Vector3(16, 2, 24), p[0]))
		out.append(box(prefix + "/light" + str(side), Vector3(-96 + 28 * side, -20, -96), Vector3(0.5, 2, 46), p[2], false))
	out.append(box(prefix + "/deck", Vector3(-96, -46, -112), Vector3(16, 4, 12), p[1]))
	out.append(box(prefix + "/pillar", Vector3(-112, -30, -80), Vector3(4, 36, 4), p[1]))
	return _translate(out, anchor - Vector3(-96, -24, -96))

func _translate(objects: Array[Dictionary], offset: Vector3) -> Array[Dictionary]:
	for object: Dictionary in objects:
		object.center += offset
	return objects
