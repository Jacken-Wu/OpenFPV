extends SceneTree
var failed := 0
var checked := 0
var drone: FPVDrone
var directory := "res://../.local/test-results/handling"

func _initialize() -> void:
	Engine.max_fps = 0
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1
func frames(count: int) -> void:
	for index in count:
		await physics_frame
func terrain_box(area: Rect2, slope: float = 0) -> Node3D:
	var vertices := PackedVector3Array()
	for point: Vector2 in [area.position, area.position + Vector2(0, area.size.y), area.position + Vector2(area.size.x, 0), area.end]:
		vertices.append(Vector3(point.x, point.x * slope, point.y))
	var normal := Vector3(-slope, 1, 0).normalized()
	var mesh := {"id": "test/terrain", "primitive": "terrain", "vertices": vertices, "normals": PackedVector3Array([normal, normal, normal, normal]), "colors": PackedColorArray([Color.GRAY, Color.GRAY, Color.GRAY, Color.GRAY]), "indices": PackedInt32Array([0, 1, 2, 1, 3, 2]), "surfaces": PackedInt32Array([0, 0]), "surface_names": ["concrete"], "solid": true}
	return WorldGeometry.create_chunk({"key": Vector3i.ZERO, "objects": [mesh]}, Vector3.ZERO)

func response_metrics(axis: int, damped: bool, spec: Dictionary) -> Dictionary:
	drone.apply_spec(spec)
	var tuning := FlightTuning.defaults()
	tuning.gravity = 0
	tuning.air_drag = 0
	tuning.angular_drag = 0
	if not damped:
		for role in FlightTuning.AXES:
			tuning.pid[role].d = 0
			tuning.pid[role].p = 12 if role == "yaw" else 18
	drone.apply_tuning(tuning)
	drone.reset_drone(Vector3(0, 100, 0))
	await frames(3)
	drone.controls = Vector4(0, 0, 0, 0.55)
	drone.controls[axis] = 1
	await frames(45)
	drone.controls[axis] = 0
	var reverse_peak := 0.0
	var tail := 0.0
	var integrated_error := 0.0
	for index in 180:
		await physics_frame
		var rates := -(drone.global_basis.inverse() * drone.angular_velocity)
		var rate: float = rates[[2, 0, 1][axis]]
		reverse_peak = maxf(reverse_peak, -rate)
		integrated_error += absf(rate) / 120.0
		if index >= 60:
			tail = maxf(tail, absf(rate))
	return {"reverse_peak": reverse_peak, "tail": tail, "integrated_error": integrated_error}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var surface := terrain_box(Rect2(-64, -64, 128, 128))
	root.add_child(surface)
	drone = FPVDrone.new()
	root.add_child(drone)
	var tuning := FlightTuning.defaults()
	tuning.gravity = 0
	tuning.air_drag = 0
	tuning.angular_drag = 0
	drone.apply_tuning(tuning)
	for angle: Vector3 in [Vector3.ZERO, Vector3(0.8, 0.4, -0.7), Vector3(PI, 0, 0), Vector3(0, 0, PI / 2)]:
		for speed: Vector3 in [Vector3(0, -120, 0), Vector3(80, -180, 100), Vector3(100, -600, -100), Vector3(0, -1200, 0)]:
			for height: float in [0.4, 0.8, 1.3, 2.3, 3.7]:
				drone.reset_drone(Vector3(0, height, 0))
				await frames(3)
				drone.rotation = angle
				await frames(2)
				drone.linear_velocity = speed
				var lowest := height
				for index in 10:
					await physics_frame
					lowest = minf(lowest, drone.position.y)
				check(lowest >= -0.01, "thin terrain collision angle%s velocity%s height%.1f" % [angle, speed, height])
	check(drone.swept_impacts > 0, "actual physical impacts exercise additional swept collision protection")
	var camera_catalog := ContentCatalog.new()
	var camera_assembler := DroneAssembler.new(camera_catalog)
	for preset_id: String in ["base.preset.explorer5", "base.preset.light35"]:
		drone.apply_spec(camera_assembler.resolve(camera_assembler.from_preset(preset_id), [], true).spec)
		for speed: float in [120, 300]:
			drone.reset_drone(Vector3(0, 2.3, 0))
			await frames(3)
			drone.rotation.x = -1.4
			await frames(2)
			drone.linear_velocity = Vector3(0, -speed, 0)
			var lowest_camera := 10.0
			var lowest_near_plane := 10.0
			for index in 30:
				await physics_frame
				lowest_camera = minf(lowest_camera, drone.camera.global_position.y)
				var half_height := tan(deg_to_rad(drone.camera.fov) * 0.5) * drone.camera.near
				var aspect := float(root.size.x) / maxf(1, root.size.y)
				for x: float in [-1, 1]:
					for y: float in [-1, 1]:
						var corner: Vector3 = drone.camera.global_transform * Vector3(x * half_height * aspect, y * half_height, -drone.camera.near)
						lowest_near_plane = minf(lowest_near_plane, corner.y)
			check(lowest_camera > 0.04 and lowest_near_plane >= 0, "FPV camera and all four near-plane corners stay above ground after tilted impact %s %.0fm/s" % [preset_id, speed])
	surface.queue_free()
	await frames(3)
	# Sloped triangles, negative coordinates and a real generator mesh.
	var slope := terrain_box(Rect2(-64, -64, 128, 128), 0.4)
	root.add_child(slope)
	for point: Vector2 in [Vector2(-32, -17), Vector2(17, 32), Vector2.ZERO]:
		drone.reset_drone(Vector3(point.x, point.x * 0.4 + 2.3, point.y))
		await frames(3)
		drone.rotation = Vector3(0.8, 0.4, -0.7)
		await frames(2)
		drone.linear_velocity = Vector3(30, -400, 10)
		var clear := true
		for index in 12:
			await physics_frame
			clear = clear and drone.position.y - drone.position.x * 0.4 > -0.02
		check(clear, "sloped triangle surface blocks high-speed tilted impact at " + str(point))
	slope.queue_free()
	await frames(3)
	var catalog := ContentCatalog.new()
	var generator := WorldGenerator.new(catalog, 271828)
	var layout: BiomeWorld = generator.regions
	var point := Vector2(-1995, 1213)
	var terrain_height := BiomeTerrain.new(layout.field, point).sample(point.x, point.y)
	var key := WorldGenerator.key_at(Vector3(point.x, terrain_height, point.y))
	var production := Node3D.new()
	root.add_child(production)
	for x in range(key.x - 1, key.x + 2):
		for z in range(key.z - 1, key.z + 2):
			for y in [-1, 0]:
				var descriptor := generator.generate(Vector3i(x, y, z))
				descriptor.objects = descriptor.objects.filter(func(object: Dictionary): return object.get("primitive", "") == "terrain")
				production.add_child(WorldGeometry.create_chunk(descriptor, Vector3.ZERO))
	drone.reset_drone(Vector3(point.x, terrain_height + 2.3, point.y))
	await frames(4)
	drone.rotation = Vector3(0.8, 0.4, -0.7)
	await frames(2)
	drone.linear_velocity = Vector3(0, -600, 0)
	var production_clear := true
	for index in 20:
		await physics_frame
		var at := drone.global_position
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 100, at - Vector3.UP * 100, 1, [drone.get_rid()])
		var hit := production.get_world_3d().direct_space_state.intersect_ray(ray)
		production_clear = production_clear and not hit.is_empty() and drone.position.y >= float(hit.position.y) - 0.1
	check(production_clear, "production generated terrain at negative coordinates resists a600m/s impact")
	production.queue_free()
	await frames(3)
	var opening := Node3D.new()
	root.add_child(opening)
	for area: Rect2 in [Rect2(-64, -64, 56, 128), Rect2(8, -64, 56, 128), Rect2(-8, -64, 16, 56), Rect2(-8, 8, 16, 56)]:
		opening.add_child(terrain_box(area))
	drone.reset_drone(Vector3(0, 2.3, 0))
	await frames(4)
	drone.linear_velocity = Vector3(0, -120, 0)
	await frames(30)
	check(drone.position.y < -20, "real16m shaft remains open; collision guard never clamps world height")
	opening.queue_free()
	await frames(3)
	var report: Array[Dictionary] = []
	var assembler := DroneAssembler.new(catalog)
	for preset_id: String in ["base.preset.explorer5", "base.preset.light35"]:
		var spec: Dictionary = assembler.resolve(assembler.from_preset(preset_id), [], true).spec
		for axis in 3:
			var pi_result: Dictionary = await response_metrics(axis, false, spec)
			var pid_result: Dictionary = await response_metrics(axis, true, spec)
			print("PID_RESPONSE ", preset_id, " axis=", axis, " PI=", JSON.stringify(pi_result), " PID=", JSON.stringify(pid_result))
			report.append({"preset": preset_id, "axis": FlightTuning.AXES[axis], "pi": pi_result, "pid": pid_result})
			check(pid_result.reverse_peak < pi_result.reverse_peak * 0.5, "D damping cuts fast-stick recenter reversal by at least half " + preset_id + " " + FlightTuning.AXES[axis])
			check(pid_result.tail < 0.04 and pid_result.integrated_error < pi_result.integrated_error, "PID settles without sustained shake " + preset_id + " " + FlightTuning.AXES[axis])
	var output := FileAccess.open(directory.path_join("pid-response.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	drone._reset_rate_history()
	drone.saturation_sign = Vector3.ONE
	drone._rate_acceleration(Vector3.ONE * 10, Vector3.ZERO, 0.01)
	check(drone.rate_integral == Vector3.ZERO, "motor saturation blocks further integral windup")
	drone._rate_acceleration(Vector3.ONE * -10, Vector3.ZERO, 0.01)
	check(drone.rate_integral.x < 0, "opposite rate error can unwind saturation")
	drone._reset_rate_history()
	drone._rate_acceleration(Vector3.ZERO, Vector3.ZERO, 0.01)
	drone._rate_acceleration(Vector3.ONE * 10, Vector3.ZERO, 0.01)
	check(drone.rate_derivative == Vector3.ZERO, "a target stick step does not produce derivative kick")
	drone.queue_free()
	await process_frame
	print("HANDLING_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
