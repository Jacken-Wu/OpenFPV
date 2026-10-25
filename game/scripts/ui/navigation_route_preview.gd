class_name NavigationRoutePreview
extends Node3D
## A short, depth-tested corridor preview. The primary HUD marker stays foremost.
var lines: Array[MeshInstance3D] = []
var markers: Array[Label3D] = []

func _ready() -> void:
	for index in 4:
		var line := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.035 if index == 0 else 0.025
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1
		mesh.radial_segments = 6
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1, 0.85, 0.48, 0.65) if index == 0 else Color(0.4, 0.78, 0.86, 0.5 - index * 0.07)
		mesh.material = material
		line.mesh = mesh
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(line)
		lines.append(line)
		if index == 0: continue
		var marker := Label3D.new()
		marker.font_size = 24
		marker.pixel_size = 0.012
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate = Color(0.55, 0.85, 0.92, 0.6 - index * 0.1)
		marker.no_depth_test = false
		add_child(marker)
		markers.append(marker)

func update_route(nav: MapNavigation, point: Vector3, origin: Vector3, camera: Camera3D, show: bool) -> void:
	visible = show and nav.corridor_route and not nav.arrived and nav.route_index < nav.route.size() - 1
	if not visible: return
	var anchor := nav.waypoint()
	position = anchor - origin
	var used: Array[Vector2] = []
	if is_instance_valid(camera) and not camera.is_position_behind(anchor - origin): used.append(camera.unproject_position(anchor - origin))
	for index in 4:
		var slot := nav.route_index + index
		var active := slot < nav.route.size()
		var a := point if index == 0 else nav.route[slot - 1] if active else anchor
		var b := nav.route[slot] if active else anchor
		var direction := (b - a).normalized()
		if index == 0: a += direction * minf(2, a.distance_to(b) * 0.5)
		var length := a.distance_to(b)
		lines[index].visible = active and length > 0.05 and point.distance_to(b) < 110
		if lines[index].visible:
			lines[index].position = (a + b) * 0.5 - anchor
			lines[index].basis = Basis(Quaternion(Vector3.UP, direction)).scaled_local(Vector3(1, length, 1))
		if index == 0: continue
		var marker := markers[index - 1]
		marker.visible = active and point.distance_to(b) < 90 and is_instance_valid(camera) and not camera.is_position_behind(b - origin)
		if not marker.visible: continue
		var screen := camera.unproject_position(b - origin)
		for previous in used: marker.visible = marker.visible and previous.distance_to(screen) > 36
		if marker.visible:
			used.append(screen)
			marker.text = "· %d" % (slot + 1)
			marker.position = b - anchor + Vector3.UP * 0.45
