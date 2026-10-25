class_name CavePassages
extends RefCounted

static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	plan.caves = []
	if plan.kind != "surface" or not plan.biomes[0].parameters.get("caves", false):
		return
	var sampler := BiomeTerrain.new(field, Vector2(plan.shape.nodes[0].x, plan.shape.nodes[0].z), entrances)
	var anchor: Vector2 = field.surface_site(plan.key).anchor
	var rng := field.rng_for(plan.key, 51001)
	var volcanic: bool = plan.biomes[0].tags.has("volcano")
	var protected: Array[Vector3] = []
	for station: Dictionary in plan.stations:
		protected.append(station.point)
	for task: MissionDefinition in plan.missions + plan.get("legacy_missions", []):
		protected.append(task.acceptance_point())
		protected.append_array(task.checkpoints)
	for attempt in 480:
		if plan.caves.size() >= 1:
			break
		var point := anchor + Vector2(rng.randf_range(-230, 230), rng.randf_range(-230, 230))
		if field.nearest(point).id != plan.id:
			continue
		var roof := sampler.sample(point.x, point.y)
		var direction := Vector2.from_angle(rng.randf_range(0, TAU))
		var distance := rng.randf_range(65, 110)
		var a := point - direction * distance
		var b := point + direction * distance
		if field.nearest(a).id != plan.id or field.nearest(b).id != plan.id:
			continue
		var end_height := maxf(sampler.sample(a.x, a.y), sampler.sample(b.x, b.y))
		if roof - end_height < 38:
			continue
		var height := roof - 26
		var start := Vector3(a.x, height, a.y)
		var end := Vector3(b.x, height, b.y)
		var clear := true
		for fraction: float in [0.4, 0.45, 0.5, 0.55, 0.6]:
			var core := start.lerp(end, fraction)
			for offset: float in [-10, 0, 10]:
				var side := Vector2(core.x, core.z) + Vector2(-direction.y, direction.x) * offset
				clear = clear and sampler.sample(side.x, side.y) >= height + 10
		for target in protected:
			clear = clear and Geometry3D.get_closest_point_to_segment(target, start, end).distance_to(target) > 18
		for entry: Dictionary in entrances:
			clear = clear and Geometry3D.get_closest_point_to_segment(entry.top, start, end).distance_to(entry.top) > 28
		for cave: Dictionary in plan.caves:
			clear = clear and start.distance_to(cave.a) > 50
		if not clear:
			continue
		start = slope_mouth(start, Vector3(point.x, height, point.y), sampler)
		end = slope_mouth(end, Vector3(point.x, height, point.y), sampler)
		for cave: Dictionary in plan.caves:
			for step in 25:
				var probe := start.lerp(end, float(step) / 24)
				clear = clear and Geometry3D.get_closest_point_to_segment(probe, cave.a, cave.b).distance_to(probe) > 26
		if not clear: continue
		var id: String = plan.id + "/cave%d" % plan.caves.size()
		var radius := rng.randf_range(6, 8)
		for object: Dictionary in plan.objects:
			if not object.get("solid", false) or object.get("primitive", "") == "terrain": continue
			var transform := Transform3D(Basis.from_euler(object.get("rotation", Vector3.ZERO)), object.center)
			var bounds := (transform * AABB(-object.size / 2, object.size)).grow(radius + 2)
			if bounds.has_point(start) or bounds.has_point(end) or bounds.intersects_segment(start, end) != null:
				clear = false
				break
		if not clear: continue
		var network := CaveNetworks.build(id, start, end, radius, sampler, rng, volcanic)
		var valid := true
		for segment: Dictionary in network.segments:
			var segment_axis: Vector3 = (segment.b - segment.a).normalized()
			var segment_a: Vector3 = segment.a - segment_axis * float(segment.get("extension_a", segment.extension))
			var segment_b: Vector3 = segment.b + segment_axis * float(segment.get("extension_b", segment.extension))
			for target in protected:
				valid = valid and Geometry3D.get_closest_point_to_segment(target, segment_a, segment_b).distance_to(target) > float(segment.radius) + 8
			for entry: Dictionary in entrances:
				valid = valid and Geometry3D.get_closest_point_to_segment(entry.top, segment_a, segment_b).distance_to(entry.top) > float(segment.radius) + 22
			for previous: Dictionary in CaveNetworks.flattened(plan.caves):
				for t: float in [0, 0.25, 0.5, 0.75, 1]:
					var probe: Vector3 = segment.a.lerp(segment.b, t)
					valid = valid and Geometry3D.get_closest_point_to_segment(probe, previous.a, previous.b).distance_to(probe) > float(segment.radius) + float(previous.radius) + 6
		if not valid: continue
		plan.caves.append(network)
		plan.objects.append_array(CaveNetworks.geometry(network, sampler))
		var axis := (end - start).normalized()
		for mouth: Vector3 in [start, end]:
			plan.landmarks.append({"id": id + ("/a" if mouth == start else "/b"), "kind": "cave", "name": "熔岩旧管洞口" if volcanic else "山体穿行洞口", "point": mouth, "size": Vector3.ONE * radius * 2, "radius": radius, "marker": mouth})
		if volcanic:
			for step in 8:
				var p := start.lerp(end, (step + 0.5) / 8) + axis.cross(Vector3.UP) * (radius - 0.15)
				plan.objects.append(WorldProvider.box(id + "/glow%d" % step, p, Vector3(0.2, 2, 0.2), Color("dd7d48"), false, "lava"))

static func slope_mouth(outside: Vector3, inside: Vector3, sampler: BiomeTerrain) -> Vector3:
	var low := outside
	var high := inside
	for step in 16:
		var middle := low.lerp(high, 0.5)
		if sampler.sample(middle.x, middle.z) < middle.y: low = middle
		else: high = middle
	return low

static func cuts_triangle(a: Vector3, b: Vector3, c: Vector3, caves: Array[Dictionary]) -> bool:
	for cave in caves:
		var start: Vector3 = cave.a
		var end: Vector3 = cave.b
		var bounds := AABB(start.min(end) - Vector3.ONE * (float(cave.radius) + 6), (end - start).abs() + Vector3.ONE * (float(cave.radius) + 6) * 2)
		var triangle := AABB(a, Vector3.ZERO).expand(b).expand(c).grow(0.01)
		if bounds.intersects(triangle): return true
	return false

static func surface_fragments(a: Vector3, b: Vector3, c: Vector3, caves: Array[Dictionary]) -> Array:
	var fragments: Array = [[a, b, c]]
	for cave in caves:
		if not cuts_triangle(a, b, c, [cave]): continue
		var axis: Vector3 = (cave.b - cave.a).normalized()
		var right := axis.cross(Vector3.UP).normalized()
		var up := right.cross(axis).normalized()
		var planes: Array[Plane] = []
		for side in 16:
			var angle := (side + 0.5) * TAU / 16
			var normal := right * cos(angle) + up * sin(angle)
			planes.append(Plane(normal, normal.dot(cave.a) + float(cave.radius) * cos(PI / 16)))
		var extension: float = cave.get("extension", float(cave.radius) + 2)
		planes.append(Plane(-axis, -axis.dot(cave.a) + float(cave.get("extension_a", extension))))
		planes.append(Plane(axis, axis.dot(cave.b) + float(cave.get("extension_b", extension))))
		var outside: Array = []
		for fragment: Array in fragments:
			var inside: Array = fragment
			for plane in planes:
				if inside.size() < 3: break
				var split := split_polygon(inside, plane)
				if split.outside.size() >= 3: outside.append(split.outside)
				inside = split.inside
		fragments = outside
	return fragments

static func split_polygon(polygon: Array, plane: Plane) -> Dictionary:
	var inside: Array[Vector3] = []
	var outside: Array[Vector3] = []
	for index in polygon.size():
		var a: Vector3 = polygon[index]
		var b: Vector3 = polygon[(index + 1) % polygon.size()]
		var da := plane.distance_to(a)
		var db := plane.distance_to(b)
		if da <= 0: inside.append(a)
		else: outside.append(a)
		if (da <= 0) != (db <= 0):
			var cut := a.lerp(b, da / (da - db))
			inside.append(cut)
			outside.append(cut)
	return {"inside": inside, "outside": outside}

static func append_surface(object: Dictionary, source: PackedInt32Array, fragments: Array, surface: int, indices: PackedInt32Array, surfaces: PackedInt32Array) -> void:
	var a: Vector3 = object.vertices[source[0]]
	var ab: Vector3 = object.vertices[source[1]] - a
	var ac: Vector3 = object.vertices[source[2]] - a
	var denominator := ab.dot(ab) * ac.dot(ac) - ab.dot(ac) * ab.dot(ac)
	for polygon: Array in fragments:
		var offset: int = object.vertices.size()
		for p: Vector3 in polygon:
			var ap := p - a
			var v := (ap.dot(ab) * ac.dot(ac) - ap.dot(ac) * ab.dot(ac)) / denominator
			var w := (ap.dot(ac) * ab.dot(ab) - ap.dot(ab) * ab.dot(ac)) / denominator
			object.vertices.append(p)
			object.normals.append((object.normals[source[0]] * (1 - v - w) + object.normals[source[1]] * v + object.normals[source[2]] * w).normalized())
			object.colors.append(object.colors[source[0]] * (1 - v - w) + object.colors[source[1]] * v + object.colors[source[2]] * w)
		for triangle in range(1, polygon.size() - 1):
			indices.append_array(PackedInt32Array([offset, offset + triangle, offset + triangle + 1]))
			surfaces.append(surface)
