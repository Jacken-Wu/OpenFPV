extends SceneTree

var failed := 0
var checked := 0
var directory := "user://tests/biomes4_" + str(Time.get_ticks_usec())

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", title)
	if not value:
		failed += 1

func capture(title: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var folder := "res://../.local/test-results/biomes4"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			folder = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder.path_join(title + ".png")) == OK, "capture " + title)

func example(layout: BiomeWorld, kind: String) -> Dictionary:
	for radius in range(0, 5):
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var p := layout.plan(kind, Vector2i(x, z))
				if not p.is_empty():
					return p
	return {}

func flood(data: Dictionary) -> Dictionary:
	var found: Dictionary = {0: true}
	var queue: Array[int] = [0]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for direction in 4:
			if data.doors[cell] & (1 << direction):
				var d: Vector2i = BiomeStructures.DIRECTIONS[direction]
				var next: int = cell + d.x + d.y * int(data.width)
				if not found.has(next):
					found[next] = true
					queue.append(next)
	return found

func dock(game: Node3D, station: Dictionary) -> void:
	game._close_menu()
	game._deploy(station.point)
	await game._wait_for_world()
	game._set_paused(false)
	await create_timer(1).timeout
	game._set_paused(true)

func run() -> void:
	var catalog := ContentCatalog.new()
	var before := catalog.fingerprint()
	var layout := BiomeWorld.new(catalog, 271828)
	var generator := WorldGenerator.new(catalog, 271828)
	check(catalog.errors.is_empty() and generator.world_version == 4, "world4 registers independent biome generation")
	var types: Dictionary = {}
	var counts: Dictionary = {}
	var offsets: Dictionary = {}
	var shapes: Dictionary = {}
	var coverage := true
	var irregular := false
	var reconstruction := true
	var kinds: Dictionary = {}
	var instance_plans: Array[Dictionary] = []
	for x in range(-4, 4):
		for z in range(-4, 4):
			var plan := layout.plan("surface", Vector2i(x, z))
			instance_plans.append(plan)
			var biome: BiomeDefinition = plan.biomes[0]
			types[biome.id.split(":")[0]] = true
			counts[plan.missions.size()] = true
			var polygon: PackedVector2Array = biome.parameters.map_polygon
			for index in polygon.size():
				var delta := polygon[(index + 1) % polygon.size()] - polygon[index]
				irregular = irregular or (absf(delta.x) > 1 and absf(delta.y) > 1)
			for station: Dictionary in plan.stations:
				offsets[Vector2(station.point.x, station.point.z).posmod(512)] = true
			coverage = coverage and plan.stations.size() >= 1 and plan.missions.size() >= 1
			for mission: MissionDefinition in plan.missions:
				kinds[mission.kind] = mission
				var again := layout.mission(mission.id)
				reconstruction = reconstruction and again != null and again.target_point == mission.target_point and again.checkpoints == mission.checkpoints
			for legacy: MissionDefinition in plan.get("legacy_missions", []):
				kinds[legacy.kind] = legacy
	check(types.size() >= 5 and irregular, "climate and outer expansion produce varied non-rectangular surface biomes")
	check(coverage and counts.size() >= 3 and offsets.size() > 20, "platform and task counts/positions vary independently of 512m map pages")
	check(reconstruction and kinds.has_all(["hold_interact", "photo", "survey", "courier", "circuit", "race", "balloons", "orbit", "follow"]), "procedural mission IDs reconstruct targets and stages deterministically")
	var independent := BiomeWorld.new(catalog, 271828)
	var initial: Dictionary = instance_plans[0]
	var cold := independent.plan("surface", initial.key)
	var cold_same: bool = cold.missions.size() == initial.missions.size()
	for index in cold.missions.size():
		cold_same = cold_same and cold.missions[index].checkpoints == initial.missions[index].checkpoints and cold.missions[index].target_point == initial.missions[index].target_point
	check(cold_same, "cold reconstruction after cache eviction cannot inherit another mission's arrays")
	var seams := true
	for x in [-9, -1, 0, 7, 19]:
		var a := BiomeTerrain.new(layout.field, Vector2(x * 64 + 32, 32))
		var b := BiomeTerrain.new(layout.field, Vector2(x * 64 + 96, 32))
		for z in 17:
			seams = seams and is_equal_approx(a.sample(x * 64 + 64, z * 4), b.sample(x * 64 + 64, z * 4)) and a.normal_at(x * 64 + 64, z * 4).is_equal_approx(b.normal_at(x * 64 + 64, z * 4))
	check(seams, "independent chunk contexts share exact terrain edges and normals")
	var signatures: Dictionary = {}
	for x in range(-4, 4):
		for z in range(-4, 4):
			var area := Rect2(Vector2(x, z) * 512, Vector2.ONE * 512)
			var sky := not layout.field.volume_sites("sky", area).is_empty()
			var maze := not layout.field.volume_sites("maze", area).is_empty()
			signatures[str(sky) + "/" + str(maze)] = true
	check(signatures.size() >= 3 and signatures.has("false/false"), "sky and underground distributions are sparse and independent, without repeated triplets")
	var sky := example(layout, "sky")
	var maze := example(layout, "maze")
	check(not sky.is_empty() and sky.shape.islands.size() >= 4 and sky.biomes[0].region_bounds.size.x > 250, "sky biomes form large multi-island clusters")
	var min_y := INF
	var max_y := -INF
	for island: Dictionary in sky.shape.islands:
		min_y = minf(min_y, island.point.y)
		max_y = maxf(max_y, island.point.y)
	check(max_y - min_y > 15, "cluster islands have meaningful altitude variation")
	var connected := true
	var maze_hashes: Dictionary = {}
	var maze_count := 0
	for x in range(-3, 4):
		for z in range(-3, 4):
			var plan := layout.plan("maze", Vector2i(x, z))
			if plan.is_empty():
				continue
			maze_count += 1
			var data: Dictionary = plan.shape.maze
			connected = connected and flood(data).size() == data.doors.size() and data.width >= 13 and plan.biomes[0].region_bounds.size.x > 200
			maze_hashes[hash(data.doors)] = true
	check(connected and maze_count >= 5 and maze_hashes.size() == maze_count, "large mazes have distinct layouts and every cell is reachable")
	var alternative := BiomeWorld.new(catalog, 314159)
	check(hash(alternative.plan("surface", Vector2i.ZERO).missions[0].target_point) != hash(layout.plan("surface", Vector2i.ZERO).missions[0].target_point), "a different seed changes structure placement")
	var keys: Array[Vector3i] = [WorldGenerator.key_at(layout.spawn_point()), WorldGenerator.key_at(sky.stations[0].point), WorldGenerator.key_at(maze.stations[0].point), Vector3i(-121, 0, 97)]
	for key in keys:
		var original := generator.semantic_hash(key)
		generator.generate(key + Vector3i(1, 0, 1))
		check(generator.semantic_hash(key) == original, "chunk output is independent of load order " + str(key))
	var cache_valid := layout.plans.size() <= 48 and layout.field.site_cache.size() <= 256
	check(cache_valid and catalog.fingerprint() == before, "bounded caches leave shared content definitions unchanged")
	var sky_scene := Node3D.new()
	root.add_child(sky_scene)
	for key: Vector3i in sky.chunks:
		sky_scene.add_child(WorldGeometry.create_chunk({"key": key, "objects": sky.chunks[key]}, Vector3.ZERO))
	for frame in 3:
		await physics_frame
	var space_sky := sky_scene.get_world_3d().direct_space_state
	var island: Dictionary = sky.shape.islands[0]
	var p: Vector3 = island.point
	check(not space_sky.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 25, p - Vector3.UP * 5)).is_empty(), "island upper surfaces have real collision")
	check(not space_sky.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(float(island.radius) + 20, -float(island.depth) * 0.25, 0), p + Vector3(float(island.radius) * 0.5, -float(island.depth) * 0.25, 0))).is_empty(), "island tapered sides have real collision")
	check(not space_sky.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(1, -float(island.depth) - 15, 1), p + Vector3(1, 5, 1))).is_empty(), "island undersides are closed physical surfaces")
	sky_scene.queue_free()
	await process_frame
	# Construct an entire maze from the production chunk descriptors and check rays.
	var scene := Node3D.new()
	root.add_child(scene)
	for key: Vector3i in maze.chunks:
		scene.add_child(WorldGeometry.create_chunk({"key": key, "objects": maze.chunks[key]}, Vector3.ZERO))
	for frame in 3:
		await physics_frame
	var space := scene.get_world_3d().direct_space_state
	var data: Dictionary = maze.shape.maze
	var open_clear := true
	var wall_solid := true
	var open_count := 0
	var closed_count := 0
	var clearance_shape := BoxShape3D.new()
	clearance_shape.size = Vector3.ONE * 0.6
	for cell in mini(data.doors.size(), 70):
		var a := BiomeStructures.cell_point(data, cell) + Vector3.UP * BiomeStructures.NAV_HEIGHT
		for direction in 4:
			var d: Vector2i = BiomeStructures.DIRECTIONS[direction]
			var b := a + Vector3(d.x, 0, d.y) * 16
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b))
			if data.doors[cell] & (1 << direction):
				open_count += 1
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = clearance_shape
				query.transform.origin = a
				query.motion = b - a
				open_clear = open_clear and hit.is_empty() and space.cast_motion(query)[0] > 0.99
			else:
				closed_count += 1
				wall_solid = wall_solid and not hit.is_empty()
	check(open_clear and open_count > 0, "actual maze corridor collisions agree with graph openings")
	check(wall_solid and closed_count > 0, "actual closed maze walls stop physics rays")
	var base := BiomeStructures.cell_point(data, 0)
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(base + Vector3.UP * 5, base - Vector3.UP * 2)).is_empty(), "maze floors have physical collision")
	var entry: Dictionary = maze.shape.entries[0]
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(entry.top + Vector3.UP * 3, entry.bottom)).is_empty(), "entrance shaft remains physically open from surface into the maze")
	var location: MapLocation = maze.locations[0].duplicate()
	var start := BiomeStructures.cell_point(data, data.doors.size() - 1) + Vector3.UP * BiomeStructures.NAV_HEIGHT
	var path := layout.route(start, location)
	var path_clear := true
	var previous := start
	for index in path.size():
		# The last segment descends onto the destination platform.
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(previous, path[index])) if previous.distance_to(path[index]) > 0.01 else {}
		path_clear = path_clear and hit.is_empty()
		previous = path[index]
	check(path.size() > 3 and path_clear, "maze navigation follows traversable corridors rather than crossing walls")
	scene.queue_free()
	await process_frame
	# Progression uses regenerated definitions and the existing atomic transactions.
	var store := ProgressStore.new(catalog, directory.path_join("progress.json"))
	var mission: MissionDefinition = kinds.circuit
	check(store.accept_mission(mission.id).ok and not store.complete_mission(mission.id).ok, "ordered missions cannot reward before checkpoints")
	store.advance_mission(mission.id, mission.checkpoints[0], 0, false)
	var restart := ProgressStore.new(catalog, store.path)
	check(restart.data.assignments[mission.id].stage == 1, "regenerated mission stage survives restart")
	store.writable = false
	check(not store.advance_mission(mission.id, mission.checkpoints[1], 0, false).ok and store.data.assignments[mission.id].stage == 1, "failed stage writes cannot expose progress")
	store.writable = true
	for index in range(1, mission.checkpoints.size()):
		store.advance_mission(mission.id, mission.checkpoints[index], 0, false)
	store.complete_mission(mission.id)
	store.complete_mission(mission.id)
	check(store.data.credits == 30, "stable generated transactions issue exactly one reward")
	var navigation := MapNavigation.new(4)
	var exploration := WorldExploration.new(store, navigation)
	var bounded := true
	for index in 12:
		exploration.refresh(Vector2i(index * 9, -index * 13))
		bounded = bounded and navigation.locations.size() < 200 and exploration.definitions.size() < 130
	check(bounded, "distant map pages keep a bounded set of unique biome instances")
	var game := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(game)
	await game._wait_for_world()
	game._show_workshop()
	check(game.menu == null, "hovering above a platform cannot open equipment")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	game._unhandled_key_input(tab)
	check(game.menu == null, "Tab cannot bypass physical docking")
	var plans := [layout.plan("surface", layout.field.nearest(Vector2.ZERO).key), sky, maze]
	for plan: Dictionary in plans:
		var station: Dictionary = plan.stations[0]
		await dock(game, station)
		check(not game._docked_station().is_empty(), "actual landing at independent biome platform " + plan.kind)
		game._perform_action("interact")
		check(game.menu is Workshop, "shared service interaction works in " + plan.kind)
		await capture("service-" + plan.kind)
		if game.menu is Workshop:
			var workshop: Workshop = game.menu
			var saved: Dictionary = game.store.data.duplicate(true)
			game.drone.position += Vector3.UP * 4
			workshop.apply_requested.emit(game.store.data.build, FlightTuning.defaults())
			check(game.store.data == saved, "service save revalidates docking after opening")
		game._close_menu()
	# Actual beacon body collision, using current generated production content.
	var beacon_hit := false
	for plan: Dictionary in plans:
		for objective: MissionDefinition in plan.missions:
			if objective.kind == "hold_interact":
				game._deploy(objective.target_point + Vector3(0, 2, 12))
				await game._wait_for_world()
				for frame in 3:
					await physics_frame
				var center := objective.target_point + Vector3(0, 1.3, -3)
				var query := PhysicsRayQueryParameters3D.create(center + Vector3(0, 0, 5) - game.streamer.origin_offset, center - Vector3(0, 0, 5) - game.streamer.origin_offset)
				beacon_hit = not game.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
				break
		if beacon_hit:
			break
	check(beacon_hit, "a real generated calibration beacon blocks physics rays")
	var overview := Camera3D.new()
	game.add_child(overview)
	for plan: Dictionary in plans:
		var station: Dictionary = plan.stations[0]
		var offset := Vector3(0, 65, 105) if plan.kind != "maze" else Vector3(0, 7, 5)
		var point: Vector3 = station.point + offset
		game._deploy(point)
		await game._wait_for_world()
		for frame in 120:
			await process_frame
		overview.position = point - game.streamer.origin_offset
		overview.look_at(station.point - game.streamer.origin_offset)
		overview.current = true
		await process_frame
		await capture("biome-" + plan.kind)
	# Look along an actual open corridor; keep the ceiling and all walls present.
	var best_cell := 0
	var best_direction := 0
	var best_length := 0
	for cell in data.doors.size():
		for direction in 4:
			var current: int = cell
			var length := 0
			while data.doors[current] & (1 << direction):
				current += BiomeStructures.DIRECTIONS[direction].x + BiomeStructures.DIRECTIONS[direction].y * int(data.width)
				length += 1
			if length > best_length:
				best_length = length
				best_cell = cell
				best_direction = direction
	var direction_2d: Vector2i = BiomeStructures.DIRECTIONS[best_direction]
	var forward := Vector3(direction_2d.x, 0, direction_2d.y)
	var interior := BiomeStructures.cell_point(data, best_cell) + Vector3.UP * BiomeStructures.NAV_HEIGHT
	game._deploy(interior)
	await game._wait_for_world()
	for frame in 100:
		await process_frame
	overview.position = interior - game.streamer.origin_offset
	overview.look_at(interior + forward * 40 - game.streamer.origin_offset)
	overview.current = true
	await process_frame
	await capture("maze-corridor")
	# Explicitly reveal the maze with a valid completion in this geometry-focused fixture.
	game.store.visit_region(maze.id)
	game.store.data.exploration.mapped[maze.id] = true
	game._show_map()
	await process_frame
	await capture("irregular-map")
	game.menu.layers.select(3)
	game.menu.layers.item_selected.emit(3)
	var filtered: bool = game.menu.map_canvas.visible_layer == "maze"
	for id: String in game.menu.location_buttons:
		filtered = filtered and game.menu.location_buttons[id].visible == (game.navigation.find_location(id).layer == "maze")
	check(filtered, "height layer control filters both the map and destination list")
	await process_frame
	await capture("maze-map")
	game._close_menu()
	game._show_missions()
	await process_frame
	await capture("generated-tasks")
	game._close_menu()
	var old_seed: int = game.store.data.seed
	game.store.writable = false
	check(not game._restart_seed(314159).ok and game.generator.seed_value == old_seed, "failed seed reset preserves the live world")
	game.store.writable = true
	check(game._restart_seed(314159).ok and game.store.data.assignments.is_empty(), "seed reset replaces all world systems and clears old objectives")
	await game._wait_for_world()
	check(game.streamer.collision_ready(game._world_position()) and game.streamer.active.size() <= 825, "new procedural spawn loads with bounded chunk streaming")
	game.queue_free()
	await process_frame
	print("REGIONS_RESULT failures=", failed, " checks=", checked)
	quit(1 if failed else 0)
