extends SceneTree

class LegacyGame:
	extends "res://scripts/main.gd"
	var profile_path := ""
	func _create_progress_store() -> ProgressStore:
		return ProgressStore.new(catalog, profile_path)

var failed := 0
var checked := 0
var test_dir := "user://tests/scenery_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1

func terrain(generator: WorldGenerator, x: int, z: int) -> Dictionary:
	for y in [-1, 0]:
		for object: Dictionary in generator.generate(Vector3i(x, y, z)).objects:
			if object.get("primitive", "") == "terrain":
				return object
	return {}

func write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func capture(name_value: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://../.local/test-results"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join(name_value + ".png")) == OK, "capture " + name_value)

func button_named(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := button_named(child, title)
		if found != null:
			return found
	return null

func click(control: Control) -> void:
	await process_frame
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
	await process_frame
	await process_frame

func run() -> void:
	var catalog := ContentCatalog.new()
	var generator := WorldGenerator.new(catalog, 271828, 2)
	var legacy := WorldGenerator.new(catalog, 271828, 1)
	check(catalog.errors.is_empty() and generator.world_version == 2 and legacy.world_version == 1, "world versions select explicit legacy and detailed providers")
	check(generator.biomes.size() == 7 and legacy.biomes.size() == 5, "new biomes appear only in the new world")
	check(generator.biome_at(Vector3(-64, 1, 320)).id == "base.biome.oldtown" and generator.biome_at(Vector3(640, 70, 0)).id == "base.biome.pine_valley", "oldtown and pine valley are real registered surface biomes")
	var navigation := MapNavigation.new()
	var old_navigation := MapNavigation.new(1)
	check(navigation.locations.size() == 13 and old_navigation.locations.size() == 11 and old_navigation.find_location("teleport.oldtown") == null, "legacy maps do not offer teleports to ungenerated new content")
	var a := terrain(generator, 5, 0)
	var b := terrain(generator, 6, 0)
	check(not a.is_empty() and not b.is_empty(), "continuous terrain exists on both sides of the canyon/forest boundary")
	check(a.vertices.size() == 289 and a.indices.size() == 1536 and a.surfaces.size() == 512, "64m terrain uses a 4m lattice with 512 collision and render triangles")
	var edges_match := true
	for z in 17:
		edges_match = edges_match and a.vertices[z * 17 + 16].is_equal_approx(b.vertices[z * 17]) and a.normals[z * 17 + 16].is_equal_approx(b.normals[z * 17])
	check(edges_match, "adjacent biomes share exact edge positions and smooth normals")
	var negative := terrain(generator, -6, -3)
	var neighbor := terrain(generator, -5, -3)
	edges_match = not negative.is_empty() and not neighbor.is_empty()
	for z in 17:
		edges_match = edges_match and negative.vertices[z * 17 + 16].is_equal_approx(neighbor.vertices[z * 17])
	check(edges_match, "negative-coordinate terrain seams also coincide")
	var original_hash := generator.semantic_hash(Vector3i(5, 0, 0))
	generator.generate(Vector3i(6, 0, 0))
	check(generator.semantic_hash(Vector3i(5, 0, 0)) == original_hash, "loading order cannot change detailed terrain")
	check(terrain(WorldGenerator.new(catalog, 314159, 2), 5, 0).vertices != a.vertices, "different world seed changes smooth terrain")
	var valid_vertices := true
	for vertex: Vector3 in a.vertices:
		valid_vertices = valid_vertices and vertex.is_finite()
	for normal: Vector3 in a.normals:
		valid_vertices = valid_vertices and normal.is_finite() and is_equal_approx(normal.length(), 1.0)
	check(valid_vertices, "terrain points and smooth normals remain finite")
	var provider: WorldProvider = generator.providers["base.generator.canyon"]
	check(is_zero_approx(TerrainSampler.sample(128, 64, 271828, provider.city_regions)) and is_zero_approx(TerrainSampler.sample(-256, 300, 271828, provider.city_regions)), "natural terrain meets both original and new city boundaries at ground level")
	check(legacy.generate(Vector3i(4, -1, 0)).objects.size() > 0 and terrain(legacy, 4, 0).is_empty(), "legacy worlds retain the original column representation")
	var styles: Dictionary = {}
	for point: Vector3 in [Vector3(-128, 0, 64), Vector3(64, 0, 64), Vector3(-64, 0, 320)]:
		var surfaces: Array[String] = []
		var ids: Array[String] = []
		for object: Dictionary in generator.generate(WorldGenerator.key_at(point)).objects:
			surfaces.append(object.get("surface", ""))
			ids.append(object.id)
		styles[point.x if point.z == 64 else 999] = {"surfaces": surfaces, "ids": str(ids)}
	check(styles[-128.0].surfaces.has("metal") and styles[-128.0].ids.contains("stack"), "industrial blocks generate metal bays, rooftop equipment and chimney silhouettes")
	check(styles[64.0].surfaces.has("plaster") and styles[64.0].ids.contains("balcony"), "garden blocks generate plaster, balconies and planted streets")
	check(styles[999].surfaces.has("brick") and styles[999].ids.contains("ridge"), "oldtown generates brick walls and stepped tile roofs")
	var forest := generator.generate(Vector3i(10, 0, 0))
	var trees := 0
	var clearing_valid := true
	for object: Dictionary in forest.objects:
		if object.get("surface", "") == "bark":
			trees += 1
			clearing_valid = clearing_valid and Vector2(object.center.x - 640, object.center.z).length() >= 18
	check(trees > 0 and clearing_valid, "pine forest has solid trunks while retaining portal clearance")
	var materials_distinct := true
	var signatures: Array[String] = []
	for surface: String in ["brick", "concrete", "metal", "glass", "grass", "asphalt", "sandstone"]:
		var material := WorldGeometry.material_for(Color.WHITE, surface)
		var signature := material.albedo_texture.get_image().get_data().hex_encode().sha256_text()
		materials_distinct = materials_distinct and not signatures.has(signature) and material.albedo_texture.get_image().has_mipmaps() and material.albedo_texture.get_width() == 128
		signatures.append(signature)
	check(materials_distinct, "surface families have different native textures with mipmaps")
	check(WorldGeometry.material_for(Color.WHITE, "glass").roughness < WorldGeometry.material_for(Color.WHITE, "concrete").roughness and WorldGeometry.material_for(Color.WHITE, "metal").metallic > 0.5, "glass, concrete and metal have different physical surface responses")
	var stable_uv := true
	for profile: Array in WorldMaterials.PROFILES.values():
		stable_uv = stable_uv and is_equal_approx(float(profile[2]) * 64, roundf(float(profile[2]) * 64))
	check(stable_uv, "world-space texture periods stay aligned during chunk-sized origin shifts")
	var scene := Node3D.new()
	root.add_child(scene)
	var descriptor := {"key": Vector3i(5, floori((a.center.y - a.size.y * 0.5) / 64), 0), "objects": [a]}
	scene.add_child(WorldGeometry.create_chunk(descriptor, Vector3.ZERO))
	for frame in 3:
		await physics_frame
	var vertex: Vector3 = a.vertices[8 * 17 + 8]
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(vertex + Vector3.UP * 20, vertex - Vector3.UP * 20))
	check(not hit.is_empty() and absf(hit.position.y - vertex.y) < 0.01, "real terrain collision coincides with rendered fine-grid vertices")
	var falling_drone := FPVDrone.new()
	scene.add_child(falling_drone)
	falling_drone.position = vertex + Vector3.UP * 3
	for frame in 180:
		await physics_frame
	check(falling_drone.position.is_finite() and falling_drone.position.y > vertex.y - 0.5 and absf(falling_drone.linear_velocity.y) < 2, "the actual drone settles on fine terrain instead of passing through its triangles")
	scene.queue_free()
	await process_frame
	var store := ProgressStore.new(catalog, test_dir.path_join("profile.json"))
	store.complete_relay("world.relay.harbor.01", "maintenance.relay", "industrial")
	store.accept_mission("base.mission.sky_photo")
	var old_data := store.data.duplicate(true)
	old_data.world_version = 1
	old_data.deployment = [240, 42, 0]
	write_json(store.path, old_data)
	var old_store := ProgressStore.new(catalog, store.path)
	check(old_store.writable and old_store.data.world_version == 4 and old_store.data.credits == 0, "authorized old-world reset creates fresh v4 progression")
	check(old_store.data.assignments.is_empty() and old_store.data.tracked_mission.is_empty(), "old authored tasks are not carried into the seed world")
	var restarted := ProgressStore.new(catalog, store.path)
	check(restarted.data.seed == old_store.data.seed and restarted.data.world_version == 4 and restarted.data.credits == 0 and restarted.data.owned == old_store.data.owned and restarted.data.build == old_store.data.build and restarted.data.assignments.is_empty(), "reset profile persists and restarts consistently")
	var game := LegacyGame.new()
	game.profile_path = test_dir.path_join("fresh-v3.json")
	root.add_child(game)
	await game._wait_for_world()
	check(game.generator.world_version == 4 and game.menu == null and game.streamer.collision_ready(game._world_position()), "production starts directly in the seeded world")
	game._show_map()
	await process_frame
	await capture("scenery-map")
	game.queue_free()
	await process_frame
	print("SCENERY_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
