class_name RaceRouteGuide
extends Node3D
## World-space guidance only; it never contributes collision or gate progress.
var segments: Array[Dictionary] = []
var arrow_count := 0

func configure(mission: MissionDefinition, stage: int) -> void:
	var anchor := mission.acceptance_point()
	for index in range(stage, mission.checkpoints.size()):
		var b := mission.checkpoints[index] - anchor
		var a := mission.checkpoints[index - 1] - anchor if index > 0 else b - mission.gate_normals[0] * 14
		var direction := (b - a).normalized()
		var distance := a.distance_to(b)
		if distance < 0.01: continue
		segments.append({"gate": index, "from": a, "to": b})
		var color := Color("ffe090") if index == stage else Color("65c5dc")
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tube := CylinderMesh.new()
		tube.top_radius = 0.065
		tube.bottom_radius = 0.065
		tube.height = distance
		tube.radial_segments = 6
		tube.material = material
		var line := MeshInstance3D.new()
		line.mesh = tube
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.position = (a + b) * 0.5
		line.basis = Basis(Quaternion(Vector3.UP, direction))
		add_child(line)
		if arrow_count >= 256: continue
		var right := direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT).normalized()
		var up := right.cross(direction).normalized()
		var arrows := ImmediateMesh.new()
		arrows.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		var count := maxi(1, ceili(distance / 12))
		for step in count:
			if arrow_count >= 256: break
			var center := a.lerp(b, (step + 0.5) / count)
			# Crossed fins remain legible from above, the side and in vertical shafts.
			for side: Vector3 in [right, up]:
				arrows.surface_add_vertex(center + direction * 1.25)
				arrows.surface_add_vertex(center - direction * 0.5 + side * 0.6)
				arrows.surface_add_vertex(center - direction * 0.5 - side * 0.6)
			arrow_count += 1
		arrows.surface_end()
		var indicators := MeshInstance3D.new()
		indicators.mesh = arrows
		indicators.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(indicators)
