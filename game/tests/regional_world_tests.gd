extends SceneTree
var failed := 0
var checked := 0
var examples := {}
var plans := {}
var catalog: ContentCatalog
var world: BiomeWorld
var directory := "res://../.local/test-results/regional017"
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	catalog = ContentCatalog.new()
	world = BiomeWorld.new(catalog, 271828)
	var fingerprint := catalog.fingerprint()
	check(catalog.errors.is_empty(), "catalog validates")
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			var style: String = site.biome.parameters.get("terrain_style", "")
			if not style.is_empty() and not examples.has(style):
				examples[style] = site
	for style: String in examples:
		var start := Time.get_ticks_msec()
		var plan := world.plan("surface", examples[style].key)
		plans[style] = plan
		print("PLAN ", style, " ", plan.id, " objects=", plan.objects.size(), " caves=", plan.caves.size(), " ms=", Time.get_ticks_msec() - start)
		check(plan.missions.size() >= 2 and plan.missions.size() <= 5, style + " public tasks remain bounded")
	await repairs()
	await puzzles()
	await contact_events()
	await physical_features()
	var gobi: Dictionary = plans.gobi
	var hidden_rocks := 0
	var registered := {}
	for location: MapLocation in gobi.locations: registered[location.id] = true
	var rocks_hidden := true
	for landmark: Dictionary in gobi.landmarks:
		if landmark.kind != "hollow_rock": continue
		hidden_rocks += 1
		rocks_hidden = rocks_hidden and not registered.has(landmark.id)
	check(hidden_rocks > 5 and rocks_hidden, "dense honeycomb rocks retain architecture metadata without special map icons")
	var real_landmarks_visible := true
	for plan: Dictionary in plans.values():
		var location_ids := {}
		for location: MapLocation in plan.locations: location_ids[location.id] = true
		for landmark: Dictionary in plan.landmarks:
			if landmark.get("map_visible", true): real_landmarks_visible = real_landmarks_visible and location_ids.has(landmark.id)
	check(real_landmarks_visible, "ordinary special buildings still appear as map destinations")
	plans.monument_core = world.plan("surface", Vector2i(4, 0))
	examples.monument_core = world.field.surface_site(Vector2i(4, 0))
	await production_clearance()
	seeded_generation()
	check(fingerprint == catalog.fingerprint(), "shared definitions stay immutable")
	print("REGIONAL_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
func repairs() -> void:
	var plan: Dictionary = plans.ruined_city
	var requirements: Array = plan.portal_requirements
	check(requirements.size() == 3, "every ruined city has three independent repair circuits")
	var store := ProgressStore.new(catalog, "user://tests/regional017_%d/progress.json" % Time.get_ticks_usec())
	store.regions = world
	var portal: String = plan.stations[0].id
	store.data.exploration.portals[portal] = true
	check(not store.portal_unlocked(portal) and not store.unlock_portal(portal).ok, "even a previously registered ruined portal requires repairs")
	var nav := MapNavigation.new(4)
	nav.locations.assign(plan.locations)
	nav.teleport_resolver = store.portal_unlocked
	var controller := MissionController.new(catalog, store, nav)
	var panel := RegionMap.new()
	panel.navigation = nav
	panel.controller = controller
	panel.biomes.assign(plan.biomes)
	root.add_child(panel)
	await process_frame
	panel._select(portal)
	check(panel.teleport_button.disabled and panel.details.text.contains("线路修复 0/3") and not panel.details.text.contains("按 E 解锁"), "offline portal details explain required circuits without an incorrect E-unlock instruction")
	panel._track_viewed()
	check(nav.selected_id == portal and store.data.tracked_mission.is_empty(), "locked portal can be explicitly tracked without accepting a task")
	panel.queue_free()
	await process_frame
	var start_credits: int = store.data.credits
	var reward_credits := 0
	for index in requirements.size():
		var task := world.mission(requirements[index])
		check(task != null and task.kind == "regional" and task.checkpoints.size() == 3, "repair task resolves by stable generated ID")
		check(store.accept_mission(task.id).ok, "repair can be accepted")
		var state: Dictionary = store.data.assignments[task.id].duplicate(true)
		for point: Vector3 in task.checkpoints:
			for step in 13:
				state = FlightChallengeRules.step(task, state, point, point, 0.1, {"speed": 0.0, "interacting": true})
		check(FlightChallengeRules.finished(task, state) and store.save_challenge_state(task.id, state).ok, "repair terminals require interaction and persist progress")
		if index == 2:
			var credits_before: int = store.data.credits
			store.writable = false
			check(not store.complete_mission(task.id).ok and store.data.credits == credits_before and not store.portal_unlocked(portal), "failed third-repair save grants neither credit nor portal")
			store.writable = true
		check(store.complete_mission(task.id).ok, "repair commits first completion")
		reward_credits += catalog.entries[task.reward_id].credits
		check(store.portal_unlocked(portal) == (index == 2), "portal remains gated until all three independent circuits finish")
	check(store.data.credits == start_credits + reward_credits, "three repairs award precisely three first rewards")
	for station: Dictionary in plan.stations:
		check(store.portal_unlocked(station.id), "third repair automatically restores all local portals")
	var restored := ProgressStore.new(catalog, store.path)
	check(restored.portal_unlocked(portal), "portal repairs and completion survive restart")
	var task := world.mission(requirements[0])
	store.accept_mission(task.id)
	var state: Dictionary = store.data.assignments[task.id].duplicate(true)
	state.stage = task.checkpoints.size()
	store.save_challenge_state(task.id, state)
	store.complete_mission(task.id)
	check(store.data.credits == start_credits + reward_credits and store.portal_unlocked(portal), "replaying a repair preserves portal and gives no duplicate credits")
	store.accept_mission(task.id)
	var target := task.checkpoints[0]
	for step in 5: controller.update_objective(target, 0, 0.1, false, false, {}, 0)
	check(controller.challenge_state(task).get("stage", 0) == 0, "production repair controller requires held interaction")
	for step in 13: controller.update_objective(target, 0, 0.1, true, false, {}, 0)
	check(store.data.assignments[task.id].get("stage", 0) == 1, "production repair controller commits the activated terminal")

func contact_events() -> void:
	var surface := WorldGeometry.create_box(Vector3(0, -1, 0), Vector3(20, 2, 20), Color.GRAY)
	root.add_child(surface)
	var drone := FPVDrone.new()
	root.add_child(drone)
	var tuning := FlightTuning.defaults()
	tuning.gravity = 0
	tuning.air_drag = 0
	drone.apply_tuning(tuning)
	drone.reset_drone(Vector3(0, 2, 0))
	for step in 4: await physics_frame
	var before := drone.contact_serial
	drone.linear_velocity = Vector3(0, -400, 0)
	for step in 10: await physics_frame
	check(drone.contact_serial > before and drone.swept_impacts > 0, "real high-speed body collision increments challenge contact serial")
	drone.set_simulation_paused(true)
	before = drone.contact_serial
	for step in 5: await physics_frame
	check(drone.contact_serial == before, "pausing preserves collision-free challenge contact baseline")
	drone.reset_drone(Vector3(0, 10, 0))
	check(drone.contact_serial > before, "explicit redeployment invalidates collision-free attempt")
	drone.queue_free()
	surface.queue_free()
	await physics_frame
func puzzles() -> void:
	var plan: Dictionary = plans.monument
	check(plan.mega_cells.size() >= 50 and plan.feature_objects > 1000, "megastructure contains a large connected modular district")
	var sequence: MissionDefinition
	var clean: MissionDefinition
	for task: MissionDefinition in plan.missions:
		if task.kind == "regional":
			if task.challenge.mode == "sequence": sequence = task
			else: clean = task
	check(sequence != null and clean != null, "monuments provide ordered-symbol and collision-free puzzles")
	var saved := {"status": "active", "kind": "regional", "stage": 0}
	var state := RegionalChallengeRules.step(sequence, saved, sequence.checkpoints[2], sequence.checkpoints[2], 0.1, {})
	check(state.stage == 0 and state.attempts == 1, "wrong symbol order resets attempt")
	for point: Vector3 in sequence.checkpoints:
		for step in 4:
			state = RegionalChallengeRules.step(sequence, state, point, point, 0.1, {"speed": 0.0, "interacting": true})
	check(FlightChallengeRules.finished(sequence, state), "ordered activation has an achievable completion path")
	state = RegionalChallengeRules.step(clean, saved, clean.checkpoints[0], clean.checkpoints[0], 0.1, {"contacts": 5})
	state = RegionalChallengeRules.step(clean, state, clean.checkpoints[1], clean.checkpoints[1], 0.1, {"contacts": 6})
	check(state.stage == 0 and not state.started and state.attempts == 1, "true or swept contact serial resets clean route")
	for point: Vector3 in clean.checkpoints:
		state = RegionalChallengeRules.step(clean, state, point, point, 0.1, {"contacts": 6})
	check(FlightChallengeRules.finished(clean, state), "all clean nodes complete without collision or timer")
func physical_features() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var rock := FeatureGeometry.rock("test_rock", Vector3.ZERO, 419)
	var rock_node := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": [rock]}, Vector3.ZERO)
	host.add_child(rock_node)
	await physics_frame
	await physics_frame
	var space := host.get_world_3d().direct_space_state
	var body := BoxShape3D.new()
	body.size = Vector3(0.6, 0.2, 0.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		query.transform = Transform3D(Basis.IDENTITY, rock.center - axis * 30)
		query.motion = axis * 60
		check(space.cast_motion(query)[0] == 1.0, "a real drone body flies through rock bore along " + str(axis))
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(rock.center + Vector3(8, 60, 8), rock.center + Vector3(8, -60, 8))).is_empty(), "hollow rock retains solid shell collision")
	host.remove_child(rock_node)
	rock_node.queue_free()
	for style: String in ["alpine", "snow_peak", "ravine", "volcano"]:
		var plan: Dictionary = plans[style]
		check(not plan.caves.is_empty(), style + " has physical mountain passages")
		if plan.caves.is_empty(): continue
		var cave: Dictionary = plan.caves[0]
		var cave_objects: Array[Dictionary] = []
		for objects: Array in plan.chunks.values():
			for object: Dictionary in objects:
				if object.id.begins_with(cave.id + "/"): cave_objects.append(object)
		var node := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": cave_objects}, Vector3.ZERO)
		host.add_child(node)
		await physics_frame
		await physics_frame
		var axis: Vector3 = (cave.b - cave.a).normalized()
		var clear := true
		for path: PackedVector3Array in cave.paths:
			for index in path.size() - 1:
				query.transform.origin = path[index]
				query.motion = path[index + 1] - path[index]
				clear = clear and space.cast_motion(query)[0] == 1.0
		check(clear, style + " all connected cave paths fit the drone")
		var center: Vector3 = cave.paths[0][4]
		check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(center, center + Vector3.UP * 20)).is_empty(), style + " tunnel has a solid roof")
		host.remove_child(node)
		node.queue_free()
		host.add_child(Node3D.new())
		await physics_frame
	host.queue_free()

func seeded_generation() -> void:
	for seed_value in [31, 271828, 90917]:
		var generated := BiomeWorld.new(catalog, seed_value)
		var samples := {}
		for x in range(-10, 11):
			for z in range(-10, 11):
				var site := generated.field.surface_site(Vector2i(x, z))
				var style: String = site.biome.parameters.get("terrain_style", "")
				if style in ["ruined_city", "monument", "gobi", "alpine", "snow_peak", "ravine", "volcano"] and not samples.has(style): samples[style] = site
		var valid := samples.size() == 7
		for style: String in samples:
			var plan := generated.plan("surface", samples[style].key)
			valid = valid and plan.missions.size() <= 5 and plan.missions.size() >= 2
			if style == "ruined_city":
				valid = valid and plan.portal_requirements.size() == 3
				for task: MissionDefinition in plan.missions:
					if task.kind != "regional": continue
					for a in task.checkpoints.size():
						for b in range(a + 1, task.checkpoints.size()): valid = valid and task.checkpoints[a].distance_to(task.checkpoints[b]) >= 24
			if style in ["alpine", "snow_peak", "ravine", "volcano"]: valid = valid and not plan.caves.is_empty()
			if style == "monument": valid = valid and plan.mega_cells.size() > 25
			var signature := geometry_signature(plan)
			generated.plans.erase(plan.id)
			valid = valid and signature == geometry_signature(generated.plan("surface", samples[style].key))
		check(valid, "seed %d reproduces real openings, bounded missions, three repairs and identical modules" % seed_value)

func geometry_signature(plan: Dictionary) -> String:
	var records := PackedStringArray()
	for objects: Array in plan.chunks.values():
		for object: Dictionary in objects: records.append(object.id + str(object.center) + str(object.size) + str(object.get("indices", []).size()))
	for task: MissionDefinition in plan.missions: records.append(task.id + str(task.checkpoints))
	records.sort()
	return "\n".join(records).sha256_text()

func production_clearance() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.2, 0.6)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	for style: String in ["alpine", "snow_peak", "ravine", "volcano", "monument", "monument_core", "ruined_city"]:
		var plan: Dictionary = plans[style]
		var targets: Array[Dictionary] = []
		if not plan.caves.is_empty():
			for cave: Dictionary in plan.caves:
				for path: PackedVector3Array in cave.paths:
					for index in path.size() - 1: targets.append({"a": path[index], "b": path[index + 1]})
		for task: MissionDefinition in plan.missions:
			var entry := task.acceptance_point()
			targets.append({"a": entry + Vector3.UP * 1.5, "b": entry + Vector3.UP * 0.3})
			if task.kind != "regional": continue
			if task.challenge.mode == "clean":
				for index in range(1, task.checkpoints.size()):
					targets.append({"a": task.checkpoints[index - 1], "b": task.checkpoints[index]})
			else:
				for p: Vector3 in task.checkpoints:
					targets.append({"a": p + Vector3.UP * 1.0, "b": p + Vector3.UP * 0.1})
		var keys := {}
		for target in targets:
			var steps := ceili(Vector3(target.a).distance_to(target.b) / 20) + 1
			for step in steps + 1:
				var key := WorldGenerator.key_at(Vector3(target.a).lerp(target.b, float(step) / steps))
				for x in range(-1, 2):
					for y in range(-1, 2):
						for z in range(-1, 2): keys[key + Vector3i(x, y, z)] = true
		var sector := Node3D.new()
		host.add_child(sector)
		for key: Vector3i in keys:
			var descriptor := world.generate_chunk(key)
			if not descriptor.objects.is_empty(): sector.add_child(WorldGeometry.create_chunk(descriptor, Vector3.ZERO))
		await physics_frame
		await physics_frame
		var clear := true
		var index := 0
		for target in targets:
			query.transform = Transform3D(Basis.IDENTITY, target.a)
			query.motion = target.b - target.a
			var value := host.get_world_3d().direct_space_state.cast_motion(query)[0]
			if value < 1.0:
				print("BLOCKED ", style, " leg=", index, " fraction=", value, " from=", target.a, " to=", target.b)
				clear = false
			index += 1
		check(clear, style + " production terrain and all props leave actual cave or puzzle flight clear")
		if not plan.caves.is_empty():
			var sampler := BiomeTerrain.new(world.field, examples[style].anchor)
			var cave: Dictionary = plan.caves[0]
			var side: Vector3 = (cave.b - cave.a).normalized().cross(Vector3.UP)
			var closed := true
			for sign_value: float in [-1, 1]:
				var p: Vector3 = cave.a + side * (float(cave.radius) + 3) * sign_value
				var height := sampler.sample(p.x, p.z)
				var hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, height + 15, p.z), Vector3(p.x, height - 15, p.z)))
				closed = closed and not hit.is_empty() and absf(float(hit.get("position", Vector3.INF).y) - height) < 8
			check(closed, style + " ground outside cave mouth remains present with collision")
		host.remove_child(sector)
		sector.queue_free()
		await physics_frame
	host.queue_free()
