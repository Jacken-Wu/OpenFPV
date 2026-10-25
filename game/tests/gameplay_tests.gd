extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/gameplay"
var game: Node3D
var examples: Dictionary = {}
var geometry_cases: Array[Dictionary] = []
func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1
func capture(name_text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_text + ".png")) == OK, "capture " + name_text)
func base_state(mission: MissionDefinition) -> Dictionary:
	return {"status": "active", "kind": mission.kind}
func view(point: Vector3, target: Vector3, clear: bool = true) -> Dictionary:
	return {"origin": point, "forward": (target - point).normalized(), "clear": clear}
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	check(catalog.errors.is_empty(), "all expanded content passes validation " + str(catalog.errors))
	check(catalog.manifest.offers.size() >= 14 and catalog.presets.size() >= 5 and catalog.parts.size() >= 16, "three new kits and their individually sold parts are explicitly registered")
	var fingerprint := catalog.fingerprint()
	var store := ProgressStore.new(catalog, "user://tests/gameplay_%d/progress.json" % Time.get_ticks_usec())
	var layout: BiomeWorld = store.regions
	var plans: Array[Dictionary] = []
	var terrain_count := {"surface": 0, "sky": 0, "maze": 0}
	var race_layers := {}
	for x in range(-3, 4):
		for z in range(-3, 4):
			for kind: String in ["surface", "sky", "maze"]:
				if terrain_count[kind] >= (12 if kind == "surface" else 3) and examples.size() == 4 and (kind != "maze" or race_layers.has("maze")):
					continue
				var p := layout.plan(kind, Vector2i(x, z))
				if p.is_empty():
					continue
				plans.append(p)
				terrain_count[kind] += 1
				var ids := {}
				var valid: bool = p.missions.size() >= 2 and p.missions.size() <= 5
				for mission: MissionDefinition in p.missions:
					valid = valid and not ids.has(mission.id) and mission.acceptance_point().is_finite()
					ids[mission.id] = true
					if mission.kind in FlightChallengeRules.KINDS:
						examples[mission.kind] = mission if not examples.has(mission.kind) else examples[mission.kind]
						valid = valid and layout.mission(mission.id).kind == mission.kind
						for point: Vector3 in mission.checkpoints:
							valid = valid and point.y < 297 and point.is_finite()
							if kind == "sky":
								valid = valid and layout.instance_at(point).id == p.id
						if mission.kind == "race":
							race_layers[kind] = true
							valid = valid and mission.checkpoints.size() >= 2 and mission.gate_normals.size() == mission.checkpoints.size()
				for legacy: MissionDefinition in p.legacy_missions:
					valid = valid and layout.mission(legacy.id).kind == legacy.kind
				check(valid, "deterministic 2-5 public tasks and resolvable legacy keys in " + p.id)
		if examples.size() == 4 and terrain_count.surface >= 12 and terrain_count.sky >= 3 and terrain_count.maze >= 3 and race_layers.has("maze"):
			break
	check(examples.size() == 4, "random task pool exposes route, balloons, orbit and follow")
	if examples.size() != 4:
		quit(1)
		return
	var desert_found := false
	for x in range(-2, 3):
		for z in range(-3, 4):
			if desert_found or layout.field.surface_site(Vector2i(x, z)).biome.provider_id != "base.generator.canyon":
				continue
			var desert := layout.plan("surface", Vector2i(x, z))
			if desert.missions.any(func(item: MissionDefinition): return item.kind == "race"):
				plans.append(desert)
				desert_found = true
	check(desert_found, "a real desert terrain course is included in collision checks")
	await geometry(plans, catalog)
	check(race_layers.has("maze"), "a real underground directed course is included in collision checks")
	var legacy_manifest := catalog.manifest.duplicate() as ContentManifest
	legacy_manifest.challenge_templates = []
	var legacy_world := BiomeWorld.new(ContentCatalog.new(legacy_manifest), int(store.data.seed))
	for p in plans.slice(0, 4):
		var previous := legacy_world.plan(p.kind, p.key)
		check(var_to_str(previous.stations) == var_to_str(p.stations), "platform IDs/positions remain unchanged for " + p.id)
		for index in previous.missions.size():
			check(previous.missions[index].checkpoints == p.legacy_missions[index].checkpoints and previous.missions[index].target_point == p.legacy_missions[index].target_point, "old mission geometry retains its meaning " + previous.missions[index].id)
	for p in plans:
		if p.kind == "maze":
			check(layout.map_task(p) == legacy_world.map_task(legacy_world.plan("maze", p.key)), "existing underground map-unlock task ID remains stable " + p.id)
	var nav := MapNavigation.new(4)
	var exploration := WorldExploration.new(store, nav)
	var controller := MissionController.new(catalog, store, nav)
	controller.exploration = exploration
	for mission: MissionDefinition in examples.values():
		var pickup := mission.acceptance_point()
		controller.invalidate_motion()
		var candidate := controller.available_at(pickup)
		check(candidate != null and candidate.id == mission.id, "physical discovery finds " + mission.kind + " without map selection")
		if not mission.pickup_points.is_empty():
			var old_entry := controller.available_at(mission.pickup_points[0])
			check(old_entry != null and old_entry.id == mission.id, "original physical task/gate also accepts " + mission.kind)
		check(controller.accept_nearby(pickup, 12).get("ok", true) == false, "fast fly-by cannot accidentally pick up " + mission.kind)
		store.writable = false
		var old_tracked: String = store.data.tracked_mission
		check(not controller.accept_nearby(pickup, 0, mission.id).ok and store.data.tracked_mission == old_tracked, "failed pickup leaves tracked objective unchanged")
		store.writable = true
		check(controller.accept_nearby(pickup, 0, mission.id).ok and store.data.tracked_mission == mission.id and nav.selected_id == mission.location_id, "docked E accepts and tracks " + mission.kind)
		check(not store.complete_mission(mission.id).ok, "direct completion cannot bypass " + mission.kind)
	var race: MissionDefinition = examples.race
	if not race.pickup_points.is_empty():
		var entry := controller.available_at(race.pickup_points[0])
		# This mission is already active; available lookup correctly omits it.
		check(entry == null or entry.id != race.id, "accepted race cannot be reaccepted at a legacy gate")
	var center := race.checkpoints[0]
	var normal := race.gate_normals[0]
	var side := FlightChallengeRules.gate_basis_for(race, 0).x
	check(FlightChallengeRules.passes_gate(race, 0, center - normal, center + normal), "correct signed crossing passes actual gate")
	check(not FlightChallengeRules.passes_gate(race, 0, center + normal, center - normal), "reverse gate crossing does not count")
	check(not FlightChallengeRules.passes_gate(race, 0, center - normal + side * 4, center + normal + side * 4), "passing outside the frame cannot count")
	check(not FlightChallengeRules.passes_gate(race, 0, center - normal, center - normal * 0.1), "approaching gate without crossing cannot count")
	check(FlightChallengeRules.passes_gate(race, 0, center - normal * 0.0001, center + normal * 0.0001), "very slow crossing cannot be lost in a dead band")
	check(FlightChallengeRules.step(race, base_state(race), center - normal * 100, center + normal * 100, 0.02, {}).get("stage", 0) == 0, "teleport-sized gate jump does not count")
	check(FlightChallengeRules.step(race, base_state(race), center - normal * 5, center + normal * 5, 0.2, {}).get("stage", 0) == 1, "a slow render frame still sweeps a valid fast gate crossing")
	controller.track(race.id, race.acceptance_point())
	store.writable = false
	controller.update_objective(center - normal, 0, 0.02, false, false)
	var failure := controller.update_objective(center + normal, 0, 0.02, false, false)
	check(not failure.get("ok", true) and store.data.assignments[race.id].get("stage", 0) == 0, "failed gate save rolls runtime back to last committed checkpoint")
	store.writable = true
	for index in race.checkpoints.size():
		controller.invalidate_motion()
		center = race.checkpoints[index]
		normal = race.gate_normals[index]
		controller.update_objective(center - normal, 0, 0.02, false, false)
		controller.update_objective(center + normal, 0, 0.02, false, false)
		if index == 0:
			var reloaded := ProgressStore.new(catalog, store.path)
			check(int(reloaded.data.assignments[race.id].stage) == 1, "gate checkpoint survives JSON reload")
	check(store.mission_status(race.id) == "completed", "all real directed gate crossings finish and reward route")
	var credits: int = store.data.credits
	check(store.complete_mission(race.id).get("duplicate", false) and store.data.credits == credits, "route reward cannot be paid twice")
	var balloons: MissionDefinition = examples.balloons
	controller.track(balloons.id, balloons.target_point)
	var released: Dictionary = store.data.assignments[balloons.id].duplicate(true)
	released.elapsed = FlightChallengeRules.balloon_release_time(balloons, balloons.checkpoints.size() - 1) + 0.1
	store.save_challenge_state(balloons.id, released)
	controller.balloon_states.erase(balloons.id)
	for index in range(balloons.checkpoints.size() - 1, -1, -1):
		controller.invalidate_motion()
		var time := float(controller.challenge_state(balloons).get("elapsed", 0)) + 0.04
		var balloon := FlightChallengeRules.balloon_point(balloons, index, time)
		controller.update_objective(balloon - Vector3.RIGHT * 2, 0, 0.04, false, false)
		controller.update_objective(balloon + Vector3.RIGHT * 2, 0, 0.04, false, false)
	check(store.mission_status(balloons.id) == "completed", "unordered swept balloon hits persist and complete the set")
	var orbit: MissionDefinition = examples.orbit
	var state := base_state(orbit)
	var stationary := base_state(orbit)
	var backwards := base_state(orbit)
	var radius := (float(orbit.challenge.radius_min) + float(orbit.challenge.radius_max)) / 2
	for index in range(1, 721):
		var previous := orbit.target_point + Vector3(cos((index - 1) * TAU / 720) * radius, 0, sin((index - 1) * TAU / 720) * radius)
		var point := orbit.target_point + Vector3(cos(index * TAU / 720) * radius, 0, sin(index * TAU / 720) * radius)
		state = FlightChallengeRules.step(orbit, state, previous, point, 0.02, view(point, orbit.target_point))
		var fixed := orbit.target_point + Vector3.RIGHT * radius
		stationary = FlightChallengeRules.step(orbit, stationary, fixed, fixed, 0.02, view(fixed, orbit.target_point))
	check(FlightChallengeRules.finished(orbit, state) and not FlightChallengeRules.finished(orbit, stationary), "real planar 360 orbit counts, stationary camera aiming does not")
	var slow := base_state(orbit)
	for index in range(1, 4001):
		var a := orbit.target_point + Vector3(cos((index - 1) * TAU / 4000) * radius, 0, sin((index - 1) * TAU / 4000) * radius)
		var b := orbit.target_point + Vector3(cos(index * TAU / 4000) * radius, 0, sin(index * TAU / 4000) * radius)
		slow = FlightChallengeRules.step(orbit, slow, a, b, 0.02, view(b, orbit.target_point))
	check(FlightChallengeRules.finished(orbit, slow), "slow cinematic orbit accumulates small angular steps without a direction deadzone")
	var prior := orbit.target_point + Vector3.RIGHT * radius
	for index in range(1, 721):
		var angle := (index if index <= 360 else 720 - index) * TAU / 720
		var point := orbit.target_point + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		backwards = FlightChallengeRules.step(orbit, backwards, prior, point, 0.02, view(point, orbit.target_point))
		prior = point
	check(float(backwards.get("orbit", 0)) < 0.01, "reversing over the same half-circle cannot farm a full orbit")
	var broken := state.duplicate(true)
	for index in 30:
		broken = FlightChallengeRules.step(orbit, broken, prior, prior, 0.02, view(prior, orbit.target_point, false))
	check(is_equal_approx(float(broken.orbit), float(state.orbit)), "sustained occlusion pauses orbit without erasing completed arc")
	var partial := state.duplicate(true)
	partial.orbit = TAU / 2
	check(store.save_challenge_state(orbit.id, partial).ok and is_equal_approx(ProgressStore.new(catalog, store.path).data.assignments[orbit.id].orbit, TAU / 2), "partial orbit survives reload without changing earned currency")
	check(store.save_challenge_state(orbit.id, state).ok and store.complete_mission(orbit.id).ok, "validated orbit progress commits before one-time reward")
	var follow: MissionDefinition = examples.follow
	state = base_state(follow)
	stationary = base_state(follow)
	prior = FlightChallengeRules.follow_point(follow, 0) - Vector3.FORWARD * -8
	var fixed := prior
	for index in range(1, 1501):
		var elapsed := index * 0.02
		var target := FlightChallengeRules.follow_point(follow, elapsed)
		var tangent := Vector3(-sin(elapsed * 0.2), 0, cos(elapsed * 0.2))
		var point := target - tangent * 8
		state = FlightChallengeRules.step(follow, state, prior, point, 0.02, view(point, target))
		stationary = FlightChallengeRules.step(follow, stationary, fixed, fixed, 0.02, view(fixed, target))
		prior = point
	check(FlightChallengeRules.finished(follow, state), "tracking the faster subject satisfies independent visibility and range coverage")
	var invalid := base_state(follow)
	invalid.distance = NAN
	check(not store.save_challenge_state(follow.id, invalid).ok, "nonfinite active challenge state cannot be saved")
	check(store.save_challenge_state(follow.id, state).ok and store.complete_mission(follow.id).ok, "follow objective rewards only after saved coverage evidence")
	check(not store.save_challenge_state(follow.id, base_state(follow)).ok, "completed challenge state cannot be overwritten")
	for preset: DronePresetDefinition in catalog.presets.values():
		var assembly := DroneAssembler.new(catalog).resolve(DroneAssembler.new(catalog).from_preset(preset.id), [], true)
		check(assembly.ok and assembly.spec.thrust_weight >= 2, "matching four-motor kit resolves " + preset.id)
	for offer: OfferDefinition in catalog.manifest.offers:
		var initial: DronePresetDefinition = catalog.presets[catalog.manifest.initial_preset_id]
		store.data.owned = [initial.id, initial.frame_id, initial.motor_set_id, initial.propeller_set_id]
		store.data.credits = 10000
		var target := offer.preset_id if not offer.preset_id.is_empty() else offer.part_id
		var result := store.purchase(offer.id, offer.city_tag)
		check(result.ok and store.data.owned.has(target) and store.data.credits == 10000 - offer.price, "priced permanent purchase " + offer.id)
		credits = store.data.credits
		check(not store.purchase(offer.id, offer.city_tag).ok and store.data.credits == credits, "already-owned purchase cannot charge again " + offer.id)
	var next := store.data.duplicate(true)
	for kind: String in AchievementBook.TYPES:
		AchievementBook.completed(next, kind)
	for biome in catalog.biomes:
		AchievementBook.biome(next, biome.id, catalog)
	for index in 10:
		next.exploration.portals["test%d" % index] = true
	credits = next.credits
	check(store._commit(next).ok and store.data.credits == credits, "achievement unlocks grant no extra currency")
	var restored := ProgressStore.new(catalog, store.path)
	check(restored.data.achievements.unlocked.has("base.achievement.biomes") and restored.data.achievements.unlocked.has("base.achievement.types") and restored.data.achievements.unlocked.has("base.achievement.portals10"), "all-biome, all-type and ten-portal achievements persist")
	check(catalog.fingerprint() == fingerprint, "generation, completion and purchases do not mutate shared content")
	await ui(catalog)
	var report := {"kind": "automated task state, transactions, native static collisions and UI; not human flight", "seed": 271828, "failures": failed, "checks": checked, "sampled_instances": plans.size(), "instance_layers": terrain_count, "geometry": geometry_cases, "examples": {}}
	for kind: String in examples:
		var mission: MissionDefinition = examples[kind]
		var points: Array = []
		var normals: Array = []
		for point: Vector3 in mission.checkpoints:
			points.append([point.x, point.y, point.z])
		for gate_normal: Vector3 in mission.gate_normals:
			normals.append([gate_normal.x, gate_normal.y, gate_normal.z])
		report.examples[kind] = {"id": mission.id, "checkpoints": points, "gate_normals": normals, "rules": mission.challenge}
	var file := FileAccess.open(directory.path_join("gameplay.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("GAMEPLAY_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed > 0 else 0)

func ui(catalog: ContentCatalog) -> void:
	game = load("res://scripts/main.gd").new()
	root.add_child(game)
	await game._wait_for_world()
	game._set_paused(false)
	await create_timer(1).timeout
	game._set_paused(true)
	var cash: Dictionary = game.store.data.duplicate(true)
	cash.credits = 10000
	game.store._commit(cash)
	game._show_workshop()
	check(game.menu is Workshop, "real landed platform opens expanded shop")
	await process_frame
	check(game.unlock_notifications.visible and game.unlock_notifications.get_child_count() > 0 and game.unlock_notifications.get_canvas_layer_node().layer > game.canvas.layer, "portal unlock notification stays visible above the open service window")
	await capture("portal-unlock-above-service")
	if game.menu is Workshop:
		var workshop: Workshop = game.menu
		workshop.tabs.current_tab = 3
		workshop.shop_category.select(1)
		workshop.shop_category.item_selected.emit(1)
		await process_frame
		check(workshop.offer_buttons.size() == catalog.manifest.offers.size() and workshop.shop_cards.values().filter(func(card: Control): return card.visible).size() == 4, "shop kit category shows four purchasable complete kits")
		await capture("shop-kits")
		workshop.shop_category.select(3)
		workshop.shop_category.item_selected.emit(3)
		await process_frame
		check(workshop.shop_cards.values().filter(func(card: Control): return card.visible).size() == 3, "motor category hides unrelated products")
		await capture("shop-motors")
		var before: int = game.store.data.credits
		workshop.offer_buttons["base.offer.freestyle5.kit"].pressed.emit()
		check(game.store.data.owned.has("base.preset.freestyle5") and game.store.data.credits == before - 390, "production product button purchases the new complete kit transactionally")
		workshop.apply_requested.emit(game.assembler.from_preset("base.preset.freestyle5"), game.drone.tuning)
		check(game.store.data.build.frame_id == "base.frame.f_freestyle5" and is_equal_approx(game.drone.spec.max_thrust, 5.6), "new matching kit applies to the actual drone at a landed platform")
	game._close_menu()
	game._show_pause_menu()
	var pause: PauseMenu = game.menu
	pause.achievements_requested.emit()
	check(game.menu is AchievementsMenu and game.menu.rows.size() == catalog.manifest.achievements.size(), "production Esc menu opens complete achievement collection")
	await process_frame
	check(not game.unlock_notifications.visible, "unlock notifications wait rather than covering achievement/menu text")
	await capture("achievements")
	game._close_menu()
	var mission: MissionDefinition
	for candidate: MissionDefinition in game.missions.local_definitions(game._world_position()):
		if candidate.kind != "hold_interact":
			mission = candidate
			break
	if mission != null:
		await land_at(mission)
		game._perform_action("interact")
		check(game.store.data.tracked_mission == mission.id and game.store.mission_status(mission.id) == "active", "production E picks up a discovered non-beacon mission without opening map")
		await capture("field-task")
	for kind: String in ["race", "balloons", "orbit", "follow"]:
		var challenge: MissionDefinition = game.store.mission_definition(examples[kind].id)
		var pickup := challenge.pickup_points[0] if not challenge.pickup_points.is_empty() else challenge.acceptance_point()
		await land_at(challenge)
		game._perform_action("interact")
		check(game.store.data.tracked_mission == challenge.id, "actual E accepts and tracks physical " + kind + " entry")
		var vantage := challenge.checkpoints[0] - challenge.gate_normals[0] * 18 + Vector3.UP * 4 if kind == "race" else challenge.target_point + Vector3(22, 6, 22)
		game._debug_teleport(vantage)
		await wait_at(vantage)
		game.drone.camera.current = true
		var target := challenge.checkpoints[0] if kind == "race" else FlightChallengeRules.follow_point(challenge, 0) if kind == "follow" else challenge.target_point
		game.drone.camera.look_at(target - game.streamer.origin_offset)
		var desired: Basis = game.drone.camera.global_basis
		var tilt := Basis.from_euler(Vector3(deg_to_rad(float(game.drone.spec.camera_tilt)), 0, 0))
		game.drone.global_basis = desired * tilt.inverse()
		game.drone.camera.basis = tilt
		await process_frame
		check(game.challenge_view.actors.has(challenge.id), "live world renders " + kind + " challenge")
		await capture("challenge-" + kind)
		if kind in ["orbit", "follow"]:
			await camera_check(challenge)
	game.queue_free()
	await create_timer(0.2).timeout

func land_at(mission: MissionDefinition) -> void:
	game._debug_teleport(mission.acceptance_point() + Vector3.UP * 0.6)
	await wait_at(mission.acceptance_point())
	game.drone.global_basis = Basis.IDENTITY
	game._set_paused(false)
	for frame in 240:
		await physics_frame
		if game._docked_task_id() == mission.id:
			break
	check(game._docked_task_id() == mission.id, "real body settles onto task platform")
	game._set_paused(true)

func camera_check(mission: MissionDefinition) -> void:
	var target := FlightChallengeRules.follow_point(mission, 0) if mission.kind == "follow" else mission.target_point
	var radius := 8.0 if mission.kind == "follow" else (float(mission.challenge.radius_min) + float(mission.challenge.radius_max)) * 0.5
	var camera: Camera3D = game.drone.camera
	var original := camera.transform
	camera.global_position = target + Vector3.RIGHT * radius - game.streamer.origin_offset
	camera.look_at(target - game.streamer.origin_offset)
	await physics_frame
	var seen: Dictionary = game._challenge_camera(0)
	check(FlightChallengeRules.view_valid(mission, seen, target), "actual viewport camera sees unobstructed " + mission.kind + " target")
	var blocker := WorldGeometry.create_box(target + Vector3.RIGHT * radius * 0.5 - game.streamer.origin_offset, Vector3.ONE * 2, Color.GRAY)
	game.add_child(blocker)
	await physics_frame
	await physics_frame
	seen = game._challenge_camera(0)
	check(not FlightChallengeRules.view_valid(mission, seen, target), "real ray obstruction rejects " + mission.kind + " cinematic evidence")
	blocker.queue_free()
	await physics_frame
	camera.transform = original

func wait_at(point: Vector3) -> void:
	var began := Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec() + 12000
	while not game.streamer.collision_ready(point) and Time.get_ticks_msec() < deadline:
		await process_frame
	await physics_frame
	print("CHALLENGE_VIEW_READY_MS ", Time.get_ticks_msec() - began)
	check(game.streamer.collision_ready(point), "actual challenge viewpoint collision is ready")

func geometry(plans: Array[Dictionary], catalog: ContentCatalog) -> void:
	var selected := {}
	var generator := WorldGenerator.new(catalog, 271828)
	for p in plans:
		var key: String = p.kind + ("_forest" if p.biomes[0].provider_id == "base.generator.pine_valley" else "_desert" if p.biomes[0].provider_id == "base.generator.canyon" else "")
		if selected.has(key):
			continue
		var routes: Array = p.missions.filter(func(mission: MissionDefinition): return mission.kind == "race")
		if routes.is_empty():
			continue
		selected[key] = true
		var points := PackedVector3Array()
		for mission: MissionDefinition in routes:
			points.append_array(mission.checkpoints)
			if mission.challenge.has("spatial_revision"): points.append_array(mission.challenge.flight_path)
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		bounds = bounds.grow(8)
		var first := WorldGenerator.key_at(bounds.position)
		var last := WorldGenerator.key_at(bounds.end)
		var host := Node3D.new()
		root.add_child(host)
		var origin := points[0]
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				for z in range(first.z, last.z + 1):
					host.add_child(WorldGeometry.create_chunk(generator.generate(Vector3i(x, y, z)), origin))
		await physics_frame
		await physics_frame
		var space := host.get_world_3d().direct_space_state
		for mission: MissionDefinition in routes:
			var clear := true
			var body := BoxShape3D.new()
			body.size = Vector3(0.4, 0.3, 0.4)
			for index in mission.checkpoints.size():
				var center := mission.checkpoints[index] - origin
				var basis := FlightChallengeRules.gate_basis_for(mission, index)
				var half := float(mission.challenge.gate_half) - 0.35
				for a: float in [-1, -0.5, 0, 0.5, 1]:
					for b: float in [-1, -0.5, 0, 0.5, 1]:
						var query := PhysicsShapeQueryParameters3D.new()
						query.shape = body
						query.transform.origin = center + basis.x * a * half + basis.y * b * half
						var hit := space.intersect_shape(query, 1)
						if not hit.is_empty():
							print("COURSE_BLOCKED ", mission.id, " gate=", index, " offset=", Vector2(a, b), " center=", mission.checkpoints[index])
							clear = false
				if index > 0 and not mission.challenge.has("spatial_revision"):
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mission.checkpoints[index - 1] - origin, center))
					if not hit.is_empty():
						print("COURSE_LEG_BLOCKED ", mission.id, " gate=", index)
						clear = false
			if mission.challenge.has("spatial_revision"):
				var path: PackedVector3Array = mission.challenge.flight_path
				for index in range(1, path.size()):
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = body
					query.transform.origin = path[index - 1] - origin
					query.motion = path[index] - path[index - 1]
					if space.cast_motion(query)[0] < 1: print("SPATIAL_CURVE_BLOCKED ", mission.id, " ", index); clear = false
			check(clear, "actual generated collisions preserve gate apertures and route legs " + key + " " + mission.id)
			geometry_cases.append({"id": mission.id, "layer": key, "gates": mission.checkpoints.size(), "body_samples_per_gate": 25, "clear": clear})
		host.queue_free()
		await physics_frame
