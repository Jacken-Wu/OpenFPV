extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, name: String) -> void:
	if not value:
		failed += 1
		push_error("FAIL: " + name)
	else:
		print("PASS: " + name)

func wait_physics(frames: int) -> void:
	for _i in frames:
		await physics_frame

func run() -> void:
	var drone := FPVDrone.new()
	root.add_child(drone)
	drone.position = Vector3(0, 100, 0)
	await wait_physics(3)
	var hover := pow(drone.mass * 9.81 / (float(drone.spec.max_thrust) * 4.0), 1.0 / 1.55)
	drone.motor_forces.fill(drone.mass * 9.81 / 4.0)
	drone.controls = Vector4(0, 0, 0, hover)
	drone.linear_velocity = Vector3.ZERO
	var altitude := drone.position.y
	await wait_physics(120)
	print("Hover drift: %.4f m, thrust: %.4f N" % [drone.position.y - altitude, drone.total_thrust])
	check(absf(drone.position.y - altitude) < 0.2, "four-motor hover maintains altitude")
	drone.controls.x = 0.2
	await wait_physics(30)
	check((drone.basis.inverse() * drone.angular_velocity).z < -0.1, "positive roll banks right")
	drone.reset_drone(Vector3(0, 100, 0))
	await wait_physics(3)
	drone.controls = Vector4(0, 0.2, 0, hover)
	await wait_physics(30)
	check((drone.basis.inverse() * drone.angular_velocity).x < -0.1, "positive pitch tips forward")
	drone.reset_drone(Vector3(0, 100, 0))
	await wait_physics(3)
	drone.controls = Vector4(0, 0, 0.2, hover)
	await wait_physics(40)
	check((drone.basis.inverse() * drone.angular_velocity).y < -0.1, "positive yaw turns right")
	drone.reset_drone(Vector3(0, 100, 0))
	await wait_physics(3)
	drone.rotation.z = 0.3
	drone.controls = Vector4(0, 0, 0, hover)
	await wait_physics(60)
	check(absf(drone.rotation.z - 0.3) < 0.04, "Acro neutral does not auto-level")
	drone.freeze = true
	drone.stop_control()
	var paused_position := drone.position
	await wait_physics(120)
	check(drone.total_thrust == 0 and drone.position.is_equal_approx(paused_position), "pause stops control and freezes the body")
	drone.freeze = false
	var ground := WorldGeometry.create_box(Vector3(0, 0, 0), Vector3(20, 0.2, 20), Color.GRAY)
	root.add_child(ground)
	drone.reset_drone(Vector3(0, 2, 0))
	await wait_physics(150)
	check(drone.position.y > 0.1 and drone.position.y < 0.3 and drone.linear_velocity.length() < 0.5, "ground contact settles on collider")
	var wall := WorldGeometry.create_box(Vector3(0, 2, -8), Vector3(20, 8, 0.1), Color.GRAY)
	root.add_child(wall)
	drone.reset_drone(Vector3(0, 3, 0))
	await wait_physics(3)
	drone.linear_velocity = Vector3(0, 0, -60)
	await wait_physics(30)
	check(drone.position.z > -8, "60 m/s approach does not tunnel through thin wall")
	drone.freeze = true
	drone.global_transform = Transform3D(Basis.from_euler(Vector3(0.6, 0.8, -0.5)), Vector3(4, 100, 7))
	drone.linear_velocity = Vector3(8, 3, 2)
	drone.angular_velocity = Vector3(2, 3, 4)
	drone.rate_integral = Vector3.ONE
	drone.motor_forces.fill(2.0)
	var original_heading := Vector2(-drone.global_basis.z.x, -drone.global_basis.z.z).normalized()
	drone.reset_attitude()
	check(drone.global_position.is_equal_approx(Vector3(4, 100, 7)) and drone.global_basis.y.is_equal_approx(Vector3.UP), "in-place reset levels roll and pitch without relocating")
	var reset_heading := Vector2(-drone.global_basis.z.x, -drone.global_basis.z.z).normalized()
	check(reset_heading.is_equal_approx(original_heading), "in-place leveling preserves horizontal heading")
	check(drone.linear_velocity == Vector3.ZERO and drone.angular_velocity == Vector3.ZERO and drone.rate_integral == Vector3.ZERO and drone.motor_forces[0] == 0, "attitude reset clears both velocities and controller history")
	drone.shift_origin(Vector3(1024, 0, 0))
	var shifted_position := drone.global_position
	drone.freeze = false
	await wait_physics(4)
	check(drone.global_basis.y.is_equal_approx(Vector3.UP) and drone.angular_velocity.is_zero_approx() and not drone.reset_pending, "physics-step reset keeps the leveled attitude after unfreezing")
	check(absf(drone.global_position.x - shifted_position.x) < 0.001 and absf(drone.global_position.z - shifted_position.z) < 0.001, "origin shifts also move a queued reset without teleporting back")
	drone.rotation = Vector3(PI * 0.5, 1.0, 0.0)
	drone.reset_attitude()
	check(drone.global_basis.y.is_equal_approx(Vector3.UP) and drone.global_transform.is_finite(), "vertical nose attitude has a finite heading fallback")
	ground.queue_free()
	wall.queue_free()
	var catalog := ContentCatalog.new()
	var assembler := DroneAssembler.new(catalog)
	var builds: Array[Dictionary] = [assembler.from_preset("base.preset.explorer5"), assembler.from_preset("base.preset.light35"), assembler.from_preset("base.preset.explorer5")]
	builds[2].propeller_set_id = "base.prop.p5_smooth"
	var velocities: Array[float] = []
	for build: Dictionary in builds:
		drone.reset_drone(Vector3(0, 100, 0))
		drone.apply_spec(assembler.resolve(build, [], true).spec)
		await wait_physics(3)
		drone.linear_velocity = Vector3.ZERO
		drone.controls = Vector4(0, 0, 0, 1)
		await wait_physics(36)
		velocities.append(drone.linear_velocity.y)
	print("Full-throttle 300ms vertical speeds: ", velocities)
	check(absf(velocities[0] - velocities[1]) > 0.2 and velocities[0] > velocities[2] + 0.2, "preset and propeller differences affect actual physical response")
	drone.queue_free()
	await process_frame
	print("FLIGHT_TESTS: %d failure(s)" % failed)
	quit(1 if failed else 0)
