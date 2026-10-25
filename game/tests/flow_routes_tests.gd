extends SceneTree
var failed := 0
var checked := 0
var report := {"routes": [], "fallbacks": [], "seeds": [271828, 42, 314159]}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)

func run() -> void:
	var catalog := ContentCatalog.new()
	index_equivalence()
	var signatures := {}
	var environments := {}
	for seed_value: int in report.seeds:
		var world := BiomeWorld.new(catalog, seed_value)
		var counts := {"surface": 0, "sky": 0, "maze": 0}
		var valid := true
		for x in range(-3, 4):
			for z in range(-3, 4):
				for kind: String in counts:
					if counts[kind] >= (24 if kind == "surface" else 8):
						continue
					var plan := world.plan(kind, Vector2i(x, z))
					if plan.is_empty():
						continue
					counts[kind] += 1
					for mission: MissionDefinition in plan.missions:
						if mission.kind != "race":
							continue
						var previous_id := mission.id.trim_suffix(":acro")
						if not previous_id.trim_suffix(":precision").ends_with(":flow"):
							report.fallbacks.append(mission.id)
							continue
						var environment: String = kind if kind != "surface" else plan.biomes[0].provider_id
						environments[environment] = true
						var minimum := INF
						var maximum := 0.0
						var max_turn := 0.0
						var acro: bool = mission.challenge.get("acro_revision", 0) > 0
						for index in mission.checkpoints.size():
							if index == 0:
								continue
							var incoming := (mission.checkpoints[index] - mission.checkpoints[index - 1]).normalized()
							valid = valid and incoming.dot(mission.gate_normals[index]) >= (0.34 if acro else 0.70)
							var distance := mission.checkpoints[index].distance_to(mission.checkpoints[index - 1])
							minimum = minf(minimum, distance)
							maximum = maxf(maximum, distance)
							if index < mission.checkpoints.size() - 1:
								var outgoing := (mission.checkpoints[index + 1] - mission.checkpoints[index]).normalized()
								max_turn = maxf(max_turn, rad_to_deg(acos(clampf(incoming.dot(outgoing), -1, 1))))
								valid = valid and outgoing.dot(mission.gate_normals[index]) >= (0.34 if acro else 0.70)
						valid = valid and max_turn <= (132.1 if acro else 91) and minimum >= 8
						var legacy := world.mission(previous_id if acro else mission.id.trim_suffix(":precision") if mission.id.ends_with(":precision") else mission.id.trim_suffix(":flow"))
						valid = valid and legacy != null and not legacy.legacy_objects.is_empty() and legacy.acceptance_point().is_equal_approx(mission.acceptance_point())
						valid = valid and world.mission(mission.id).checkpoints == mission.checkpoints
						# Distances/turns measure shape independently of world translation.
						var signature := "%d/%.1f/%.1f/%.1f" % [mission.checkpoints.size(), minimum, maximum, max_turn]
						signatures[signature] = true
						report.routes.append({"id": mission.id, "seed": seed_value, "environment": environment, "gates": mission.checkpoints.size(), "shortest_leg": minimum, "longest_leg": maximum, "maximum_turn": max_turn})
		check(valid, "route directions flow, old keys resolve and reception slots stay stable seed=" + str(seed_value))
		check(counts.surface == 24 and counts.sky == 8 and counts.maze == 8, "sample 24 surface regions and eight of each volume layer")
	check(signatures.size() >= 12 and environments.size() >= 5, "routes have varied shapes in cities, forests, desert, sky and maze")
	check(report.fallbacks.is_empty(), "sampled public races all use environmental routes: " + str(report.fallbacks))
	var replay_world := BiomeWorld.new(catalog, 271828)
	var id: String = report.routes[0].id
	var independent := BiomeWorld.new(catalog, 271828)
	check(replay_world.mission(id).checkpoints == independent.mission(id).checkpoints, "fresh world generation deterministically reproduces the same environmental course")
	history(catalog, id)
	report.failures = failed
	report.checks = checked
	var directory := "res://../.local/test-results/flow-routes"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open(directory.path_join("routes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FLOW_ROUTES_RESULT failures=%d checks=%d routes=%d shapes=%d" % [failed, checked, report.routes.size(), signatures.size()])
	quit(1 if failed > 0 else 0)

func finish_race(store: ProgressStore, mission: MissionDefinition) -> Dictionary:
	var accepted := store.accept_mission(mission.id)
	if not accepted.ok:
		return accepted
	var state: Dictionary = store.data.assignments[mission.id].duplicate(true)
	state.stage = mission.checkpoints.size()
	var saved := store.save_challenge_state(mission.id, state)
	return store.complete_mission(mission.id) if saved.ok else saved

func history(catalog: ContentCatalog, id: String) -> void:
	var store := ProgressStore.new(catalog, "user://tests/flow_history_%d/progress.json" % Time.get_ticks_usec())
	var current := store.mission_definition(id)
	var old := store.mission_definition(current.history_id)
	check(finish_race(store, old).ok, "historical course can still complete at its original checkpoints")
	var cash: int = store.data.credits
	check(store.mission_status(current.id) == "completed" and store.mission_completed_once(current.id), "new route inherits the old course's completion status before acceptance")
	store = ProgressStore.new(catalog, store.path)
	check(finish_race(store, current).ok and store.data.credits == cash, "new layout cannot reissue a historical first-completion reward after reload")
	check(AchievementBook.counts(store.data, catalog).missions == 1, "layout variants count as one completed task for collection achievements")
	var nav := MapNavigation.new(4)
	var exploration := WorldExploration.new(store, nav)
	store.visit_region(store.regions.instance_at(current.acceptance_point()).id)
	exploration.refresh(RegionalWorld.key_at(current.acceptance_point()))
	check(exploration.definitions.filter(func(item: MissionDefinition): return item.id == old.id).is_empty() and exploration.definitions.any(func(item: MissionDefinition): return item.id == current.id), "map presents one completed reception slot instead of overlapping historical icons")
	var reverse := ProgressStore.new(catalog, "user://tests/flow_reverse_%d/progress.json" % Time.get_ticks_usec())
	check(finish_race(reverse, current).ok and finish_race(reverse, old).ok and reverse.data.credits == cash, "first new route then historical replay also share the single reward")
	var active := ProgressStore.new(catalog, "user://tests/flow_active_%d/progress.json" % Time.get_ticks_usec())
	active.accept_mission(old.id)
	var state: Dictionary = active.data.assignments[old.id].duplicate(true)
	state.stage = 1
	active.save_challenge_state(old.id, state)
	active = ProgressStore.new(catalog, active.path)
	check(active.mission_status(old.id) == "active" and active.data.assignments[old.id].stage == 1 and active.mission_definition(old.id).checkpoints == old.checkpoints, "an active historical route reloads its original saved stage and geometry")

func index_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17831
	var objects: Array[Dictionary] = []
	for index in 80:
		var object := WorldProvider.box(str(index), Vector3(rng.randf_range(-64, 64), rng.randf_range(-24, 24), rng.randf_range(-64, 64)), Vector3(rng.randf_range(0.2, 20), rng.randf_range(0.2, 15), rng.randf_range(0.2, 20)), Color.WHITE)
		object.rotation = Vector3(rng.randf_range(-PI, PI), rng.randf_range(-PI, PI), rng.randf_range(-PI, PI))
		objects.append(object)
	var bins := FlowCourses._prepare_obstacles(objects)
	var equal := typeof(bins) == TYPE_DICTIONARY and bins.size() > 1
	for index in 400:
		var a := Vector3(rng.randf_range(-80, 80), rng.randf_range(-32, 32), rng.randf_range(-80, 80))
		var b := Vector3(rng.randf_range(-80, 80), rng.randf_range(-32, 32), rng.randf_range(-80, 80)) if index % 3 else a
		if index % 10 == 0:
			a = a.snapped(Vector3.ONE * 16)
		var brute_clear := true
		for object: Dictionary in objects:
			var inverse := Transform3D(Basis.from_euler(object.rotation), object.center).affine_inverse()
			var box := AABB(-object.size * 0.5, object.size).grow(0.75)
			var from: Vector3 = inverse * a
			var to: Vector3 = inverse * b
			if box.has_point(from) or box.has_point(to) or box.intersects_segment(from, to) != null:
				brute_clear = false
				break
		equal = equal and FlowCourses._segment_clear(a, b, bins) == brute_clear
	check(equal, "spatial collision index matches brute-force rotated boxes for 400 segments/points, negative coordinates and cell boundaries")
