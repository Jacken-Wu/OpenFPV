extends SceneTree
var failed := 0
var checked := 0
class FixtureGenerator extends WorldGenerator:
	func _init() -> void: super(ContentCatalog.new(), 271828, 2)
	func generate(key: Vector3i) -> Dictionary:
		var objects: Array[Dictionary] = []
		if key == Vector3i.ZERO:
			for index in 900:
				var object := WorldProvider.box("fixture/%d" % index, Vector3(index % 30, 1, index / 30) * 1.5, Vector3.ONE, Color.WHITE, true)
				if index % 11 == 0:
					object.rotation = Vector3(0.22, 0.6, 0.41)
					object.size = Vector3(1.2, 0.4, 1.6)
				objects.append(object)
		return {"key": key, "objects": objects}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func run() -> void:
	var streamer := WorldStreamer.new()
	streamer.generator = FixtureGenerator.new()
	streamer.radius = 1
	streamer.vertical_radius = 1
	streamer.commit_budget_us = 200
	root.add_child(streamer)
	var partial := false
	for frame in 5000:
		await process_frame
		if not streamer.assembly.is_empty():
			partial = not streamer.active.has(Vector3i.ZERO) and not streamer.collision_ready(Vector3.ZERO) and not streamer.assembly.root.is_inside_tree()
			break
	check(partial, "partly assembled chunk stays outside scene and cannot unlock collision readiness")
	for frame in 5000:
		await process_frame
		if streamer.collision_ready(Vector3.ZERO): break
	check(streamer.collision_ready(Vector3.ZERO), "complete collider halo eventually publishes")
	await physics_frame
	await physics_frame
	var hit := streamer.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 8, 0), Vector3(0, 0, 0)))
	check(not hit.is_empty(), "published chunk has the actual complete fixture collisions")
	var bounds_ok := true
	if DisplayServer.get_name() == "headless":
		# Dummy RenderingServer does not retain MultiMesh transform readback.
		var data := WorldGeometry.prepare_chunk(streamer.generator.generate(Vector3i.ZERO))
		for bucket: Dictionary in data.buckets:
			for transform: Transform3D in bucket.transforms:
				bounds_ok = bounds_ok and bucket.bounds.grow(0.05).encloses(transform * AABB(Vector3.ONE * -0.5, Vector3.ONE))
	else:
		for child in streamer.active[Vector3i.ZERO].get_children():
			if not child is MultiMeshInstance3D: continue
			for index in child.multimesh.instance_count:
				var actual: AABB = child.multimesh.get_instance_transform(index) * child.multimesh.mesh.get_aabb()
				bounds_ok = bounds_ok and child.multimesh.custom_aabb.encloses(actual)
	check(bounds_ok, "explicit immutable batch bounds enclose every scaled instance")
	var old: Node3D = streamer.active[Vector3i.ZERO]
	streamer.focus = Vector3(4096, 0, 4096)
	await process_frame
	await process_frame
	check(not is_instance_valid(old) or (not old.visible and old.get_child(0).collision_layer == 0), "retired chunk disappears and disables collisions immediately")
	for retired in streamer.retired:
		check(not retired.visible and retired.get_child(0).collision_layer == 0, "retired terrain is immediately hidden and cannot leave ghost collisions")
	for frame in 300:
		await process_frame
		if streamer.collision_ready(streamer.focus) and streamer.retired.is_empty(): break
	check(streamer.collision_ready(streamer.focus) and streamer.retired.is_empty(), "old chunks retire gradually and new location cannot reuse their readiness")
	streamer.replace_generator(FixtureGenerator.new())
	check(streamer.active.is_empty() and streamer.assembly.is_empty() and streamer.pending.is_empty(), "world replacement drains workers and unpublished scene nodes")
	streamer.focus = Vector3.ZERO
	for frame in 5000:
		await process_frame
		if not streamer.assembly.is_empty(): break
	var abandoned: Node3D = streamer.assembly.root
	streamer.focus = Vector3(8192, 0, 8192)
	await process_frame
	await process_frame
	check(not is_instance_valid(abandoned) and not streamer.active.has(Vector3i.ZERO), "moving away cancels incomplete geometry without publishing a stale chunk")
	streamer.queue_free()
	await process_frame
	var geometry := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": [WorldProvider.box("fixture/ground", Vector3.ZERO, Vector3(64, 0.25, 64), Color.GRAY, true, "asphalt"), WorldProvider.box("fixture/tower", Vector3(40, 40, 40), Vector3(12, 80, 12), Color.GRAY, true, "concrete")]}, Vector3.ZERO)
	root.add_child(geometry)
	var floor_ok := false
	var tower_ok := false
	for child in geometry.get_children():
		if child is MultiMeshInstance3D:
			if child.multimesh.mesh.material == WorldMaterials.material_for(Color.GRAY, "asphalt"):
				floor_ok = child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			else:
				tower_ok = child.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and child.multimesh.mesh.subdivide_height == 2
	check(floor_ok and tower_ok, "flat road stops casting self-shadow while large building keeps subdivided casting faces")
	await physics_frame
	await physics_frame
	check(not geometry.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(12, 8, 12), Vector3(12, -3, 12))).is_empty(), "shadow stability changes preserve actual solid ground")
	geometry.queue_free()
	await process_frame
	var catalog := ContentCatalog.new()
	var world := BiomeWorld.new(catalog, 271828)
	var plan := world.plan("surface", Vector2i.ZERO)
	var task: MissionDefinition = plan.missions[0]
	world.plans.clear()
	var summary := world.instance(plan.id)
	check(not summary.has("chunks") and not summary.has("shape") and summary.missions.size() == plan.missions.size(), "metadata cache survives geometry eviction without retaining chunk meshes")
	check(world.mission(task.id).checkpoints == task.checkpoints and catalog.fingerprint() == ContentCatalog.new().fingerprint(), "metadata lookup preserves objective identity and immutable content")
	print("STREAMING_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
