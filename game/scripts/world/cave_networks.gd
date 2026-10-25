class_name CaveNetworks
extends RefCounted
## A watertight union of bent passages, a return loop and a descending side cave.
static func build(id: String, a: Vector3, b: Vector3, radius: float, sampler: BiomeTerrain, rng: RandomNumberGenerator, volcanic: bool) -> Dictionary:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP).normalized()
	var main := PackedVector3Array()
	for index in 9:
		var t := index / 8.0
		main.append(a.lerp(b, t) + side * sin(t * TAU) * sin(t * PI) * 8 + Vector3.UP * (-sin(t * PI) * 5 + sin(t * TAU) * 2))
	var loop := PackedVector3Array([main[2], main[3] + side * 21 - Vector3.UP * 11, main[5] + side * 23 - Vector3.UP * 14, main[6]])
	var spur := PackedVector3Array([main[4], main[4] - side * 16 - Vector3.UP * 10, main[4] - side * 29 - Vector3.UP * 18])
	# Interior rooms remain under a thick roof, including on narrow ridges.
	for path: PackedVector3Array in [main, loop, spur]:
		for index in range(1, path.size() - 1):
			path[index].y = minf(path[index].y, sampler.sample(path[index].x, path[index].z) - 17)
	var volumes: Array[Dictionary] = []
	for path_index in 3:
		var path: PackedVector3Array = [main, loop, spur][path_index]
		for index in path.size() - 1:
			var r := radius * rng.randf_range(0.86, 1.1) if path_index == 0 else rng.randf_range(4.2, 5.6)
			volumes.append({"id": id + "/volume%d" % volumes.size(), "a": path[index], "b": path[index + 1], "radius": r, "extension": 1.2, "open_a": path_index == 0 and index == 0, "open_b": path_index == 0 and index == path.size() - 2})
			if volumes[-1].open_a: volumes[-1].extension_a = r + 2
			if volumes[-1].open_b: volumes[-1].extension_b = r + 2
	# Wider junction chambers provide space to turn and choose a branch.
	for index: int in [2, 4, 6]:
		volumes.append({"id": id + "/room%d" % index, "a": main[index] - axis * 4, "b": main[index] + axis * 4, "radius": radius + 2.2, "extension": 0.5})
	return {"id": id, "a": a, "b": b, "radius": radius, "paths": [main, loop, spur], "segments": volumes, "volcanic": volcanic}

static func geometry(network: Dictionary, sampler: BiomeTerrain) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var segments: Array[Dictionary] = network.segments
	var heights := {}
	for segment in segments:
		var axis: Vector3 = (segment.b - segment.a).normalized()
		var extension: float = segment.extension
		var a: Vector3 = segment.a - axis * float(segment.get("extension_a", extension))
		var b: Vector3 = segment.b + axis * float(segment.get("extension_b", extension))
		var buried := true
		var horizontal := axis.cross(Vector3.UP).normalized()
		for index in 7:
			var center := a.lerp(b, index / 6.0)
			for offset: float in [-1, 0, 1]:
				var probe := center + horizontal * float(segment.radius) * offset
				buried = buried and sampler.sample(probe.x, probe.z) > center.y + float(segment.radius) + 3
		var clipper: BiomeTerrain = null if buried else sampler
		var parts := FeatureGeometry.tunnel(segment.id, a, b, segment.radius, network.volcanic, clipper, heights)
		var cap := FeatureGeometry.mesh(segment.id + "/caps", "basalt" if network.volcanic else "sandstone")
		var right := axis.cross(Vector3.UP).normalized()
		var up := right.cross(axis).normalized()
		for end in 2:
			# Close the buried part of every end, including entrance planes.
			# Only the portion outside the terrain is an open entrance.
			var center := a if end == 0 else b
			for index in 16:
				var p := center + (right * cos(index * TAU / 16) + up * sin(index * TAU / 16)) * float(segment.radius)
				var q := center + (right * cos((index + 1) * TAU / 16) + up * sin((index + 1) * TAU / 16)) * float(segment.radius)
				var polygon: Array[Vector3] = [center, p, q]
				var fragments: Array = [polygon] if buried else FeatureGeometry.ground_fragments(polygon, sampler, heights)
				for fragment: Array in fragments:
					for triangle in range(1, fragment.size() - 1): FeatureGeometry.triangle(cap, fragment[0], fragment[triangle], fragment[triangle + 1], axis if end == 0 else -axis, Color("756e62"))
		if not cap.vertices.is_empty(): parts.append(FeatureGeometry.bounds(cap))
		var others: Array[Dictionary] = []
		for other in segments:
			if other.id != segment.id: others.append(other)
		for part in parts:
			var clipped := part.duplicate(true)
			var indices := PackedInt32Array()
			var surfaces := PackedInt32Array()
			for triangle in part.surfaces.size():
				var source: PackedInt32Array = part.indices.slice(triangle * 3, triangle * 3 + 3)
				var a0: Vector3 = part.vertices[source[0]]
				var b0: Vector3 = part.vertices[source[1]]
				var c0: Vector3 = part.vertices[source[2]]
				if (b0 - a0).cross(c0 - a0).length_squared() < 0.000001: continue
				CavePassages.append_surface(clipped, source, CavePassages.surface_fragments(a0, b0, c0, others), 0, indices, surfaces)
			clipped.indices = indices
			clipped.surfaces = surfaces
			if not indices.is_empty(): result.append(clipped)
	return result

static func flattened(networks: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for network: Dictionary in networks:
		if network.has("segments"): result.append_array(network.segments)
		else: result.append(network)
	return result
