class_name MissionChallengeView
extends Node3D
## Physical props are streamed; this bounded layer shows live balloons and targets.
var controller: MissionController
var actors: Dictionary = {}
var signature := ""
var effects := MissionPopEffects.new()
const ENTRY_COLORS := {"available": Color("164b46ef"), "active": Color("72501bef"), "completed": Color("35465eef"), "failed": Color("743e3aef")}
const ENTRY_RANGE := 70.0

func _ready() -> void:
	add_child(effects)

func update_at(point: Vector3, origin: Vector3, labels_visible: bool, delta: float = 0, paused: bool = false) -> void:
	if controller == null:
		return
	effects.update_at(origin, delta, paused)
	var local := controller.local_definitions(point)
	var key := controller.store.path + ":" + str(controller.store.data.seed)
	for mission in local:
		var state: Dictionary = controller.store.data.assignments.get(mission.id, {})
		key += mission.id + str(state.get("status", "available")) + str(state.get("started", false)) + str(state.get("stage", 0)) + str(state.get("hits", []))
	key += controller.store.data.tracked_mission
	if key != signature:
		signature = key
		for child in get_children():
			if child == effects:
				continue
			remove_child(child)
			child.queue_free()
		actors.clear()
		for mission in local:
			_build(mission)
	var camera := get_viewport().get_camera_3d()
	for actor: Dictionary in actors.values():
		var mission: MissionDefinition = actor.mission
		var anchor := mission.acceptance_point()
		actor.root.position = anchor - origin
		if actor.has("guide"): actor.guide.visible = labels_visible
		_update_entry(actor, point, origin, camera, labels_visible)
		for child in actor.root.get_children():
			if child is Label3D:
				child.visible = labels_visible
		var elapsed := float(controller.challenge_state(mission).get("elapsed", 0))
		if controller.store.mission_status(mission.id) != "active":
			continue
		if mission.kind == "balloons":
			for index in actor.balloons:
				actor.balloons[index].position = FlightChallengeRules.balloon_point(mission, index, elapsed) - anchor
				actor.balloons[index].visible = controller.challenge_state(mission).get("started", false) and FlightChallengeRules.balloon_released(mission, index, elapsed)
		elif mission.kind == "follow":
			actor.target.position = FlightChallengeRules.follow_point(mission, elapsed) - anchor
			var direction := FlightChallengeRules.follow_point(mission, elapsed + 0.05) - FlightChallengeRules.follow_point(mission, elapsed)
			if direction.length_squared() > 0.0001:
				actor.target.basis = Basis.looking_at(direction, Vector3.UP)

func set_labels_visible(value: bool) -> void:
	for actor: Dictionary in actors.values():
		if not value:
			actor.entry.visible = false
		if actor.has("guide"): actor.guide.visible = value
		for child in actor.root.get_children():
			if child is Label3D:
				child.visible = value

func _build(mission: MissionDefinition) -> void:
	var root := Node3D.new()
	add_child(root)
	var tracked: bool = controller.store.data.tracked_mission == mission.id
	var status := controller.store.mission_status(mission.id)
	var entry := Node3D.new()
	entry.position = Vector3.UP * 3.0
	root.add_child(entry)
	var status_text: String = {"available": "未接取 · 停稳按 E 接取", "active": "已接取 · 正在追踪" if tracked else "已接取 · 可在地图追踪", "completed": "已完成 · 停稳按 E 重玩", "failed": "气球超高 · 停稳按 E 重试"}[status]
	if status == "active" and mission.kind == "balloons" and not controller.challenge_state(mission).get("started", false):
		status_text = "已接取 · 停稳按 E 开始放球"
	var label := Label3D.new()
	label.text = mission.display_name.get_slice(" · ", 0).left(14) + "\n" + status_text
	label.font_size = 32
	label.pixel_size = 0.014
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.render_priority = 2
	label.visibility_range_end = ENTRY_RANGE
	entry.add_child(label)
	var background := QuadMesh.new()
	background.size = Vector2(7.8, 1.8)
	var board := _mesh(entry, background, ENTRY_COLORS[status])
	board.visibility_range_end = ENTRY_RANGE
	var material := board.material_override as StandardMaterial3D
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.render_priority = 1
	var actor := {"mission": mission, "root": root, "entry": entry, "balloons": {}}
	if status == "active" and not mission.legacy_objects.is_empty():
		var objects: Array[Dictionary] = []
		for object: Dictionary in mission.legacy_objects:
			var local_object := object.duplicate()
			local_object.center -= mission.acceptance_point()
			objects.append(local_object)
		root.add_child(WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": objects}, Vector3.ZERO))
	if status in ["completed", "failed"]:
		actors[mission.id] = actor
		return
	if mission.kind == "balloons" and status == "active":
		var state: Dictionary = controller.store.data.assignments.get(mission.id, {})
		var colors := [Color("ec8177"), Color("f1c967"), Color("7dd9be"), Color("80b8ed"), Color("c7a1e7")]
		for index in mission.checkpoints.size():
			if state.get("hits", []).has(index):
				continue
			var balloon := Node3D.new()
			root.add_child(balloon)
			var sphere := SphereMesh.new()
			sphere.radius = 1.15
			sphere.height = 2.3
			_mesh(balloon, sphere, colors[index % colors.size()])
			_box(balloon, Vector3(0, -1.7, 0), Vector3(0.035, 1.8, 0.035), Color("bcbfa6"))
			actor.balloons[index] = balloon
	elif mission.kind in ["orbit", "follow"]:
		var target := Node3D.new()
		root.add_child(target)
		target.position = mission.target_point - mission.acceptance_point()
		var sphere := SphereMesh.new()
		sphere.radius = 1.1
		sphere.height = 2.2
		_mesh(target, sphere, Color("efb968"))
		if mission.kind == "follow":
			_box(target, Vector3.ZERO, Vector3(4, 0.18, 0.8), Color("63c9d8"))
			_box(target, Vector3(0, 0, 0.8), Vector3(1.2, 0.2, 2), Color("dbeced"))
		else:
			_box(target, Vector3.ZERO, Vector3(0.18, 3.2, 0.18), Color("d4e7ed"))
			if tracked:
				var guide := ImmediateMesh.new()
				guide.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
				var radius := (float(mission.challenge.radius_min) + float(mission.challenge.radius_max)) * 0.5
				for index in 65:
					guide.surface_add_vertex(Vector3(cos(index * TAU / 64) * radius, 0, sin(index * TAU / 64) * radius))
				guide.surface_end()
				_mesh(target, guide, Color("70b9c4"))
		actor.target = target
	elif mission.kind == "regional" and status == "active":
		var stage := int(controller.challenge_state(mission).get("stage", 0))
		for index in mission.checkpoints.size():
			var number := Label3D.new()
			var glyphs := ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ"]
			var title: String = glyphs[index % glyphs.size()] if mission.challenge.mode == "sequence" else str(index + 1)
			number.text = title + (" · 已激活" if index < stage else " · 当前目标" if index == stage else "")
			number.text += "\n靠近按住 E" if index == stage and mission.challenge.mode != "clean" else ""
			number.position = mission.checkpoints[index] - mission.acceptance_point() + Vector3.UP * 3
			number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			number.font_size = 40
			number.pixel_size = 0.016
			number.visibility_range_end = 230
			number.modulate = Color("7de0ac") if index < stage else Color("ffe090") if index == stage else Color("9eb9c8")
			root.add_child(number)
			if mission.challenge.mode == "clean":
				var ring := TorusMesh.new()
				ring.inner_radius = 3.5
				ring.outer_radius = 3.65
				var marker := _mesh(root, ring, number.modulate)
				marker.position = mission.checkpoints[index] - mission.acceptance_point()
				var normal := (mission.checkpoints[index] - mission.checkpoints[maxi(0, index - 1)]).normalized() if index > 0 else Vector3.UP
				marker.basis = Basis(Quaternion(Vector3.UP, normal))
	elif mission.kind == "race" and tracked:
		var stage := int(controller.store.data.assignments[mission.id].get("stage", 0))
		var guide := RaceRouteGuide.new()
		root.add_child(guide)
		guide.configure(mission, stage)
		actor.guide = guide
		var half := float(mission.challenge.get("gate_half", 3.4))
		for index in mission.checkpoints.size():
			var number := Label3D.new()
			number.text = ("起点 " if index == 0 else "终点 " if index == mission.checkpoints.size() - 1 else "") + str(index + 1)
			number.position = mission.checkpoints[index] - mission.acceptance_point() + FlightChallengeRules.gate_basis_for(mission, index).y * (half + 0.7)
			number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			number.font_size = 32
			number.pixel_size = 0.014
			number.visibility_range_end = 180
			number.modulate = Color("7de0ac") if index < stage else Color("ffe090") if index == stage else Color("9eb9c8")
			root.add_child(number)
			if index == stage:
				var gate := Node3D.new()
				gate.name = "CurrentGate"
				gate.position = mission.checkpoints[index] - mission.acceptance_point()
				gate.basis = FlightChallengeRules.gate_basis_for(mission, index)
				root.add_child(gate)
				var line := half + 0.05
				for side: float in [-1, 1]:
					_box(gate, Vector3(side * line, 0, 0), Vector3(0.10, line * 2, 0.10), Color("ffe090"))
					_box(gate, Vector3(0, side * line, 0), Vector3(line * 2, 0.10, 0.10), Color("ffe090"))
				var arrow := CylinderMesh.new()
				arrow.top_radius = 0
				arrow.bottom_radius = 0.32
				arrow.height = 1.2
				var indicator := _mesh(root, arrow, Color("ffe090"))
				indicator.position = mission.checkpoints[index] - mission.acceptance_point() + mission.gate_normals[index] * 1.2
				indicator.basis = Basis(Quaternion(Vector3.UP, mission.gate_normals[index]))
	actors[mission.id] = actor

func _update_entry(actor: Dictionary, point: Vector3, origin: Vector3, camera: Camera3D, labels_visible: bool) -> void:
	var mission: MissionDefinition = actor.mission
	var nearest := mission.acceptance_point()
	for pickup: Vector3 in mission.pickup_points:
		if point.distance_squared_to(pickup) < point.distance_squared_to(nearest):
			nearest = pickup
	var target := nearest + Vector3.UP * 3 - origin
	actor.entry.visible = labels_visible and camera != null and point.distance_to(nearest) <= ENTRY_RANGE and not camera.is_position_behind(target)
	if not actor.entry.visible:
		return

func _mesh(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, color).position = point
