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
	drone.armed = true
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
	drone.armed = true
	drone.controls = Vector4(0, 0.2, 0, hover)
	await wait_physics(30)
	check((drone.basis.inverse() * drone.angular_velocity).x < -0.1, "positive pitch tips forward")
	drone.reset_drone(Vector3(0, 100, 0))
	await wait_physics(3)
	drone.armed = true
	drone.controls = Vector4(0, 0, 0.2, hover)
	await wait_physics(40)
	check((drone.basis.inverse() * drone.angular_velocity).y < -0.1, "positive yaw turns right")
	drone.reset_drone(Vector3(0, 100, 0))
	await wait_physics(3)
	drone.rotation.z = 0.3
	drone.armed = true
	drone.controls = Vector4(0, 0, 0, hover)
	await wait_physics(60)
	check(absf(drone.rotation.z - 0.3) < 0.04, "Acro neutral does not auto-level")
	drone.armed = false
	await wait_physics(120)
	check(drone.total_thrust < 0.001, "disarmed motors spool down")
	drone.queue_free()
	await process_frame
	print("FLIGHT_TESTS: %d failure(s)" % failed)
	quit(1 if failed else 0)
