extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/entrance"

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1

func meshes_at(generator: WorldGenerator, point: Vector3) -> Array[Dictionary]:
	var key := WorldGenerator.key_at(point)
	var meshes: Array[Dictionary] = []
	for y in [-1, 0]:
		for object: Dictionary in generator.generate(Vector3i(key.x, y, key.z)).objects:
			if object.get("primitive", "") == "terrain" and "/terrain/" in object.id:
				meshes.append(object)
	return meshes

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.trim_prefix("--capture-dir=")
	var catalog := ContentCatalog.new()
	var scenes: Array[Node3D] = []
	var city_entry: Dictionary = {}
	var saved_generator: WorldGenerator
	var city_count := 0
	var natural_count := 0
	# Different seeds and signed world locations cover flat city and natural slopes.
	for seed_value in [271828, 42, 8675309]:
		var generator := WorldGenerator.new(catalog, seed_value)
		var world: BiomeWorld = generator.regions
		var entries_tested := 0
		for x in range(-2, 3):
			for z in range(-2, 3):
				var plan := world.plan("maze", Vector2i(x, z))
				if plan.is_empty():
					continue
				for entry: Dictionary in plan.shape.entries:
					var p: Vector3 = entry.top
					var city: bool = world.field.nearest(Vector2(p.x, p.z)).biome.provider_id == "base.generator.modular_city"
					var meshes := meshes_at(generator, p)
					check(meshes.size() == 1, "one surface mesh over maze entrance seed%d at%s" % [seed_value, p])
					if meshes.size() == 1:
						var object := meshes[0]
						var area := 0.0
						var hole_filled := false
						for index in object.indices.size() / 3:
							var a: Vector3 = object.vertices[object.indices[index * 3]]
							var b: Vector3 = object.vertices[object.indices[index * 3 + 1]]
							var c: Vector3 = object.vertices[object.indices[index * 3 + 2]]
							area += absf((b - a).cross(c - a).y) * 0.5
							var center := (a + b + c) / 3
							hole_filled = hole_filled or entry.hole.has_point(Vector2(center.x, center.z))
						# At most three 16m holes can overlap one chunk.
						check(area >= 4096 - 3 * 256 and not hole_filled, "ground retains full area except shaft openings seed%d" % seed_value)
					if city:
						city_count += 1
						if city_entry.is_empty():
							city_entry = entry
							saved_generator = generator
					else:
						natural_count += 1
					entries_tested += 1
				if entries_tested >= 6:
					break
			if entries_tested >= 6:
				break
	check(city_count > 0 and natural_count > 0, "regression covers city and natural entrances across seeds and negative coordinates")
	if not city_entry.is_empty():
		var scene := Node3D.new()
		root.add_child(scene)
		scenes.append(scene)
		var p: Vector3 = city_entry.top
		var base := WorldGenerator.key_at(p)
		for x in range(base.x - 1, base.x + 2):
			for z in range(base.z - 1, base.z + 2):
				for y in range(-3, 2):
					scene.add_child(WorldGeometry.create_chunk(saved_generator.generate(Vector3i(x, y, z)), Vector3.ZERO))
		for frame in 4:
			await physics_frame
		var space := scene.get_world_3d().direct_space_state
		check(space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3, city_entry.bottom)).is_empty(), "actual surface mesh leaves shaft flight path physically open")
		var supported := true
		for offset: Vector3 in [Vector3(12, 0, 0), Vector3(-12, 0, 0), Vector3(0, 0, 12), Vector3(0, 0, -12), Vector3(24, 0, 24), Vector3(-24, 0, -24)]:
			var at := p + offset
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 4, at - Vector3.UP * 8))
			supported = supported and not hit.is_empty()
		check(supported, "ground around all four entrance rims and former missing chunk has physical collision")
		if DisplayServer.get_name() != "headless":
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.position = p + Vector3(50, 65, 60)
			camera.look_at(p)
			camera.current = true
			var light := DirectionalLight3D.new()
			light.rotation_degrees = Vector3(-55, -30, 0)
			scene.add_child(light)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(directory.path_join("city-entrance.png")) == OK, "capture city entrance and restored terrain")
	for scene in scenes:
		scene.queue_free()
	await process_frame
	print("ENTRANCE_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
