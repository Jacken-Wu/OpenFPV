class_name BiomeSurfaceProvider
extends RegionalWorldProvider
var sampler: BiomeTerrain
var field: BiomeField
var shafts: Array[Dictionary]
var caves: Array[Dictionary] = []

func _init(provider_kind: String, biome_field: BiomeField, point: Vector2, entrances: Array[Dictionary]) -> void:
	super(provider_kind)
	field = biome_field
	shafts = entrances
	sampler = BiomeTerrain.new(field, point, entrances)

func _terrain_height(x: float, z: float, _seed_value: int) -> float:
	return sampler.sample(x, z)

func _terrain_normal(x: float, z: float, _seed_value: int) -> Vector3:
	return sampler.normal_at(x, z)

func _city(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	biome.parameters.expanded_props = field.expanded_at(Vector2(key.x * 64 + 32, key.z * 64 + 32))
	var out := super._city(key, seed_value, biome, reservations)
	var removed: Dictionary = {}
	var replacements: Array[Dictionary] = []
	for object: Dictionary in out:
		if not object.id.ends_with("/wall"):
			continue
		if field.nearest(Vector2(object.center.x, object.center.z)).biome.provider_id != "base.generator.modular_city":
			removed[object.id.trim_suffix("wall")] = true
		var footprint := Rect2(Vector2(object.center.x - object.size.x * 0.5, object.center.z - object.size.z * 0.5), Vector2(object.size.x, object.size.z))
		for clearing: Vector3 in biome.parameters.clearings:
			if footprint.intersects(Rect2(Vector2(clearing.x - 9, clearing.z - 9), Vector2(18, 18))):
				removed[object.id.trim_suffix("wall")] = true
		for shaft in shafts:
			if footprint.intersects(shaft.hole.grow(3)):
				removed[object.id.trim_suffix("wall")] = true
		for reserved: Rect2 in biome.parameters.get("landmark_reservations", []):
			if footprint.intersects(reserved):
				removed[object.id.trim_suffix("wall")] = true
		# Empty lots and plazas occur independently of services.
		if noise_at(int(object.center.x), int(object.center.z), seed_value + 9323) < 0.13:
			removed[object.id.trim_suffix("wall")] = true
		var prefix: String = object.id.trim_suffix("wall")
		var choice := noise_at(int(object.center.x), int(object.center.z), seed_value + 19103)
		var template: BiomeDefinition = field.nearest(Vector2(object.center.x, object.center.z)).biome
		var pool: Array = template.parameters.get("lot_pool", [])
		if not field.expanded_at(Vector2(object.center.x, object.center.z)):
			pool = pool.filter(func(value: String): return value not in ["open_house", "playground", "pipe_stack", "billboard", "tri_billboard"])
		if not removed.has(prefix) and not pool.is_empty() and choice < 0.48:
			removed[prefix] = true
			var kind: String = pool[mini(pool.size() - 1, int(choice / 0.48 * pool.size()))]
			replacements.append_array(Architecture.build(kind, prefix + "special/" + kind, Vector3(object.center.x, 0.25, object.center.z), noise_at(int(object.center.x), int(object.center.z), seed_value + 19121)))
	var result: Array[Dictionary] = []
	for object in out:
		var skip := false
		if ("/pillar" in object.id or object.id.ends_with("/bridge")) and noise_at(key.x, key.z, seed_value + 19301) > 0.22:
			skip = true
		for prefix: String in removed:
			skip = skip or object.id.begins_with(prefix)
		for shaft in shafts:
			var footprint := Rect2(Vector2(object.center.x - object.size.x * 0.5, object.center.z - object.size.z * 0.5), Vector2(object.size.x, object.size.z))
			if not object.id.ends_with("/ground") and footprint.intersects(shaft.hole):
				skip = true
		if not skip:
			result.append(object)
	if key.y in [-1, 0] and not shafts.is_empty():
		# Replace the monolithic asphalt slab near an entrance with a mesh that
		# uses the same clipped opening as natural terrain.
		for shaft in shafts:
			if Rect2(Vector2(key.x * 64, key.z * 64), Vector2(64, 64)).intersects(shaft.hole.grow(34)):
				# Raised terrain belongs to y=0; querying only y=-1 loses the mesh.
				# Remove the slab and emit the mesh at its computed vertical owner.
				result = result.filter(func(object: Dictionary) -> bool: return not object.id.ends_with("/ground"))
				result.append_array(_canyon(key, seed_value, biome, []))
				break
	result.append_array(replacements)
	return result

func _canyon(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	var out := super._canyon(key, seed_value, biome, reservations)
	for object: Dictionary in out:
		if object.get("primitive", "") == "terrain":
			var vertex_types := PackedInt32Array()
			if kind != "city":
				object.surface_names = ["grass", "sandstone", "gravel", "asphalt", "snow", "basalt", "lava"]
				for index in object.vertices.size():
					var point: Vector3 = object.vertices[index]
					var biome_at: BiomeDefinition = field.nearest(Vector2(point.x, point.z), sampler.sites).biome
					var surface := 3 if biome_at.provider_id == "base.generator.modular_city" else 4 if biome_at.tags.has("snow") else 5 if biome_at.tags.has("volcano") else 0 if biome_at.tags.has("forest") else 1
					if biome_at.tags.has("volcano"):
						var site := field.nearest(Vector2(point.x, point.z), sampler.sites)
						if Vector2(point.x, point.z).distance_to(site.anchor) < 45:
							surface = 6
					# Snow rests on shelves; steep rock faces stay exposed as depth cues.
					var slope: float = 1.0 - object.normals[index].y
					if surface == 4 and slope > 0.16:
						surface = 5
					vertex_types.append(surface)
					var low: Color = biome_at.parameters.get("terrain_low", Color("434b50") if surface == 3 else Color("779653") if surface == 0 else Color("bd9569"))
					var high: Color = biome_at.parameters.get("terrain_high", low)
					object.colors[index] = Color("e97236") if surface == 6 else low.lerp(high, clampf(point.y / 160, 0, 1))
					if biome_at.tags.has("snow"):
						var band := 0.5 + 0.5 * sin(point.x * 0.025 + point.z * 0.04 + point.y * 0.12)
						object.colors[index] = Color("354552").lerp(Color("687c8a"), band) if surface == 5 else Color("88a8bd").lerp(Color("d2dedf"), band * 0.65 + 0.2)
			var indices := PackedInt32Array()
			var surfaces := PackedInt32Array()
			for triangle in object.surfaces.size():
				var a: Vector3 = object.vertices[object.indices[triangle * 3]]
				var b: Vector3 = object.vertices[object.indices[triangle * 3 + 1]]
				var c: Vector3 = object.vertices[object.indices[triangle * 3 + 2]]
				var center := (a + b + c) / 3
				var opening := false
				for shaft in shafts:
					opening = opening or shaft.hole.has_point(Vector2(center.x, center.z))
				if not opening:
					var surface: int = object.surfaces[triangle]
					if not vertex_types.is_empty() and (surface == 0 or vertex_types[object.indices[triangle * 3]] >= 4):
						surface = vertex_types[object.indices[triangle * 3]]
					if CavePassages.cuts_triangle(a, b, c, caves):
						CavePassages.append_surface(object, object.indices.slice(triangle * 3, triangle * 3 + 3), CavePassages.surface_fragments(a, b, c, caves), surface, indices, surfaces)
					else:
						indices.append_array(object.indices.slice(triangle * 3, triangle * 3 + 3))
						surfaces.append(surface)
			object.indices = indices
			object.surfaces = surfaces
			if kind == "city":
				object.surface_names = ["asphalt", "concrete", "gravel"]
				object.colors.fill(Color("434b50"))
		elif object.get("surface", "") in ["bark", "foliage", "sandstone"]:
			# Substantial plants and rocks have collisions; keep decorative facade
			# overlays non-solid because their backing already supplies collision.
			object.solid = true
	return out.filter(func(object: Dictionary) -> bool:
		if object.get("primitive", "") != "terrain":
			for reserved: Rect2 in biome.parameters.get("landmark_reservations", []):
				if reserved.has_point(Vector2(object.center.x, object.center.z)):
					return false
		return object.get("surface", "") not in ["bark", "foliage"] or field.nearest(Vector2(object.center.x, object.center.z), sampler.sites).biome.tags.has("forest"))
