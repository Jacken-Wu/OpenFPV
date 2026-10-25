class_name FPVDrone
extends RigidBody3D
## Rate controller and four lagged motors; all hardware enters through one resolved spec.

var controls := Vector4.ZERO
var tuning := FlightTuning.defaults()
var spec: Dictionary = {}
var camera: Camera3D
var motor_forces := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var rate_integral := Vector3.ZERO
var previous_rate := Vector3.ZERO
var rate_derivative := Vector3.ZERO
var rate_history_valid := false
var saturation_sign := Vector3.ZERO
var swept_impacts := 0
var contact_serial := 0
var total_thrust := 0.0
var spawn_point := Vector3(0, 3, 16)
var visual: Node3D
var collision: CollisionShape3D
var reset_pending := false
var reset_transform := Transform3D.IDENTITY
var paused_linear_velocity := Vector3.ZERO
var paused_angular_velocity := Vector3.ZERO
var motion_restore_pending := false
const MAX_ALTITUDE := 300.0
const SOFT_ALTITUDE := 280.0
const FPV_CAMERA_CLEARANCE := 0.07
var altitude_cutoff := false
var world_origin_offset := Vector3.ZERO
const SPINS: Array[float] = [1.0, -1.0, -1.0, 1.0]

func _ready() -> void:
	continuous_cd = true
	max_contacts_reported = 8
	can_sleep = false
	linear_damp = 0.0
	angular_damp = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	collision = CollisionShape3D.new()
	add_child(collision)
	camera = Camera3D.new()
	camera.near = 0.06
	camera.far = 1400.0
	camera.fov = 100.0
	camera.position = Vector3(0, 0.055, -0.18)
	add_child(camera)
	visual = Node3D.new()
	add_child(visual)
	apply_spec({"mass": 0.5, "arm": 0.14, "inertia": Vector3(0.003, 0.005, 0.003), "max_thrust": 4.0, "response": 0.055, "torque_ratio": 0.018, "drag": 0.007, "camera_tilt": 20.0})
	apply_tuning(tuning)
	get_viewport().size_changed.connect(_update_camera_clearance)

func apply_tuning(value: Dictionary) -> bool:
	if not FlightTuning.valid(value):
		return false
	tuning = FlightTuning.with_pid(value)
	_reset_rate_history()
	gravity_scale = float(tuning.gravity) / maxf(0.001, float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)))
	linear_damp = float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1)) * float(tuning.air_drag)
	angular_damp = float(ProjectSettings.get_setting("physics/3d/default_angular_damp", 0.1)) * float(tuning.angular_drag)
	return true

func apply_spec(value: Dictionary) -> void:
	spec = value.duplicate(true)
	mass = float(spec.mass)
	inertia = spec.inertia
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	var arm := float(spec.arm)
	camera.rotation_degrees.x = float(spec.camera_tilt)
	_update_camera_clearance()
	for child in visual.get_children():
		child.queue_free()
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(arm * 1.2, 0.075, arm * 1.5)
	body.mesh = body_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("253745")
	body.material_override = material
	visual.add_child(body)
	for index in 4:
		var rotor := MeshInstance3D.new()
		var rotor_mesh := CylinderMesh.new()
		rotor_mesh.top_radius = arm * 0.43
		rotor_mesh.bottom_radius = arm * 0.43
		rotor_mesh.height = 0.012
		rotor_mesh.radial_segments = 12
		rotor.mesh = rotor_mesh
		rotor.position = motor_position(index, arm)
		var rotor_material := StandardMaterial3D.new()
		rotor_material.albedo_color = Color("eab56b") if index < 2 else Color("45b7ac")
		rotor.material_override = rotor_material
		visual.add_child(rotor)
	rate_integral = Vector3.ZERO
	_reset_rate_history()
	motor_forces.fill(0.0)

func _update_camera_clearance() -> void:
	if spec.is_empty() or not is_instance_valid(camera): return
	var arm := float(spec.arm)
	var envelope := AABB(Vector3(-arm * 1.1, -0.055, -arm * 1.1), Vector3(arm * 2.2, 0.11, arm * 2.2))
	envelope = envelope.expand(camera.position - Vector3.ONE * FPV_CAMERA_CLEARANCE)
	envelope = envelope.expand(camera.position + Vector3.ONE * FPV_CAMERA_CLEARANCE)
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(1, viewport_size.y)
	var half := tan(deg_to_rad(camera.fov) * 0.5) * camera.near
	# Cover both aspect conventions, the mounted camera tilt and resized windows.
	for x: float in [-1, 1]:
		for y: float in [-1, 1]:
			var corner := camera.position + camera.basis * Vector3(x * half * maxf(1, aspect), y * half * maxf(1, 1 / aspect), -camera.near)
			envelope = envelope.expand(corner - Vector3.ONE * 0.02)
			envelope = envelope.expand(corner + Vector3.ONE * 0.02)
	var shape := BoxShape3D.new()
	shape.size = envelope.size
	collision.position = envelope.get_center()
	collision.shape = shape

static func motor_position(index: int, arm: float) -> Vector3:
	return Vector3(-arm if index % 2 == 0 else arm, 0.0, -arm if index < 2 else arm)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if reset_pending:
		state.transform = reset_transform
		update_altitude_protection(reset_transform.origin.y + world_origin_offset.y)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		stop_control()
		reset_pending = false
		return
	if freeze:
		stop_control()
		return
	if motion_restore_pending:
		state.linear_velocity = paused_linear_velocity
		state.angular_velocity = paused_angular_velocity
		motion_restore_pending = false
	update_altitude_protection(state.transform.origin.y + world_origin_offset.y)
	var dt := state.step
	if state.get_contact_count() > 0:
		contact_serial += 1
	_guard_swept_motion(state)
	var basis := state.transform.basis.orthonormalized()
	var local_rate := basis.inverse() * state.angular_velocity
	var collective := 0.0
	var torque := Vector3.ZERO
	var target := target_rates(controls, tuning)
	var acceleration := _rate_acceleration(target, local_rate, dt)
	torque = spec.inertia * acceleration + local_rate.cross(spec.inertia * local_rate)
	collective = pow(clampf(controls.w, 0.0, 1.0), 1.55) * float(spec.max_thrust)
	total_thrust = 0.0
	var arm := float(spec.arm)
	var reaction := float(spec.torque_ratio)
	var available_torque := Vector3.ZERO
	for index in 4:
		if altitude_cutoff:
			# Torque mixing and motor lag must not produce thrust during protection.
			motor_forces[index] = 0.0
			rate_integral = Vector3.ZERO
			continue
		var offset := motor_position(index, arm)
		var force: float = collective + (-offset.z * torque.x + offset.x * torque.z) / (4.0 * arm * arm) + SPINS[index] * torque.y / (4.0 * reaction)
		force = clampf(force, 0.0, float(spec.max_thrust))
		available_torque += Vector3(-offset.z * force, SPINS[index] * reaction * force, offset.x * force)
		motor_forces[index] = lerpf(motor_forces[index], force, 1.0 - exp(-dt / float(spec.response)))
		state.apply_force(basis.y * motor_forces[index], basis * offset)
		state.apply_torque(basis.y * SPINS[index] * reaction * motor_forces[index])
		total_thrust += motor_forces[index]
	saturation_sign = Vector3.ZERO
	if not altitude_cutoff:
		for axis in 3:
			if absf(torque[axis] - available_torque[axis]) > 0.00001:
				saturation_sign[axis] = signf(torque[axis] - available_torque[axis])
	var velocity := state.linear_velocity
	state.apply_central_force(-velocity * (0.035 + float(spec.drag) * velocity.length()) * float(tuning.air_drag))
	state.apply_torque(-state.angular_velocity * 0.001 * float(tuning.angular_drag))

func _rate_acceleration(target: Vector3, measured: Vector3, dt: float) -> Vector3:
	var error := target - measured
	if rate_history_valid:
		var derivative := (measured - previous_rate) / maxf(0.0001, dt)
		rate_derivative = rate_derivative.lerp(derivative, 1.0 - exp(-TAU * float(tuning.d_filter_hz) * dt))
	else:
		rate_derivative = Vector3.ZERO
		rate_history_valid = true
	previous_rate = measured
	for axis in 3:
		# Integrate only if the available motor authority can correct this error,
		# or if the error would unwind saturation in the opposite direction.
		if error[axis] * saturation_sign[axis] <= 0:
			rate_integral[axis] = clampf(rate_integral[axis] + error[axis] * dt, -1.5, 1.5)
	var p := Vector3(tuning.pid.pitch.p, tuning.pid.yaw.p, tuning.pid.roll.p)
	var i := Vector3(tuning.pid.pitch.i, tuning.pid.yaw.i, tuning.pid.roll.i)
	var d := Vector3(tuning.pid.pitch.d, tuning.pid.yaw.d, tuning.pid.roll.d)
	# Derivative of measured rate avoids a kick when the stick target jumps.
	return error * p + rate_integral * i - rate_derivative * d

func _reset_rate_history() -> void:
	rate_integral = Vector3.ZERO
	previous_rate = Vector3.ZERO
	rate_derivative = Vector3.ZERO
	rate_history_valid = false
	saturation_sign = Vector3.ZERO

func _guard_swept_motion(state: PhysicsDirectBodyState3D) -> void:
	var motion := state.linear_velocity * state.step
	if motion.length_squared() < 0.04 * 0.04:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = state.transform * collision.transform
	query.motion = motion
	query.margin = 0.003
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	var space := state.get_space_state()
	var fractions := space.cast_motion(query)
	var safe: float = fractions[0] if fractions.size() == 2 else 1.0
	var normal := Vector3.ZERO
	if safe < 1:
		query.transform.origin += motion * minf(1, fractions[1] + 0.001 / motion.length())
		query.motion = Vector3.ZERO
		var rest := space.get_rest_info(query)
		if not rest.is_empty():
			normal = rest.normal
	# Convex casts share the native CCD's extreme-speed triangle edge cases.
	# Sweep the box corners and centre as well, against actual geometry only.
	if motion.length_squared() > 0.1 * 0.1:
		var half_size: Vector3 = collision.shape.size * 0.5
		var points := PackedVector3Array([Vector3.ZERO])
		for x: float in [-1, 1]:
			for y: float in [-1, 1]:
				for z: float in [-1, 1]:
					points.append(half_size * Vector3(x, y, z))
		for point in points:
			var start: Vector3 = state.transform * collision.transform * point
			var ray := PhysicsRayQueryParameters3D.create(start, start + motion, collision_mask, [get_rid()])
			ray.hit_back_faces = true
			var hit := space.intersect_ray(ray)
			if hit.is_empty() or state.linear_velocity.dot(hit.normal) >= 0:
				continue
			var fraction: float = start.distance_to(hit.position) / motion.length()
			if fraction < safe:
				safe = fraction
				normal = hit.normal
	if safe >= 1:
		return
	swept_impacts += 1
	contact_serial += 1
	safe = maxf(0, safe - 0.003 / motion.length())
	if not normal.is_zero_approx() and state.linear_velocity.dot(normal) < 0:
		# Keep tangential speed; limit only this step's approach to the contact.
		var approach := normal * state.linear_velocity.dot(normal)
		state.linear_velocity = state.linear_velocity - approach + approach * safe
	else:
		state.linear_velocity *= safe

func update_altitude_protection(world_height: float) -> void:
	if world_height > MAX_ALTITUDE:
		altitude_cutoff = true
	elif world_height <= SOFT_ALTITUDE:
		altitude_cutoff = false

func effective_throttle() -> float:
	return 0.0 if altitude_cutoff or freeze else clampf(controls.w, 0, 1)

static func target_rates(input: Vector4, profile: Dictionary) -> Vector3:
	return Vector3(-FlightTuning.response(input.y, profile.axes.pitch), -FlightTuning.response(input.z, profile.axes.yaw), -FlightTuning.response(input.x, profile.axes.roll)) * (PI / 180.0)

func stop_control() -> void:
	controls = Vector4.ZERO
	_reset_rate_history()
	motor_forces.fill(0.0)
	total_thrust = 0.0

func set_simulation_paused(value: bool) -> void:
	if value == freeze:
		return
	if value:
		# Godot's frozen body may report zero velocity after the physics sync.
		# Repeated pause/menu calls must not overwrite the original snapshot.
		if not motion_restore_pending:
			paused_linear_velocity = linear_velocity
			paused_angular_velocity = angular_velocity
		freeze = true
		stop_control()
	else:
		freeze = false
		linear_velocity = paused_linear_velocity
		angular_velocity = paused_angular_velocity
		motion_restore_pending = true

func motion_velocity() -> Vector3:
	return paused_linear_velocity if freeze else linear_velocity

func reset_drone(at: Vector3 = spawn_point, heading: float = 0.0) -> void:
	contact_serial += 1
	stop_control()
	reset_transform = Transform3D(Basis(Vector3.UP, heading), at)
	reset_pending = true
	paused_linear_velocity = Vector3.ZERO
	paused_angular_velocity = Vector3.ZERO
	motion_restore_pending = false
	global_transform = reset_transform
	update_altitude_protection(at.y + world_origin_offset.y)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	reset_physics_interpolation()

func reset_attitude() -> void:
	var forward := -global_basis.z
	var heading := atan2(-forward.x, -forward.z)
	if Vector2(forward.x, forward.z).length_squared() < 0.0001:
		var right := global_basis.x
		heading = atan2(-right.z, right.x)
	reset_drone(global_position, heading)

func shift_origin(shift: Vector3) -> void:
	world_origin_offset += shift
	global_position -= shift
	if reset_pending:
		reset_transform.origin -= shift
	reset_physics_interpolation()
