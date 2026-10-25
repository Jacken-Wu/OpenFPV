class_name RegionalWorldProvider
extends WorldProvider
## v3 additions leave the v2 provider's deterministic output intact.

func _terrain_height(x: float, z: float, seed_value: int) -> float:
	return RegionalTerrainSampler.sample(x, z, seed_value, city_regions)

func _terrain_normal(x: float, z: float, seed_value: int) -> Vector3:
	return RegionalTerrainSampler.normal_at(x, z, seed_value, city_regions)

func _sky(key: Vector3i, biome: BiomeDefinition) -> Array[Dictionary]:
	var out := super._sky(key, biome)
	if out.is_empty():
		return out
	var anchor: Vector3 = biome.parameters.anchor
	var variant := int(biome.parameters.get("layout_variant", 0))
	var center := anchor + Vector3(18, 10, 14)
	out.append(box(biome.id + "/annex", center, Vector3(14, 8 + variant * 3, 12), Color("afbfba"), true, "plaster"))
	out.append(box(biome.id + "/annex_glass", center + Vector3(0, 1, 6.04), Vector3(12, 4, 0.08), Color("5c97a5"), false, "glass"))
	if variant == 0:
		out.append(box(biome.id + "/gallery", anchor + Vector3(18, 12, 0), Vector3(5, 0.5, 20), Color("9caba7"), true, "metal"))
	elif variant == 1:
		for tier in 3:
			out.append(box(biome.id + "/roof_step" + str(tier), center + Vector3(0, 6.5 + tier, 0), Vector3(13 - tier * 3, 1, 11 - tier * 2), Color("85a67a"), true, "grass"))
	else:
		var dome := box(biome.id + "/observatory", center + Vector3(0, 11, 0), Vector3(9, 6, 9), Color("6b9fa6"), true, "glass")
		dome.primitive = "cylinder"
		out.append(dome)
	return out

func _underground(key: Vector3i, biome: BiomeDefinition) -> Array[Dictionary]:
	var out := super._underground(key, biome)
	if out.is_empty():
		return out
	var anchor: Vector3 = biome.parameters.anchor
	var variant := int(biome.parameters.get("layout_variant", 0))
	for side: float in [-1, 1]:
		out.append(box(biome.id + "/gantry_post" + str(side), anchor + Vector3(21, -12, side * 22), Vector3(2, 24, 2), Color("899a96"), true, "metal"))
	out.append(box(biome.id + "/gantry", anchor + Vector3(21, 0, 0), Vector3(5, 0.7, 46), Color("b39565"), true, "metal"))
	var machine := box(biome.id + "/machine", anchor + Vector3(23, -18, 0), Vector3(8, 12, 12 + variant * 4), Color("547f80"), true, "metal")
	machine.primitive = "cylinder" if variant == 1 else "box"
	out.append(machine)
	out.append(box(biome.id + "/machine_panel", anchor + Vector3(18.95, -15, 0), Vector3(0.08, 3, 6), Color("8ad6c4"), false, "screen"))
	return out

func _city(key: Vector3i, seed_value: int, biome: BiomeDefinition, reservations: Array[AABB]) -> Array[Dictionary]:
	var out := super._city(key, seed_value, biome, reservations)
	var additions: Array[Dictionary] = []
	for object: Dictionary in out:
		if not object.id.ends_with("/wall"):
			continue
		var center: Vector3 = object.center
		var roof_y: float = center.y + object.size.y * 0.5
		var n := noise_at(int(center.x), int(center.z), seed_value + 103)
		var prefix: String = object.id.trim_suffix("wall")
		if n > 0.82 and biome.parameters.get("expanded_props", false):
			additions.append_array(Architecture.build("tri_billboard" if n > 0.91 else "pipe_stack", prefix + "roof_open", Vector3(center.x, roof_y, center.z), n))
		elif n < 0.25:
			# A narrow rooftop tower changes the skyline without occupying roads.
			additions.append(box(prefix + "tower", Vector3(center.x, roof_y + 5, center.z), Vector3(8, 10, 8), object.color, true, object.surface))
			additions.append(box(prefix + "tower_glass", Vector3(center.x, roof_y + 6, center.z + 4.12), Vector3(6, 4, 0.04), Color("6a9caa"), false, "glass"))
		elif n < 0.5:
			var tank := box(prefix + "water_tank", Vector3(center.x, roof_y + 3, center.z), Vector3(7, 5, 7), Color("8c999a"), true, "metal")
			tank.primitive = "cylinder"
			additions.append(tank)
		elif n < 0.75:
			for step in 3:
				additions.append(box(prefix + "terrace" + str(step), Vector3(center.x, roof_y + step * 2.5 + 1.5, center.z - step * 1.3), Vector3(14 - step * 4, 2.5, 12 - step * 3), Color("b3c6b2"), true, "plaster"))
		else:
			additions.append(box(prefix + "skylight", Vector3(center.x, roof_y + 1.7, center.z), Vector3(12, 2.5, 10), Color("588b9b"), true, "glass"))
			for side: float in [-1, 1]:
				additions.append(box(prefix + "canopy" + str(side), Vector3(center.x, 3.0, center.z + side * (object.size.z * 0.5 + 1.0)), Vector3(object.size.x, 0.3, 2), Color("ccae78"), false, "tile"))
	out.append_array(additions)
	return out
