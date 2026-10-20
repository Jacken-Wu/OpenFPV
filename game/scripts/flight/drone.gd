class_name FPVDrone
extends RigidBody3D
## Rate controller and four lagged motors; all hardware enters through one resolved spec.

var controls := Vector4.ZERO
var armed := false
var rates_dps := 360.0
var expo := 0.25
var spec: Dictionary = {}
var camera: Camera3D
var motor_forces := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var rate_integral := Vector3.ZERO
var total_thrust := 0.0
var spawn_point := Vector3(0, 3, 16)
var visual: Node3D
var collision: CollisionShape3D
const SPINS: Array[float] = [1.0, -1.0, -1.0, 1.0]

func _ready() -> void:
	continuous_cd = true
	can_sleep = false
	linear_damp = 0.0
	angular_damp = 0.0
	collision = CollisionShape3D.new()
	add_child(collision)
	camera = Camera3D.new()
	camera.near = 0.025
	camera.far = 2400.0
	camera.fov = 100.0
	camera.position = Vector3(0, 0.055, -0.18)
	add_child(camera)
	visual = Node3D.new()
	add_child(visual)
	apply_spec({"mass": 0.5, "arm": 0.14, "inertia": Vector3(0.003, 0.005, 0.003), "max_thrust": 4.0, "response": 0.055, "torque_ratio": 0.018, "drag": 0.007, "camera_tilt": 20.0})

func apply_spec(value: Dictionary) -> void:
	spec = value.duplicate(true)
	mass = float(spec.mass)
	inertia = spec.inertia
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	var shape := BoxShape3D.new()
	var arm := float(spec.arm)
	shape.size = Vector3(arm * 2.2, 0.11, arm * 2.2)
	collision.shape = shape
	camera.rotation_degrees.x = float(spec.camera_tilt)
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
	motor_forces.fill(0.0)

static func motor_position(index: int, arm: float) -> Vector3:
	return Vector3(-arm if index % 2 == 0 else arm, 0.0, -arm if index < 2 else arm)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt := state.step
	var basis := state.transform.basis.orthonormalized()
	var local_rate := basis.inverse() * state.angular_velocity
	var collective := 0.0
	var torque := Vector3.ZERO
	if armed:
		var target := target_rates(controls, rates_dps, expo)
		var error := target - local_rate
		rate_integral = (rate_integral + error * dt).clamp(Vector3.ONE * -1.5, Vector3.ONE * 1.5)
		var acceleration := error * Vector3(18.0, 12.0, 18.0) + rate_integral * 3.0
		torque = spec.inertia * acceleration + local_rate.cross(spec.inertia * local_rate)
		collective = pow(clampf(controls.w, 0.0, 1.0), 1.55) * float(spec.max_thrust)
	else:
		rate_integral = Vector3.ZERO
	total_thrust = 0.0
	var arm := float(spec.arm)
	var reaction := float(spec.torque_ratio)
	for index in 4:
		var offset := motor_position(index, arm)
		var force: float = collective + (-offset.z * torque.x + offset.x * torque.z) / (4.0 * arm * arm) + SPINS[index] * torque.y / (4.0 * reaction)
		force = clampf(force, 0.0, float(spec.max_thrust)) if armed else 0.0
		motor_forces[index] = lerpf(motor_forces[index], force, 1.0 - exp(-dt / float(spec.response)))
		state.apply_force(basis.y * motor_forces[index], basis * offset)
		state.apply_torque(basis.y * SPINS[index] * reaction * motor_forces[index])
		total_thrust += motor_forces[index]
	var velocity := state.linear_velocity
	state.apply_central_force(-velocity * (0.035 + float(spec.drag) * velocity.length()))
	state.apply_torque(-state.angular_velocity * 0.001)

static func target_rates(input: Vector4, rate_dps: float, curve: float) -> Vector3:
	var shaped := Vector3(input.x, input.y, input.z)
	shaped = shaped * (1.0 - curve) + shaped * shaped * shaped * curve
	return Vector3(-shaped.y, -shaped.z * 0.7, -shaped.x) * deg_to_rad(rate_dps)

func reset_drone(at: Vector3 = spawn_point) -> void:
	armed = false
	global_transform = Transform3D(Basis.IDENTITY, at)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	rate_integral = Vector3.ZERO
	motor_forces.fill(0.0)
