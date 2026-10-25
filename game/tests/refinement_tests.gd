extends SceneTree
var failed := 0
var checked := 0
var catalog: ContentCatalog
var world: BiomeWorld
var examples := {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func run() -> void:
	catalog = ContentCatalog.new()
	world = BiomeWorld.new(catalog, 271828)
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			var kind: String = site.biome.parameters.get("terrain_style", "city" if site.biome.provider_id == "base.generator.modular_city" else "")
			if not kind.is_empty() and not examples.has(kind): examples[kind] = site
	await waypoints()
	mesh_normals()
	await courses()
	await caves()
	await repairs()
	print("REFINEMENT_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
func waypoints() -> void:
	var nav := MapNavigation.new(4)
	var location := MapLocation.new()
	location.id = "existing"
	location.point = Vector3(100, 20, 50)
	nav.locations.append(location)
	nav.select(location.id, Vector3.ZERO)
	var route := nav.route.duplicate()
	nav.place_temporary(Vector3(1, 20, 1), Vector3.ZERO, false)
	check(nav.selected_id == "existing" and nav.route == route and nav.find_location("temporary") != null, "temporary preview preserves an active ordinary destination and complete route")
	nav.select("temporary", Vector3.ZERO)
	var target := nav.selected().point
	route = nav.route.duplicate()
	nav.place_temporary(Vector3(200, 20, 200), Vector3.ZERO, false)
	check(nav.selected().point == target and nav.route == route and nav.find_location("temporary").point != target, "placing a second preview preserves an actively tracked temporary target")
	for index in 8: nav.place_temporary(Vector3(index, 20, 100), Vector3.ZERO, false)
	check(nav.locations.filter(func(p: MapLocation): return p.layer == "temporary").size() == 2, "repeated previews stay bounded to active and viewed markers")
	nav.select("temporary", Vector3.ZERO)
	check(nav.selected().point == Vector3(7, 20, 100) and nav.route[-1] == nav.selected().point, "explicit tracking installs the preview route")
	nav.clear()
	check(nav.locations.size() == 1, "clearing removes active and preview temporary markers")
func mesh_normals() -> void:
	var rock := FeatureGeometry.rock("rock", Vector3.ZERO, 419)
	var valid := true
	for triangle in rock.surfaces.size():
		var a: int = rock.indices[triangle * 3]
		var b: int = rock.indices[triangle * 3 + 1]
		var c: int = rock.indices[triangle * 3 + 2]
		valid = valid and Vector3(rock.vertices[b] - rock.vertices[a]).cross(rock.vertices[c] - rock.vertices[a]).dot(rock.normals[a]) < 0
	check(valid, "all exposed honeycomb faces use Godot clockwise winding matching their outward normals")
func courses() -> void:
	for kind: String in ["city", "ruined_city", "monument"]:
		var plan := world.plan("surface", examples[kind].key)
		var count := 0
		var host := Node3D.new()
		root.add_child(host)
		var keys := {}
		var targets: Array[Dictionary] = []
		for task: MissionDefinition in plan.missions:
			if task.kind not in ["regional", "race"]: continue
			check(task.challenge.get("precision_revision", 0) == 1, kind + " new public challenge uses building-dependent precision layout")
			if task.challenge.get("precision_revision", 0) == 0: continue
			count += 1
			var old := world.mission(task.id.trim_suffix(":acro") if task.id.ends_with(":acro") else task.id.trim_suffix(":precision"))
			check(old != null and old.transaction_id() == task.transaction_id(), "old layout resolves with the same one-time reward identity")
			var longest := 0.0
			for index in range(1, task.checkpoints.size()): longest = maxf(longest, task.checkpoints[index - 1].distance_to(task.checkpoints[index]))
			if task.kind == "race" and task.challenge.get("acro_revision", 0) > 0:
				check(task.checkpoints.size() > old.checkpoints.size() and task.checkpoints.size() <= AcroCourses.MAX_GATES, kind + " new race adds bounded close manoeuvres instead of requiring long trips")
			else:
				check(longest >= 100, kind + " regional route still retains its requested long legs")
			for index in task.checkpoints.size():
				var p := task.checkpoints[index]
				if task.kind == "race" or task.challenge.mode == "clean":
					if index > 0: targets.append({"a": task.checkpoints[index - 1], "b": p})
				else:
					targets.append({"a": p + Vector3.UP, "b": p})
				if task.kind == "race":
					var basis := FlightChallengeRules.gate_basis(task.gate_normals[index])
					var half := float(task.challenge.gate_half) - 0.5
					for x: float in [-half, 0, half]:
						for y: float in [-half, 0, half]: targets.append({"a": p + basis * Vector3(x, y, -0.5), "b": p + basis * Vector3(x, y, 0.5)})
		check(count > 0, kind + " supplies upgraded challenges")
		for target in targets:
			var steps := ceili(Vector3(target.a).distance_to(target.b) / 32) + 1
			for step in steps + 1:
				var key := WorldGenerator.key_at(Vector3(target.a).lerp(target.b, float(step) / steps))
				for x in range(-1, 2):
					for y in range(-1, 2):
						for z in range(-1, 2): keys[key + Vector3i(x, y, z)] = true
		for key: Vector3i in keys:
			var descriptor := world.generate_chunk(key)
			if not descriptor.objects.is_empty(): host.add_child(WorldGeometry.create_chunk(descriptor, Vector3.ZERO))
		await physics_frame
		await physics_frame
		var query := PhysicsShapeQueryParameters3D.new()
		var body := BoxShape3D.new()
		body.size = Vector3(0.6, 0.2, 0.6)
		query.shape = body
		var clear := true
		for target in targets:
			query.transform = Transform3D(Basis.IDENTITY, target.a)
			query.motion = target.b - target.a
			var fraction := host.get_world_3d().direct_space_state.cast_motion(query)[0]
			if fraction < 1:
				print("BLOCKED ", kind, " ", target, " fraction=", fraction)
				clear = false
		check(clear, kind + " production buildings, terminals and new gate openings fit the real drone")
		host.queue_free()
		await physics_frame
func caves() -> void:
	for kind: String in ["alpine", "snow_peak", "ravine", "volcano"]:
		var plan := world.plan("surface", examples[kind].key)
		check(not plan.caves.is_empty(), kind + " has a connected cave network")
		if plan.caves.is_empty(): continue
		var cave: Dictionary = plan.caves[0]
		check(cave.paths.size() == 3 and cave.segments.size() >= 12, kind + " main path, return loop, descending spur and junction rooms exist")
		check(cave.paths[0][2].is_equal_approx(cave.paths[1][0]) and cave.paths[0][6].is_equal_approx(cave.paths[1][-1]) and cave.paths[0][4].is_equal_approx(cave.paths[2][0]), kind + " branches join the actual main-path nodes without displaced endpoints")
		var host := Node3D.new()
		root.add_child(host)
		for objects: Array in plan.chunks.values():
			var chosen := objects.filter(func(o: Dictionary): return o.id.begins_with(cave.id))
			if not chosen.is_empty(): host.add_child(WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": chosen}, Vector3.ZERO))
		await physics_frame
		await physics_frame
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 0.2, 0.6)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		var clear := true
		for path: PackedVector3Array in cave.paths:
			for index in path.size() - 1:
				query.transform = Transform3D(Basis.IDENTITY, path[index])
				query.motion = path[index + 1] - path[index]
				var fraction := host.get_world_3d().direct_space_state.cast_motion(query)[0]
				if fraction < 1:
					print("CAVE_BLOCKED ", kind, " ", index, " ", path[index], " ", path[index + 1], " ", fraction)
					clear = false
		check(clear, kind + " real body traverses every bend, branch and junction without internal wall caps")
		host.queue_free()
		await physics_frame
func repairs() -> void:
	var plan := world.plan("surface", examples.ruined_city.key)
	var store := ProgressStore.new(catalog, "user://tests/refinement018_%d/progress.json" % Time.get_ticks_usec())
	store.regions = world
	var portal: String = plan.stations[0].id
	check(not store.unlock_portal(portal).ok, "unrepaired ruined portal cannot unlock")
	var credits: int = store.data.credits
	for task: MissionDefinition in plan.missions:
		if task.kind != "regional" or not task.challenge.portal_required: continue
		check(store.accept_mission(task.id).ok, "new repair layout can be accepted")
		var state: Dictionary = store.data.assignments[task.id].duplicate(true)
		state.stage = task.checkpoints.size()
		check(store.save_challenge_state(task.id, state).ok and store.complete_mission(task.id).ok, "new layout completion persists through shared history")
	check(store.portal_unlocked(portal) and store.data.credits == credits + 135, "all three new repair layouts atomically restore local teleport network")
	var old: String = plan.portal_requirements[0]
	store.accept_mission(old)
	var state: Dictionary = store.data.assignments[old].duplicate(true)
	state.stage = 3
	store.save_challenge_state(old, state)
	store.complete_mission(old)
	check(store.data.credits == credits + 135, "replaying an old repair layout cannot duplicate its new-layout reward")
