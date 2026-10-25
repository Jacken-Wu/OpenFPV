extends SceneTree

var failed := 0
var scene: Node3D

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var catalog := ContentCatalog.new()
	var generator := WorldGenerator.new(catalog, 271828, 2)
	check(WorldGenerator.key_at(Vector3(-0.01, -64.01, 64)) == Vector3i(-1, -2, 1), "3D floor keys support negative coordinates")
	var keys: Array[Vector3i] = [Vector3i(-2, -1, -2), Vector3i(1, 1, -2), Vector3i(-1, 0, -1), Vector3i(0, 0, 0), Vector3i(5, -1, 0)]
	var hashes: Dictionary = {}
	for key in keys:
		hashes[key] = generator.semantic_hash(key)
	keys.reverse()
	for key in keys:
		check(hashes[key] == generator.semantic_hash(key), "loading order does not affect " + str(key))
	var alternative := WorldGenerator.new(catalog, 314159, 2)
	check(generator.semantic_hash(Vector3i(-2, 0, 0)) != alternative.semantic_hash(Vector3i(-2, 0, 0)), "seed changes generated city structure")
	check(generator.biome_at(Vector3(-0.1, 0, 0)).id != generator.biome_at(Vector3(0.1, 0, 0)).id, "city style changes across defined region boundary")
	var tile := generator.generate(Vector3i(-2, -1, -2))
	var ids: Array[String] = []
	for object: Dictionary in tile.objects:
		ids.append(object.id)
	check(not str(ids).contains("/ground"), "surface generation reserves underground entrance")
	var sky := generator.generate(Vector3i(1, 1, -2))
	check(sky.objects.size() >= 6, "sky volume produces closed 3D geometry")
	scene = Node3D.new()
	root.add_child(scene)
	scene.add_child(WorldGeometry.create_chunk(tile, Vector3.ZERO))
	scene.add_child(WorldGeometry.create_chunk(sky, Vector3.ZERO))
	for frame in 3:
		await physics_frame
	check(not _ray(Vector3(100, 140, -68), Vector3(100, 100, -68)).is_empty(), "sky top and landing pad collide")
	check(not _ray(Vector3(60, 109, -80), Vector3(120, 109, -80)).is_empty(), "sky side collides")
	check(not _ray(Vector3(112, 75, -80), Vector3(112, 115, -80)).is_empty(), "sky underside collides across vertical chunk boundary")
	check(_ray(Vector3(-96, 10, -96), Vector3(-96, -47, -96)).is_empty(), "underground shaft remains open from surface to chamber")
	check(not _ray(Vector3(-96, -40, -96), Vector3(-96, -52, -96)).is_empty(), "underground floor collides")
	var streamer := WorldStreamer.new()
	streamer.generator = generator
	scene.add_child(streamer)
	streamer.focus = Vector3(0, 1, 16)
	check(not streamer.collision_ready(streamer.focus), "flight waits for collision halo before loading")
	for frame in 1000:
		await process_frame
		if streamer.collision_ready(streamer.focus):
			break
	check(streamer.collision_ready(streamer.focus), "background generation commits ready collision halo")
	var original_key := WorldGenerator.key_at(Vector3(1100, 25, -64))
	var original_hash := generator.semantic_hash(original_key)
	var velocity := Vector3(20, -5, 10)
	var orientation := Basis.from_euler(Vector3(0.2, 1.2, -0.4))
	var body := RigidBody3D.new()
	body.freeze = true
	body.transform = Transform3D(orientation, Vector3(1100, 25, -64))
	body.linear_velocity = velocity
	scene.add_child(body)
	var shift := Vector3(1024, 0, -64)
	streamer.shift_origin(shift)
	body.position -= shift
	check(WorldGenerator.key_at(body.position + streamer.origin_offset) == original_key and generator.semantic_hash(original_key) == original_hash and body.basis.is_equal_approx(orientation) and body.linear_velocity == velocity, "origin shift preserves world key, semantic geometry, attitude and velocity")
	streamer.focus = Vector3(640, 180, 640)
	await process_frame
	await process_frame
	check(not streamer.collision_ready(streamer.focus), "teleport cannot reuse unrelated collision readiness")
	scene.queue_free()
	await process_frame
	print("WORLD_RESULT failures=", failed)
	quit(1 if failed else 0)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
