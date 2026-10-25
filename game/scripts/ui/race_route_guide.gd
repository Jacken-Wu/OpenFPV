class_name RaceRouteGuide
extends Node3D
## World-space guidance only; it never contributes collision or gate progress.
var segments: Array[Dictionary] = []
var arrow_count := 0

func configure(mission: MissionDefinition, stage: int) -> void:
	var anchor := mission.acceptance_point()
	for index in range(stage, mission.checkpoints.size()):
		var path := section(mission, index)
		var frame_ups := section_ups(mission, index, path)
		for point in path.size(): path[point] -= anchor
		segments.append({"gate": index, "from": path[0], "to": path[-1], "path": path, "ups": frame_ups})
		var color := Color("ffe090") if index == stage else Color("65c5dc")
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tube := ArrayMesh.new()
		var vertices := PackedVector3Array()
		for point in range(1, path.size()): _tube(vertices, path[point - 1], path[point])
		if vertices.is_empty(): continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		tube.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		tube.surface_set_material(0, material)
		var line := MeshInstance3D.new()
		line.mesh = tube
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		if arrow_count >= 256: continue
		var arrows := ImmediateMesh.new()
		arrows.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		var total := 0.0
		for point in range(1, path.size()): total += path[point - 1].distance_to(path[point])
		var spacing := total / maxi(1, ceili(total / 12))
		var next_arrow := spacing * 0.5
		var travelled := 0.0
		for point in range(1, path.size()):
			var a := path[point - 1]
			var b := path[point]
			var direction := (b - a).normalized()
			var up_hint := (frame_ups[point - 1] + frame_ups[point]).normalized()
			var up := FlightChallengeRules.gate_basis(direction, up_hint).y
			var right := direction.cross(up).normalized()
			var distance := a.distance_to(b)
			while next_arrow < travelled + distance and arrow_count < 256:
				var center := a + direction * (next_arrow - travelled)
				for side: Vector3 in [right, up]:
					arrows.surface_add_vertex(center + direction * 1.25)
					arrows.surface_add_vertex(center - direction * 0.5 + side * 0.6)
					arrows.surface_add_vertex(center - direction * 0.5 - side * 0.6)
				arrow_count += 1
				next_arrow += spacing
			travelled += distance
		arrows.surface_end()
		var indicators := MeshInstance3D.new()
		indicators.mesh = arrows
		indicators.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(indicators)

static func section(mission: MissionDefinition, index: int) -> PackedVector3Array:
	var b := mission.checkpoints[index]
	var a := mission.checkpoints[index - 1] if index > 0 else b - mission.gate_normals[0] * 14
	var path: PackedVector3Array = mission.challenge.get("flight_path", PackedVector3Array())
	var indices: PackedInt32Array = mission.challenge.get("gate_path_indices", PackedInt32Array())
	if index > 0 and indices.size() == mission.checkpoints.size() and indices[index] < path.size() and path[indices[index]] == b and path[indices[index - 1]] == a:
		return path.slice(indices[index - 1], indices[index] + 1)
	return PackedVector3Array([a, b])

static func section_ups(mission: MissionDefinition, index: int, path: PackedVector3Array) -> PackedVector3Array:
	var ups: PackedVector3Array = mission.challenge.get("flight_ups", PackedVector3Array())
	var indices: PackedInt32Array = mission.challenge.get("gate_path_indices", PackedInt32Array())
	if index > 0 and indices.size() == mission.checkpoints.size() and ups.size() == mission.challenge.get("flight_path", PackedVector3Array()).size() and path.size() == indices[index] - indices[index - 1] + 1:
		return ups.slice(indices[index - 1], indices[index] + 1)
	var result := PackedVector3Array()
	for point in path.size(): result.append(FlightChallengeRules.gate_basis_for(mission, index).y)
	return result

static func _tube(vertices: PackedVector3Array, a: Vector3, b: Vector3) -> void:
	var direction := (b - a).normalized()
	if direction.is_zero_approx(): return
	var right := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized() * 0.065
	var up := right.normalized().cross(direction) * 0.065
	for face in 6:
		var theta := TAU * face / 6
		var next := TAU * (face + 1) / 6
		var p := right * cos(theta) + up * sin(theta)
		var q := right * cos(next) + up * sin(next)
		vertices.append_array(PackedVector3Array([a + p, b + p, a + q, a + q, b + p, b + q]))
