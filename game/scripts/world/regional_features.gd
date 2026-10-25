class_name RegionalFeatures
extends RefCounted
## Connected, seeded region-scale architecture and fly-through geology.
static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	if plan.kind != "surface":
		return
	var profile: String = plan.biomes[0].parameters.get("feature_profile", "")
	if profile.is_empty():
		return
	if profile == "megastructure":
		# Supersede isolated towers after historical course definitions are built.
		# Their saved IDs/waypoints remain resolvable, with the same clear corridors.
		plan.objects = plan.objects.filter(func(object: Dictionary): return "/landmark/mega_ruins" not in object.id and "/landmark_base/mega_ruins" not in object.id)
		plan.landmarks = plan.landmarks.filter(func(landmark: Dictionary): return landmark.kind != "mega_ruins")
	var anchor: Vector2 = field.surface_site(plan.key).anchor
	var sampler := BiomeTerrain.new(field, anchor, entrances)
	var rng := field.rng_for(plan.key, 53003)
	var protected: Array[Dictionary] = []
	for entrance: Dictionary in entrances:
		protected.append({"a": entrance.bottom, "b": entrance.top + Vector3.UP * 14, "radius": 18.0})
	for station: Dictionary in plan.stations:
		protected.append({"a": station.point - Vector3.UP * 2, "b": station.point + Vector3.UP * 12, "radius": 10.0})
	for task: MissionDefinition in plan.missions + plan.legacy_missions:
		protected.append({"a": task.acceptance_point() - Vector3.UP * 1.2, "b": task.acceptance_point() + Vector3.UP * 7, "radius": 7.0})
		for point: Vector3 in task.checkpoints + PackedVector3Array([task.target_point]):
			protected.append({"a": point - Vector3.UP * 2, "b": point + Vector3.UP * 5, "radius": 5.0})
		if task.kind == "balloons":
			for point: Vector3 in task.checkpoints:
				protected.append({"a": point, "b": Vector3(point.x, float(task.challenge.height_limit), point.z), "radius": 4.0})
		if task.kind == "race" or (task.kind == "regional" and task.challenge.mode == "clean"):
			for index in range(1, task.checkpoints.size()):
				protected.append({"a": task.checkpoints[index - 1], "b": task.checkpoints[index], "radius": 5.0})
	var added: Array[Dictionary] = []
	match profile:
		"ruined_grid":
			for x in range(-6, 7):
				for z in range(-6, 7):
					if rng.randf() < 0.20:
						continue
					var p := anchor + Vector2(x, z) * 38
					if field.nearest(p).id != plan.id:
						continue
					var point := Vector3(p.x, sampler.sample(p.x, p.y) + 1.5, p.y)
					var id: String = plan.id + "/ruined_block/%d/%d" % [x, z]
					var height := rng.randi_range(2, 7) * 8.0
					for side: float in [-1, 1]:
						for edge: float in [-1, 1]:
							Architecture.add(added, id, "post%s%s" % [side, edge], point + Vector3(side * 11, height / 2, edge * 11), Vector3(1.4, height, 1.4), Color("7c8785"), "concrete")
					for floor_index in int(height / 8):
						var y := floor_index * 8.0
						for side: float in [-1, 1]:
							if rng.randf() > 0.2:
								Architecture.add(added, id, "floor%d%s" % [floor_index, side], point + Vector3(side * 8, y, 0), Vector3(7, 0.65, 24), Color("9c9f92"), "concrete")
							if rng.randf() > 0.4:
								Architecture.add(added, id, "wall%d%s" % [floor_index, side], point + Vector3(0, y + 2, side * 11), Vector3(19, 3.6, 0.8), Color("999585"), "brick")
		"honeycomb_rocks":
			var count := 0
			for attempt in 220:
				if count >= 26:
					break
				var p := anchor + Vector2(rng.randf_range(-290, 290), rng.randf_range(-290, 290))
				if field.nearest(p).id != plan.id:
					continue
				var point := Vector3(p.x, sampler.sample(p.x, p.y), p.y)
				var clear := true
				for volume in protected:
					clear = clear and Geometry3D.get_closest_point_to_segment(point + Vector3.UP * 16, volume.a, volume.b).distance_to(point + Vector3.UP * 16) > 32 + float(volume.radius)
				for rock: Dictionary in added:
					clear = clear and Vector2(point.x - rock.center.x, point.z - rock.center.z).length() > 39
				if not clear:
					continue
				var rock := FeatureGeometry.rock(plan.id + "/hollow_rock%d" % count, point, rng.randi())
				added.append(rock)
				plan.landmarks.append({"id": rock.id, "kind": "hollow_rock", "name": "风蚀蜂窝岩", "point": point, "marker": rock.center, "size": rock.size, "radius": rock.size.length() / 2, "map_visible": false})
				count += 1
		"megastructure":
			var base := float(plan.get("megabase", RegionalSites.megabase(plan, sampler, anchor)))
			var cells := {}
			for x in range(-5, 6):
				for z in range(-5, 6):
					if field.nearest(anchor + Vector2(x, z) * 52).id == plan.id:
						cells[Vector2i(x, z)] = true
			var connected := {Vector2i.ZERO: true}
			var frontier: Array[Vector2i] = [Vector2i.ZERO]
			while not frontier.is_empty():
				var cell := frontier.pop_back() as Vector2i
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
					if cells.has(cell + d) and not connected.has(cell + d):
						connected[cell + d] = true
						frontier.append(cell + d)
			for cell: Vector2i in connected:
				var point := Vector3(anchor.x + cell.x * 52, base, anchor.y + cell.y * 52)
				var floors := rng.randi_range(3, 5)
				var id: String = plan.id + "/mega/%d/%d" % [cell.x, cell.y]
				for x: float in [-24, 24]:
					for z: float in [-24, 24]:
						Architecture.add(added, id, "column%s%s" % [x, z], point + Vector3(x, (floors * 40 + 29) / 2.0, z), Vector3(3, floors * 40 + 29, 3), Color("7b8584"), "concrete")
				for floor_index in range(0, floors + 1):
					var y := floor_index * 40 + 28.0
					for side: float in [-1, 1]:
						Architecture.add(added, id, "deckx%d%s" % [floor_index, side], point + Vector3(side * 18.5, y, 0), Vector3(15, 1.6, 52), Color("b2b19d"), "sandstone")
						Architecture.add(added, id, "deckz%d%s" % [floor_index, side], point + Vector3(0, y, side * 18.5), Vector3(22, 1.6, 15), Color("b2b19d"), "sandstone")
						if rng.randf() > 0.4:
							Architecture.add(added, id, "glow%d%s" % [floor_index, side], point + Vector3(side * 25, y + 1.1, 0), Vector3(0.2, 0.3, 40), Color("6aa0a0"), "screen", "box", false)
			plan.mega_cells = connected.keys()
			plan.landmarks.append({"id": plan.id + "/mega_core", "kind": "megastructure", "name": "连片巨构中庭群", "point": Vector3(anchor.x, base, anchor.y), "marker": Vector3(anchor.x, base + 180, anchor.y), "size": Vector3(520, 230, 520), "radius": 260.0})
		"volcanic_causeway":
			for index in 20:
				var angle := index * TAU / 20
				var p := anchor + Vector2.from_angle(angle) * 115
				var height := sampler.sample(p.x, p.y)
				var point := Vector3(p.x, height + 5, p.y)
				var id: String = plan.id + "/crater_bridge%d" % index
				var object := WorldProvider.box(id, point, Vector3(9, 1.2, 39), Color("5d6161"), true, "basalt")
				object.rotation = Vector3(0, -angle, 0)
				added.append(object)
				Architecture.add(added, id, "vent", point + Vector3(8, 6, 0), Vector3(5, 12, 5), Color("4a4c50"), "basalt", "cylinder")
				Architecture.add(added, id, "glow", point + Vector3(8, 12.2, 0), Vector3(3, 0.3, 3), Color("d57943"), "lava", "cylinder", false)
	var accepted := 0
	for object in added:
		var blocked := false
		var transform := Transform3D(Basis.from_euler(object.get("rotation", Vector3.ZERO)), object.center)
		var box := (transform * AABB(-object.size / 2, object.size)).grow(1)
		if object.get("primitive", "") == "terrain":
			# Entire rock bodies have already passed footprint reservations.
			plan.objects.append(object)
			accepted += 1
			continue
		for volume in protected:
			var grown := box.grow(float(volume.radius))
			if grown.has_point(volume.a) or grown.has_point(volume.b) or grown.intersects_segment(volume.a, volume.b) != null:
				blocked = true
				break
		if not blocked:
			plan.objects.append(object)
			accepted += 1
	plan.feature_objects = accepted
