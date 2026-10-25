class_name WorldProvider
extends RefCounted
## Pure descriptors. No nodes, scene-tree access or shared RNG in generation jobs.

var kind: String
const SIZE := 64.0
var city_regions: Array[AABB] = []

func _init(provider_kind: String, cities: Array[AABB] = []) -> void:
	kind = provider_kind
	city_regions = cities

func generate(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB] = []) -> Array[Dictionary]:
	match kind:
		"city": return _city(key, seed_value, biome, reservations)
		"canyon": return _canyon(key, seed_value, biome, reservations)
		"forest": return _canyon(key, seed_value, biome, reservations)
		"sky": return _sky(key, biome)
		"underground": return _underground(key, biome)
	return []

static func box(id: String, center: Vector3, size: Vector3, color: Color, solid: bool = true, surface: String = "paint") -> Dictionary:
	return {"id": id, "center": center, "size": size, "color": color, "solid": solid, "surface": surface}

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
		out.append(box(prefix + "ground", base + Vector3(32, -1, 32), Vector3(64, 2, 64), Color("434b50"), true, "asphalt"))
		return out
	if key.y != 0:
		return out
	var style: String = biome.parameters.get("architecture", "industrial")
	for x in [16, 48]:
		for z in [16, 48]:
			var center := base + Vector3(x, 0, z)
			if biome.parameters.get("start_clearing", true) and Vector2(center.x, center.z - 16).length() < 38:
				continue
			var n := noise_at(int(center.x), int(center.z), seed_value)
			var height := snappedf(lerpf(float(biome.parameters.building_min), float(biome.parameters.building_max), n), 1.0)
			var lot := prefix + str(x) + ":" + str(z) + "/"
			out.append(box(lot + "walk", center + Vector3(0, 0.12, 0), Vector3(26, 0.24, 26), Color("a7a99c"), true, "concrete"))
			var width := 18.0 + floorf(n * 3) * 2
			var depth := 18.0 if style == "oldtown" else 21.0
			var wall_color := colors[0].lightened(0.13 * n)
			var wall_surface := "brick" if style == "oldtown" or (style == "industrial" and n > 0.5) else "metal" if style == "industrial" else "plaster"
			if style == "garden":
				wall_color = Color("c7d1c8").lerp(Color("8cb7ae"), n)
			out.append(box(lot + "wall", center + Vector3(0, height * 0.5, 0), Vector3(width, height, depth), wall_color, true, wall_surface))
			var roof_surface := "tile" if style == "oldtown" else "metal"
			out.append(box(lot + "roof", center + Vector3(0, height + 0.3, 0), Vector3(width + 1, 0.6, depth + 1), colors[1], true, roof_surface))
			if style == "oldtown":
				for tier in 4:
					out.append(box(lot + "ridge" + str(tier), center + Vector3(0, height + 0.7 + tier * 0.55, 0), Vector3(width - tier * 4, 0.55, depth + 1), Color("a56341"), true, "tile"))
				out.append(box(lot + "awning", center + Vector3(0, 3.5, depth * 0.5 + 1.0), Vector3(width * 0.7, 0.25, 2.5), colors[2], false, "paint"))
			elif style == "industrial":
				out.append(box(lot + "vent", center + Vector3(-4, height + 1.1, 2), Vector3(4, 1.6, 3), Color("8a9292"), true, "metal"))
				var stack := box(lot + "stack", center + Vector3(5, height + 4, -4), Vector3(1.6, 8, 1.6), Color("915d45"), true, "brick")
				stack.primitive = "cylinder"
				out.append(stack)
				out.append(box(lot + "door", center + Vector3(0, 2.5, depth * 0.5 + 0.12), Vector3(7, 5, 0.04), Color("657e89"), false, "metal"))
			else:
				out.append(box(lot + "setback", center + Vector3(1, height + 2.5, 1), Vector3(width * 0.6, 4.5, depth * 0.6), colors[1], true, "plaster"))
				_tree(out, lot + "tree", center + Vector3(width * 0.5 + 2, 0.25, depth * 0.5 + 2), 5.0 + n * 2, false)
			for floor_index in range(1, int(height / 4)):
				var y := floor_index * 4.0
				for side: float in [-1, 1]:
					out.append(box(lot + "window_z" + str(floor_index) + str(side), center + Vector3(0, y, side * (depth * 0.5 + 0.12)), Vector3(width - 3, 1.6, 0.04), Color("547a89"), false, "glass"))
					out.append(box(lot + "window_x" + str(floor_index) + str(side), center + Vector3(side * (width * 0.5 + 0.12), y, 0), Vector3(0.04, 1.6, depth - 3), Color("547a89"), false, "glass"))
				if style == "garden":
					out.append(box(lot + "balcony" + str(floor_index), center + Vector3(0, y - 0.95, depth * 0.5 + 0.6), Vector3(width - 2, 0.18, 1.4), Color("c4cec3"), false, "concrete"))
	# One owner per complete bridge. Adjacent chunks' collision halo includes overhangs.
	var bridge_center := base + Vector3(0, 0, 32)
	for side: float in [-1.0, 1.0]:
		out.append(box(prefix + "pillar" + str(side), bridge_center + Vector3(side * 8, 6, 0), Vector3(2, 12, 3), colors[1], true, "concrete"))
	out.append(box(prefix + "bridge", bridge_center + Vector3(0, 12, 0), Vector3(20, 1.5, 5), colors[1], true, "metal"))
	for z in [8, 24, 40, 56]:
		out.append(box(prefix + "road" + str(z), base + Vector3(0, 0.08, z), Vector3(0.25, 0.04, 3), Color("e2d3a1"), false, "paint"))
	return out

func _canyon(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if key.y < -2 or key.y > 4:
		return out
	var origin := Vector3(key.x * 64, 0, key.z * 64)
	for reservation in reservations:
		if Rect2(Vector2(origin.x, origin.z), Vector2(64, 64)).intersects(Rect2(Vector2(reservation.position.x, reservation.position.z), Vector2(reservation.size.x, reservation.size.z))):
			return out
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var surfaces := PackedInt32Array()
	var minimum := INF
	var maximum := -INF
	for z in 17:
		for x in 17:
			var wx := origin.x + x * 4
			var wz := origin.z + z * 4
			var height := _terrain_height(wx, wz, seed_value)
			var normal := _terrain_normal(wx, wz, seed_value)
			vertices.append(Vector3(wx, height, wz))
			normals.append(normal)
			var color := Color("6a8c4d") if kind == "forest" else Color("bb9162")
			if kind == "forest":
				color = color.lerp(Color("959385"), 1.0 - smoothstep(0.65, 0.95, normal.y))
			elif height < -5:
				color = color.lerp(Color("8f8b7f"), smoothstep(-5, -12, height))
			colors.append(color.lightened((noise_at(int(wx), int(wz), seed_value) - 0.5) * 0.08))
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)
	var owner := floori(minimum / SIZE)
	if key.y != owner:
		return out
	for z in 16:
		for x in 16:
			var a := z * 17 + x
			indices.append_array(PackedInt32Array([a, a + 1, a + 17, a + 1, a + 18, a + 17]))
			for triangle in 2:
				var slope := (normals[a].y + normals[a + 18].y) * 0.5
				surfaces.append(1 if slope < 0.8 else 2 if vertices[a].y < -5 else 0)
	out.append({"id": biome.id + "/terrain/" + str(key.x) + "/" + str(key.z), "primitive": "terrain", "center": origin + Vector3(32, (minimum + maximum) * 0.5, 32), "size": Vector3(64, maxf(0.1, maximum - minimum), 64), "solid": true, "color": Color.WHITE, "vertices": vertices, "normals": normals, "colors": colors, "indices": indices, "surfaces": surfaces, "surface_names": ["grass" if kind == "forest" else "sandstone", "sandstone", "gravel"]})
	if kind == "forest":
		for x in [10, 30, 50]:
			for z in [10, 30, 50]:
				var wx: float = origin.x + x + (noise_at(key.x * 3 + x, key.z * 3 + z, seed_value) - 0.5) * 14
				var wz: float = origin.z + z + (noise_at(key.x * 3 + x, key.z * 3 + z, seed_value + 1) - 0.5) * 14
				var reserved := false
				for clearing: Vector3 in biome.parameters.get("clearings", []):
					reserved = reserved or Vector2(wx - clearing.x, wz - clearing.z).length() < 18
				if reserved:
					continue
				var height := _terrain_height(wx, wz, seed_value)
				if noise_at(int(wx), int(wz), seed_value + 9) < 0.22:
					out.append(box(biome.id + "/stone/" + str(wx) + "/" + str(wz), Vector3(wx, height + 0.7, wz), Vector3(2.2, 1.4, 1.8), Color("93978b"), true, "sandstone"))
					continue
				_tree(out, biome.id + "/pine/" + str(wx) + "/" + str(wz), Vector3(wx, height, wz), 9 + noise_at(int(wx), int(wz), seed_value) * 8, true)
	return out

func _terrain_height(x: float, z: float, seed_value: int) -> float:
	return TerrainSampler.sample(x, z, seed_value, city_regions)

func _terrain_normal(x: float, z: float, seed_value: int) -> Vector3:
	return TerrainSampler.normal_at(x, z, seed_value, city_regions)

func _tree(out: Array[Dictionary], id: String, point: Vector3, height: float, pine: bool) -> void:
	var trunk := box(id + "/trunk", point + Vector3(0, height * 0.35, 0), Vector3(0.65, height * 0.7, 0.65), Color("64513f"), true, "bark")
	trunk.primitive = "cylinder"
	out.append(trunk)
	for tier in (3 if pine else 2):
		var crown := box(id + "/crown" + str(tier), point + Vector3(0, height * (0.48 + tier * 0.2), 0), Vector3(height * (0.7 - tier * 0.14), height * 0.45, height * (0.7 - tier * 0.14)), (Color("3e6d4e") if pine else Color("6f915e")).lightened((height - 9.0) * 0.008), false, "foliage")
		crown.primitive = "cone"
		out.append(crown)

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
	for index in out.size():
		out[index].surface = ["sandstone", "sandstone", "sandstone", "plaster", "metal", "landing"][index]
	out.append(box(biome.id + "/meadow", Vector3(112, 114.015, -80), Vector3(72, 0.02, 64), Color("91aa6f"), false, "grass"))
	out.append(box(biome.id + "/station_glass", Vector3(130, 124, -86.96), Vector3(11, 3, 0.08), Color("4f8a9e"), false, "glass"))
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
	for object in out:
		object.surface = "screen" if "/light" in object.id else "metal" if "/deck" in object.id else "concrete"
	return _translate(out, anchor - Vector3(-96, -24, -96))

func _translate(objects: Array[Dictionary], offset: Vector3) -> Array[Dictionary]:
	for object: Dictionary in objects:
		object.center += offset
	return objects
