class_name FeatureGeometry
extends RefCounted
## Compound feature meshes keep visual openings and physical faces identical.
static func mesh(id: String, surface: String = "sandstone") -> Dictionary:
	return {"id": id, "primitive": "terrain", "unmerged": true, "solid": true, "center": Vector3.ZERO, "size": Vector3.ONE, "color": Color.WHITE, "vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "indices": PackedInt32Array(), "surfaces": PackedInt32Array(), "surface_names": [surface]}

static func quad(out: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var offset: int = out.vertices.size()
	out.vertices.append_array(PackedVector3Array([a, b, c, d]))
	for index in 4:
		out.normals.append(normal)
		out.colors.append(color)
	var clockwise := (b - a).cross(c - a).dot(normal) < 0
	out.indices.append_array(PackedInt32Array([offset, offset + 1, offset + 2, offset, offset + 2, offset + 3]) if clockwise else PackedInt32Array([offset, offset + 2, offset + 1, offset, offset + 3, offset + 2]))
	out.surfaces.append_array(PackedInt32Array([0, 0]))

static func bounds(out: Dictionary) -> Dictionary:
	var box := AABB(out.vertices[0], Vector3.ZERO)
	for point: Vector3 in out.vertices:
		box = box.expand(point)
	out.center = box.get_center()
	out.size = box.size
	return out

static func triangle(out: Dictionary, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	var offset: int = out.vertices.size()
	out.vertices.append_array(PackedVector3Array([a, b, c]))
	for index in 3:
		out.normals.append(normal)
		out.colors.append(color)
	out.indices.append_array(PackedInt32Array([offset, offset + 1, offset + 2]) if (b - a).cross(c - a).dot(normal) < 0 else PackedInt32Array([offset, offset + 2, offset + 1]))
	out.surfaces.append(0)

static func rock(id: String, center: Vector3, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var nx := rng.randi_range(6, 9)
	var ny := rng.randi_range(5, 9)
	var nz := rng.randi_range(5, 8)
	var unit := 4.0
	var solid := {}
	var width := Vector3(nx, ny, nz) * unit
	var bottom := center - Vector3(width.x / 2, 0, width.z / 2)
	var bore := rng.randf_range(3.5, 5.0)
	for x in nx:
		for y in ny:
			for z in nz:
				var p := (Vector3(x, y, z) + Vector3.ONE * 0.5) * unit - width * 0.5
				var q := p / (width * 0.5)
				var outer := q.length_squared() < 1.0 + WorldProvider.noise_at(x * 17 + y, z, seed_value) * 0.25
				var hollow := Vector2(p.y, p.z).length() < bore or Vector2(p.y, p.x).length() < bore or Vector2(p.x, p.z).length() < bore * 0.9
				if outer and not hollow:
					solid[Vector3i(x, y, z)] = true
	var out := mesh(id)
	var axes: Array[Vector3i] = [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]
	for cell: Vector3i in solid:
		var p := bottom + Vector3(cell) * unit
		for axis in axes:
			if solid.has(cell + axis):
				continue
			var normal := Vector3(axis)
			var u := Vector3.UP if axis.x != 0 else Vector3.RIGHT
			var v := normal.cross(u)
			var face := p + Vector3.ONE * (unit * 0.5) + normal * (unit * 0.5)
			var color := Color("a9987f").lerp(Color("ccb58e"), float(cell.y) / ny)
			quad(out, face - (u + v) * unit / 2, face + (u - v) * unit / 2, face + (u + v) * unit / 2, face + (v - u) * unit / 2, normal, color)
	return bounds(out)

static func tunnel(id: String, a: Vector3, b: Vector3, radius: float, volcanic: bool = false, sampler: BiomeTerrain = null, heights: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var axis := (b - a).normalized()
	var right := axis.cross(Vector3.UP).normalized()
	var up := right.cross(axis).normalized()
	var count := ceili(a.distance_to(b) / 4)
	for index in count:
		var part := mesh(id + "/section%d" % index, "basalt" if volcanic else "sandstone")
		for side in 16:
			var t0 := side * TAU / 16
			var t1 := (side + 1) * TAU / 16
			var p := right * cos(t0) + up * sin(t0)
			var q := right * cos(t1) + up * sin(t1)
			var start := a.lerp(b, float(index) / count)
			var end := a.lerp(b, float(index + 1) / count)
			var color := Color("64707b") if volcanic else Color("897d6b")
			var polygon: Array[Vector3] = [start + p * radius, end + p * radius, end + q * radius, start + q * radius]
			var fragments: Array = [polygon] if sampler == null else ground_fragments(polygon, sampler, heights)
			for fragment: Array in fragments:
				for index_triangle in range(1, fragment.size() - 1):
					triangle(part, fragment[0], fragment[index_triangle], fragment[index_triangle + 1], -(p + q).normalized(), color.lightened((side % 3) * 0.04))
		if not part.vertices.is_empty(): out.append(bounds(part))
	return out

static func ground_fragments(polygon: Array[Vector3], sampler: BiomeTerrain, heights: Dictionary) -> Array:
	# Match the actual four-metre terrain triangles, including their diagonal.
	# Sampling a smooth height only at a face's endpoints leaves metre-sized
	# cracks on steep slopes. Two centimetres of overlap cover float roundoff.
	var bounds := AABB(polygon[0], Vector3.ZERO)
	for point in polygon: bounds = bounds.expand(point)
	var first := Vector2i(floori(bounds.position.x / 4), floori(bounds.position.z / 4))
	var last := Vector2i(floori(bounds.end.x / 4), floori(bounds.end.z / 4))
	var result: Array = []
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var cell: Array = polygon.duplicate()
			for plane: Plane in [Plane(Vector3.LEFT, -x * 4), Plane(Vector3.RIGHT, (x + 1) * 4), Plane(Vector3.FORWARD, -z * 4), Plane(Vector3.BACK, (z + 1) * 4)]:
				cell = CavePassages.split_polygon(cell, plane).inside
				if cell.size() < 3: break
			if cell.size() < 3: continue
			var corners: Array[Vector3] = []
			for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i(0, 1), Vector2i.ONE]:
				var key := Vector2i(x, z) + offset
				if not heights.has(key): heights[key] = sampler.sample(key.x * 4, key.y * 4)
				corners.append(Vector3(key.x * 4, heights[key], key.y * 4))
			var diagonal := Plane(Vector3(1, 0, 1).normalized(), (x * 4 + z * 4 + 4) / sqrt(2.0))
			var halves := CavePassages.split_polygon(cell, diagonal)
			for half in 2:
				var fragment: Array = halves.inside if half == 0 else halves.outside
				if fragment.size() < 3: continue
				var a := corners[0] if half == 0 else corners[1]
				var b := corners[1] if half == 0 else corners[3]
				var c := corners[2]
				var normal := (c - a).cross(b - a).normalized()
				fragment = CavePassages.split_polygon(fragment, Plane(normal, normal.dot(a) + 0.02)).inside
				if fragment.size() >= 3: result.append(fragment)
	return result
