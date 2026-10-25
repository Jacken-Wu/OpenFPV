extends SceneTree
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/expansion"
var examples := {}
var report := {}
var signals_seen: Array[String] = []
var host: Node3D
var camera: Camera3D

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")

func check(value: bool, description: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", description)

func view(point: Vector3, target: Vector3, visible: bool = true) -> Dictionary:
	return {"origin": point, "forward": (target - point).normalized(), "clear": visible, "in_view": visible}

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			directory = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	var fingerprint := catalog.fingerprint()
	check(catalog.errors.is_empty() and catalog.biomes.size() == 15, "fifteen validated biome definitions include eight extensions")
	var world := BiomeWorld.new(catalog, 271828)
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			if site.biome.parameters.get("extension", false) and not examples.has(site.biome.parameters.terrain_style):
				examples[site.biome.parameters.terrain_style] = site
	check(examples.size() == 8, "extension lottery generates every new geography")
	compatibility(catalog)
	follow(catalog)
	await structures()
	await geography(catalog, world)
	await audio_and_events(catalog)
	check(fingerprint == catalog.fingerprint(), "generation and tests never mutate shared definitions")
	report.checks = checked
	report.failures = failed
	var file := FileAccess.open(directory.path_join("expansion.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("EXPANSION_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)

func compatibility(catalog: ContentCatalog) -> void:
	var old_manifest := catalog.manifest.duplicate() as ContentManifest
	old_manifest.biomes = []
	for biome: BiomeDefinition in catalog.biomes:
		if not biome.parameters.get("extension", false):
			old_manifest.biomes.append(biome)
	var legacy := ContentCatalog.new(old_manifest)
	var old := BiomeField.new(legacy, 271828)
	var current := BiomeField.new(catalog, 271828)
	var same := true
	for x in range(-3, 4):
		for z in range(-3, 4):
			same = same and old.surface_site(Vector2i(x, z)).biome.id == current.surface_site(Vector2i(x, z)).biome.id
	check(same, "old climate choices remain identical in all 49 core cells")
	var store := ProgressStore.new(catalog, "user://tests/expansion_%d/progress.json" % Time.get_ticks_usec())
	var before: Dictionary = store.data.duplicate(true)
	store.data.erase("extension_radius")
	store.data.exploration.visited["surface:17:-9"] = true
	store.data.exploration.mapped["sky:-12:7"] = true
	store.prepare_geography()
	check(store.data.extension_radius >= 27 and store.data.credits == before.credits and store.data.owned == before.owned, "upgrade protects all explored layers with a three-cell buffer and retains ownership")
	var protected := BiomeField.new(catalog, 271828, int(store.data.extension_radius))
	check(not protected.surface_site(Vector2i(17, -9)).biome.parameters.get("extension", false), "explored outer surface cannot become a new biome after restart")
	check(store._commit(store.data).ok and int(ProgressStore.new(catalog, store.path).data.extension_radius) == int(store.data.extension_radius), "preserved geography boundary survives saved reload")
	var outer_world := BiomeWorld.new(catalog, 271828, int(store.data.extension_radius))
	var baseline := BiomeWorld.new(legacy, 271828, 1000000).plan("surface", Vector2i(17, -9))
	var preserved := outer_world.plan("surface", Vector2i(17, -9))
	var unchanged := JSON.stringify(baseline.stations) == JSON.stringify(preserved.stations)
	for task: MissionDefinition in baseline.missions:
		if task.kind == "race":
			var found: MissionDefinition
			for candidate: MissionDefinition in preserved.missions:
				if candidate.id == task.id:
					found = candidate
			unchanged = unchanged and found != null and task.checkpoints == found.checkpoints
	check(unchanged, "protected outer station positions and saved race checkpoint identities match legacy geography")
	var outer := BiomeLocator.new(outer_world).locate("alpine", Vector3.ZERO)
	check(outer.get("ok", false) and maxi(absi(outer.key.x), absi(outer.key.y)) >= int(store.data.extension_radius), "new biomes remain locatable beyond an upgraded large exploration core")
	var finite := true
	for seed_value: int in [42, 314159]:
		var other := BiomeField.new(catalog, seed_value)
		var kinds := {}
		for x in range(-7, 8):
			for z in range(-7, 8):
				var site := other.surface_site(Vector2i(x, z))
				if site.biome.parameters.get("extension", false):
					kinds[site.biome.parameters.terrain_style] = true
					var sampler := BiomeTerrain.new(other, site.anchor)
					var y := sampler.sample(site.anchor.x, site.anchor.y)
					finite = finite and is_finite(y) and y > -64 and y < 230
		finite = finite and kinds.size() == 8
	check(finite, "all eight new terrains recur with finite bounded heights in two further seeds")

func follow(catalog: ContentCatalog) -> void:
	var world := BiomeWorld.new(catalog, 271828)
	var mission: MissionDefinition
	for x in range(-3, 4):
		for z in range(-3, 4):
			if mission != null:
				continue
			for task: MissionDefinition in world.plan("surface", Vector2i(x, z)).missions:
				if task.kind == "follow":
					mission = task
	check(mission != null and mission.checkpoints.size() == 12, "follow uses twelve smooth varied control points")
	var state := {"status": "active", "kind": "follow"}
	var far := FlightChallengeRules.follow_point(mission, 0) + Vector3.RIGHT * 100
	check(FlightChallengeRules.step(mission, state, far, far, 0.1, view(far, mission.target_point)).get("elapsed", 0) == 0, "remote acceptance waits until within fifty metres")
	var exact := state.duplicate(true)
	var poor := state.duplicate(true)
	for index in 300:
		var target := FlightChallengeRules.follow_point(mission, (index + 1) * 0.1)
		var point := target + Vector3.RIGHT * (30 if index < 240 else 60)
		exact = FlightChallengeRules.step(mission, exact, point, point, 0.1, view(point, target, index >= 60))
		point = target + Vector3.RIGHT * 30
		poor = FlightChallengeRules.step(mission, poor, point, point, 0.1, view(point, target, index < 237))
	check(FlightChallengeRules.finished(mission, exact), "independent eighty-percent visibility and range both pass at thirty seconds")
	check(not FlightChallengeRules.finished(mission, poor), "seventy-nine percent visibility cannot pass despite perfect range")
	for index in 100:
		var target := FlightChallengeRules.follow_point(mission, float(poor.elapsed) + 0.1)
		var point := target + Vector3.RIGHT * 30
		poor = FlightChallengeRules.step(mission, poor, point, point, 0.1, view(point, target))
	check(FlightChallengeRules.finished(mission, poor) and poor.elapsed > 30, "continued filming recovers coverage without resetting or expiring")
	var invalid := exact.duplicate(true)
	invalid.visible_time = invalid.elapsed + 1
	check(not FlightChallengeRules.valid_state(mission, invalid), "coverage cannot exceed recorded duration")
	invalid.visible_time = NAN
	check(not FlightChallengeRules.valid_state(mission, invalid), "nonfinite coverage is rejected")
	var minimum := INF
	var maximum := 0.0
	var height_low := INF
	var height_high := -INF
	for index in 600:
		var a := FlightChallengeRules.follow_point(mission, index * 0.1)
		var b := FlightChallengeRules.follow_point(mission, (index + 1) * 0.1)
		minimum = minf(minimum, a.distance_to(b) / 0.1)
		maximum = maxf(maximum, a.distance_to(b) / 0.1)
		height_low = minf(height_low, a.y)
		height_high = maxf(height_high, a.y)
	check(minimum > 3 and maximum < 25 and height_high - height_low > 10, "target moves faster with smooth turns and vertical variation")
	report.follow_speed_mps = [minimum, maximum]
	var store := ProgressStore.new(catalog, "user://tests/follow016_%d/progress.json" % Time.get_ticks_usec())
	store.accept_mission(mission.id)
	var controller := MissionController.new(catalog, store, MapNavigation.new(4))
	var target := FlightChallengeRules.follow_point(mission, 0)
	var point := target + Vector3.RIGHT * 20
	controller.update_objective(point, 0, 0.02, false, false, view(point, target))
	for index in 65:
		controller.update_objective(point, 0, 0.02, false, false, view(point, target, false))
	var saved := ProgressStore.new(catalog, store.path)
	check(float(saved.data.assignments[mission.id].get("elapsed", 0)) >= 0.9 and float(saved.data.assignments[mission.id].get("visible_time", 0)) == 0, "even bad footage time commits and survives restart within checkpoint interval")
	var elapsed: float = controller.runtime_state.elapsed
	controller.update_objective(point, 0, 5, false, true, view(point, target))
	check(is_equal_approx(controller.runtime_state.elapsed, elapsed), "pause stops recording and target movement")
	var old_state: Dictionary = store.data.assignments[mission.id].duplicate(true)
	old_state.erase("visible_time")
	old_state.erase("near_time")
	old_state.distance = 20
	store.data.assignments[mission.id] = old_state
	store._commit(store.data)
	saved = ProgressStore.new(catalog, store.path)
	check(saved.data.assignments[mission.id].elapsed == 0 and saved.data.assignments[mission.id].visible_time == 0 and saved.mission_status(mission.id) == "active", "old active follow changes only its current take; mission remains accepted")

func setup_view() -> void:
	host = Node3D.new()
	root.add_child(host)
	camera = Camera3D.new()
	host.add_child(camera)
	camera.current = true
	camera.far = 3000
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	host.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("8ca9b5")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bcc9ce")
	environment.environment.ambient_light_energy = 0.65
	host.add_child(environment)

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "capture " + name)

func structures() -> void:
	setup_view()
	var cases := {"open_house": [Vector3(0, 3, -14), Vector3(0, 3, 14)], "construction": [Vector3(0, 2, 0), Vector3(0, 40, 0)], "pipe_stack": [Vector3(-3, 3, -9), Vector3(-3, 3, 9)], "tri_billboard": [Vector3(0, 1, 0), Vector3(0, 15, 0)], "mega_ruins": [Vector3(0, 10, -40), Vector3(0, 10, 40)], "rock_arch": [Vector3(0, 10, -12), Vector3(0, 10, 12)], "ice_arch": [Vector3(0, 10, -12), Vector3(0, 10, 12)], "lava_arch": [Vector3(0, 10, -12), Vector3(0, 10, 12)], "playground": [Vector3(4, 2.8, -3), Vector3(4, 2.8, 13)]}
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * 0.6
	for kind: String in cases:
		var objects := Architecture.build(kind, "test/" + kind, Vector3.ZERO)
		var node := WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": objects}, Vector3.ZERO)
		host.add_child(node)
		await physics_frame
		await physics_frame
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = cases[kind][0]
		query.motion = cases[kind][1] - cases[kind][0]
		check(host.get_world_3d().direct_space_state.cast_motion(query)[0] > 0.99, "real body passes the intended opening of " + kind)
		camera.position = Vector3(48, 37, 55) if kind != "mega_ruins" else Vector3(80, 65, 95)
		camera.look_at(Vector3(0, 12 if kind == "construction" else 5, 0))
		await screenshot("structure-" + kind)
		node.queue_free()
		await physics_frame
	host.queue_free()
	await physics_frame

func geography(catalog: ContentCatalog, world: BiomeWorld) -> void:
	report.biomes = {}
	var generator := WorldGenerator.new(catalog, 271828)
	for kind: String in examples:
		var site: Dictionary = examples[kind]
		var plan := world.plan("surface", site.key)
		check(plan.missions.size() >= 2 and plan.missions.size() <= 5 and not plan.stations.is_empty(), "new biome keeps platform and bounded tasks " + kind)
		var sampler := BiomeTerrain.new(world.field, site.anchor)
		var minimum := INF
		var maximum := -INF
		for x in range(-150, 151, 30):
			for z in range(-150, 151, 30):
				var y := sampler.sample(site.anchor.x + x, site.anchor.y + z)
				minimum = minf(minimum, y)
				maximum = maxf(maximum, y)
		check(minimum > -64 and maximum < 230 and maximum - minimum > 0.5, "distinct bounded terrain relief " + kind)
		var pads := true
		for a: MissionDefinition in plan.missions:
			pads = pads and not a.pickup_platform.is_empty()
			for b: MissionDefinition in plan.missions:
				if a != b:
					pads = pads and a.acceptance_point().distance_to(b.acceptance_point()) >= 47.99
		check(pads, "new terrain task pads stay separated " + kind)
		setup_view()
		var origin := Vector3(site.anchor.x, 0, site.anchor.y)
		var center := Vector3(site.anchor.x, sampler.sample(site.anchor.x, site.anchor.y), site.anchor.y)
		var key := WorldGenerator.key_at(center)
		var meshes := 0
		var loaded := {}
		for x in range(-1, 2):
			for z in range(-1, 2):
				for y in range(-1, 4):
					var data := generator.generate(Vector3i(key.x + x, y, key.z + z))
					loaded[data.key] = true
					meshes += data.objects.filter(func(value: Dictionary): return value.get("primitive", "") == "terrain" and "/terrain/" in value.id).size()
					host.add_child(WorldGeometry.create_chunk(data, origin))
		await physics_frame
		await physics_frame
		var space := host.get_world_3d().direct_space_state
		# The analytical field is triangulated at 4m intervals; curved volcano
		# crater bottoms can differ by more than half a metre from interpolation.
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center - origin + Vector3.UP * 4, center - origin - Vector3.UP * 5))
		check(meshes >= 9 and not hit.is_empty(), "production chunks own high terrain and actual ground collision " + kind)
		var mission: MissionDefinition = plan.missions[0]
		var pad := mission.acceptance_point()
		var pad_key := WorldGenerator.key_at(pad)
		for y in range(-1, pad_key.y + 2):
			var chunk := Vector3i(pad_key.x, y, pad_key.z)
			if not loaded.has(chunk):
				host.add_child(WorldGeometry.create_chunk(generator.generate(chunk), origin))
		await physics_frame
		await physics_frame
		var pad_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pad - origin + Vector3.UP, pad - origin - Vector3.UP * 2))
		check(not pad_hit.is_empty() and absf(float(pad_hit.position.y) - float(mission.pickup_platform.top)) < 0.08, "new biome reception pad is exposed and landable " + kind)
		camera.position = center - origin + Vector3(110, 100, 125)
		camera.look_at(center - origin)
		await screenshot("biome-" + kind)
		report.biomes[kind] = {"key": [site.key.x, site.key.y], "height_range": [minimum, maximum], "landmarks": plan.landmarks.map(func(value: Dictionary): return value.kind), "tasks": plan.missions.size(), "terrain_meshes": meshes}
		host.queue_free()
		await physics_frame

func audio_and_events(catalog: ContentCatalog) -> void:
	var mixer := GameAudioMixer.new()
	root.add_child(mixer)
	var settings := GameAudioSettings.defaults()
	settings.music = 0.0
	mixer.apply(settings)
	var audio := GameEventAudio.new()
	root.add_child(audio)
	var capture: AudioEffectCapture
	if DisplayServer.get_name() != "headless":
		capture = AudioEffectCapture.new()
		capture.buffer_length = 3
		AudioServer.add_bus_effect(0, capture)
	for cue: String in GameEventAudio.CUES:
		var stream: AudioStreamWAV = audio.streams[cue]
		check(stream.get_length() > 0.15 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.data.decode_s16(0) == 0, "original finite enveloped event sound " + cue)
		stream.save_to_wav(directory.path_join(cue + ".wav"))
		if capture != null:
			capture.clear_buffer()
			audio.play_event(cue)
			await create_timer(stream.get_length() + 0.15).timeout
			var peak := 0.0
			for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
				peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
			check(peak > 0.01 and peak < 0.9, "native audible event output " + cue)
	if capture != null:
		audio.play_event("portal")
		audio.play_event("achievement")
		audio.play_event("achievement")
		audio.play_event("region")
		check(audio.current == "portal" and audio.pending == ["achievement", "region"], "simultaneous unlocks queue once instead of overlapping voices")
		await create_timer(0.8).timeout
		check(audio.current == "achievement", "queued achievement plays after portal cue finishes")
		await create_timer(1.3).timeout
		settings.effects = 0.0
		mixer.apply(settings)
		await create_timer(0.15).timeout
		capture.clear_buffer()
		audio.play_event("achievement")
		await create_timer(0.9).timeout
		var muted := true
		for frame: Vector2 in capture.get_buffer(capture.get_frames_available()):
			muted = muted and frame.length() < 0.0001
		check(muted, "Effects zero silences new cues at the actual Master output")
		AudioServer.remove_bus_effect(0, AudioServer.get_bus_effect_count(0) - 1)
	var store := ProgressStore.new(catalog, "user://tests/events016_%d/progress.json" % Time.get_ticks_usec())
	store.feedback.connect(func(event: String): signals_seen.append(event))
	store.unlocked.connect(func(category: String, _title: String): signals_seen.append(category))
	var portal: String = store.regions.plan("surface", Vector2i.ZERO).stations[0].id
	store.writable = false
	store.unlock_portal(portal)
	check(signals_seen.is_empty(), "failed portal save emits no unlock sound event")
	store.writable = true
	store.unlock_portal(portal)
	var count := signals_seen.size()
	store.unlock_portal(portal)
	check(signals_seen.has("portal") and signals_seen.size() == count, "portal sound event occurs once after commit")
	var mission: MissionDefinition = store.regions.plan("surface", Vector2i.ZERO).missions[0]
	store.writable = false
	store.accept_mission(mission.id)
	check(signals_seen.size() == count, "failed acceptance emits no cue")
	store.writable = true
	store.accept_mission(mission.id)
	check(signals_seen.has("accept"), "accepted mission emits success cue")
	var next: Dictionary = store.data.duplicate(true)
	for biome: BiomeDefinition in catalog.biomes:
		AchievementBook.biome(next, biome.id, catalog)
	store._commit(next)
	check(signals_seen.has("achievement"), "new achievement emits its earcon event after successful persistent award")
	count = signals_seen.size()
	store.writable = false
	store.complete_relay("audio-probe", "maintenance.relay", "industrial")
	check(signals_seen.size() == count, "failed completion does not emit success audio")
	store.writable = true
	store.complete_relay("audio-probe", "maintenance.relay", "industrial")
	check(signals_seen.has("complete"), "ordinary mission completion emits success event")
	audio.queue_free()
	mixer.queue_free()
	await create_timer(0.15).timeout
