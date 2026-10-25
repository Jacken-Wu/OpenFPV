extends SceneTree

var failed := 0

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func _initialize() -> void:
	var catalog := ContentCatalog.new()
	check(catalog.errors.is_empty(), "content references and parameter contracts: " + str(catalog.errors))
	var assembler := DroneAssembler.new(catalog)
	var store := ProgressStore.new(catalog, "user://tests/session_" + str(Time.get_ticks_usec()) + "/progress.json")
	var build := assembler.from_preset(catalog.manifest.initial_preset_id)
	var original := JSON.stringify(catalog.parts[build.frame_id].tuning)
	var normal := assembler.resolve(build, store.data.owned)
	check(normal.ok and normal.spec.mass > 0 and normal.spec.thrust_weight > 2, "assemble initial owned preset")
	var invalid := build.duplicate(true)
	invalid.motor_set_id = "base.motor.m35"
	check(not assembler.resolve(invalid, [], true).ok, "reject incompatible mount and propulsion map")
	invalid = build.duplicate(true)
	invalid.tuning = {"frame": {"camera_mount_tilt_deg": 46.0}}
	check(not assembler.resolve(invalid, store.data.owned).ok, "reject tuning outside bounded range")
	var rule: Dictionary = catalog.parts[build.frame_id].tuning.camera_mount_tilt_deg
	check(not DroneAssembler.valid_tuning(NAN, rule) and not DroneAssembler.valid_tuning(INF, rule) and not DroneAssembler.valid_tuning(20.5, rule), "reject NaN, infinity and fractional step")
	check(not assembler.resolve(assembler.from_preset("base.preset.light35"), store.data.owned).ok, "locked preset cannot bypass ownership")
	check(JSON.stringify(catalog.parts[build.frame_id].tuning) == original, "assembly does not mutate shared resources")
	check(not store.complete_relay("relay", "maintenance.relay", "garden").ok and store.data.credits == 0, "city and mission conditions both required")
	check(store.complete_relay("relay", "maintenance.relay", "industrial").ok and store.data.credits == 60, "atomic relay grant")
	check(store.complete_relay("relay", "maintenance.relay", "industrial").ok and store.data.credits == 60, "repeat mission cannot grant twice")
	check(assembler.resolve(assembler.from_preset("base.preset.light35"), store.data.owned).ok, "reward includes complete flyable light kit")
	var budget := store.data.duplicate(true)
	budget.credits += 150 # Saved wallet fixture; one reduced relay reward no longer funds a prop set.
	store._commit(budget)
	check(store.purchase("base.offer.smooth", "industrial").ok and store.data.credits == 60, "purchase permanently unlocks propellers")
	check(not store.purchase("base.offer.smooth", "industrial").ok and store.data.credits == 60, "repeat purchase cannot spend twice")
	check(store.save_build(build).ok, "save valid equipment configuration")
	var restored := ProgressStore.new(catalog, store.path)
	check(restored.data == JSON.parse_string(JSON.stringify(store.data)), "restart restores entire progression snapshot")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("corrupt")
	file.close()
	var recovered := ProgressStore.new(catalog, store.path)
	check(recovered.writable and recovered.data.credits == 60 and not recovered.warning.is_empty(), "corrupt main recovers valid backup")
	var blocked := ProgressStore.new(catalog, "res://project.godot/blocked.json")
	check(not blocked.complete_relay("relay", "maintenance.relay", "industrial").ok and blocked.data.credits == 0, "failed persistence never exposes uncommitted rewards")
	var duplicate_manifest := catalog.manifest.duplicate(true) as ContentManifest
	duplicate_manifest.parts.append(duplicate_manifest.parts[0])
	check(not ContentCatalog.new(duplicate_manifest).errors.is_empty(), "duplicate content IDs rejected")
	print("CONTENT_RESULT failures=", failed)
	quit(1 if failed else 0)
