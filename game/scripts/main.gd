extends Node3D

var drone: FPVDrone
var flight_input: FlightInput
var hud: Label
var message: Label
var paused_by_user := false

func _ready() -> void:
	_build_world()
	flight_input = FlightInput.new()
	add_child(flight_input)
	drone = FPVDrone.new()
	add_child(drone)
	drone.position = drone.spawn_point
	drone.camera.current = true
	flight_input.connection_lost.connect(func(): _pause(true); message.text = "输入设备断开，飞行已暂停。")
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(28, 22)
	hud.add_theme_font_size_override("font_size", 19)
	canvas.add_child(hud)
	message = Label.new()
	message.position = Vector2(28, 740)
	message.text = "OpenFPV / 飞行灰盒\nW S 俯仰 · A D 横滚 · J L 偏航 · ↑ ↓ 油门 · 空格 电机解锁 · R 重置 · P 暂停"
	canvas.add_child(message)
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke()

func _smoke() -> void:
	await get_tree().create_timer(2.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../.local/flight-smoke.png")
	print("SMOKE_OK")
	get_tree().quit()

func _physics_process(_delta: float) -> void:
	drone.controls = flight_input.channels

func _process(_delta: float) -> void:
	if hud:
		hud.text = "OPENFPV   /   FREE FLIGHT\n%s  |  油门 %d%%  |  %.1f km/h  |  高度 %.1f m\n推力 %.1f N  ·  120 Hz  ·  %d FPS" % ["电机已解锁" if drone.armed else "电机锁定", int(flight_input.channels.w * 100), drone.linear_velocity.length() * 3.6, drone.position.y, drone.total_thrust, Engine.get_frames_per_second()]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE:
			if drone.armed:
				drone.armed = false
			elif flight_input.channels.w < 0.08 and not paused_by_user:
				drone.armed = true
		KEY_R:
			drone.reset_drone()
			flight_input.reset_throttle()
		KEY_P, KEY_ESCAPE:
			_pause(not paused_by_user)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(drone):
		_pause(true)

func _pause(value: bool) -> void:
	paused_by_user = value
	drone.freeze = value
	flight_input.enabled = not value

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9aafb4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d5dc")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_color = Color("ffdfb2")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	add_box(Vector3(0, -1, 0), Vector3(100, 2, 100), Color("526755"))
	for x in [-7.0, 7.0]:
		add_box(Vector3(x, 5, -15), Vector3(2, 10, 4), Color("536d78"))
	add_box(Vector3(0, 10, -15), Vector3(16, 1.5, 4), Color("cd9b64"))
	add_box(Vector3(0, 0.5, 16), Vector3(8, 1, 8), Color("bc945e"))
	for i in 8:
		add_box(Vector3(-24, 2 + i * 0.8, -i * 9), Vector3(5, 4 + i * 1.6, 5), Color("657c77"))

func add_box(at: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = size
	shape.shape = collider
	body.add_child(shape)
	add_child(body)
