extends Node3D
## Composition root: physics, content, world generation and progression stay separate.

const RELAY_ID := "world.relay.harbor.01"
const RELAY_POSITION := Vector3(-18, 1.3, 12)
const SHOP_POSITION := Vector3(18, 1.3, 12)
var catalog: ContentCatalog
var store: ProgressStore
var assembler: DroneAssembler
var generator: WorldGenerator
var streamer: WorldStreamer
var drone: FPVDrone
var flight_input: FlightInput
var features: Node3D
var gate: Node3D
var relay_lamp: MeshInstance3D
var truck: Node3D
var chase_camera: Camera3D
var canvas: CanvasLayer
var hud: Label
var telemetry: Label
var objective: Label
var notice: Label
var prompt: Label
var menu_host: CenterContainer
var menu: Control
var paused := true
var pause_reason := "准备就绪后按 P 开始"
var radio_required := false
var ready_frames := 2
var task_hold := 0.0
var world_time := 0.0
var spawn_world := Vector3(0, 1.2, 16)
var last_notice := "欢迎来到 OpenFPV。F2 校准遥控器；F1 查看操作。"
var screenshot_busy := false
var benchmark_samples: Array[float] = []
var integration_mode := false

func _ready() -> void:
	integration_mode = "--smoke" in OS.get_cmdline_user_args() or "--tour" in OS.get_cmdline_user_args() or "--test-session" in OS.get_cmdline_user_args() or "--benchmark" in OS.get_cmdline_user_args()
	catalog = ContentCatalog.new()
	if not catalog.errors.is_empty():
		push_error("Content validation failed: " + str(catalog.errors))
		get_tree().quit(1)
		return
	assembler = DroneAssembler.new(catalog)
	store = ProgressStore.new(catalog, "user://tests/integration_" + str(Time.get_ticks_usec()) + "/progress.json" if integration_mode else "user://profile/progress.json")
	var deployment: Variant = store.data.get("deployment", [0.0, 1.2, 16.0])
	if deployment is Array and deployment.size() == 3:
		var point := Vector3(float(deployment[0]), float(deployment[1]), float(deployment[2]))
		if point.is_finite():
			spawn_world = point
	generator = WorldGenerator.new(catalog, int(store.data.seed))
	_build_environment()
	streamer = WorldStreamer.new()
	streamer.generator = generator
	add_child(streamer)
	_build_features()
	flight_input = FlightInput.new()
	add_child(flight_input)
	drone = FPVDrone.new()
	add_child(drone)
	drone.freeze = true
	drone.position = spawn_world
	drone.camera.current = true
	var resolved := assembler.resolve(store.data.build, store.data.owned)
	if not resolved.ok:
		resolved = assembler.resolve(assembler.from_preset(catalog.manifest.initial_preset_id), store.data.owned)
		last_notice = "旧装配已失效，暂用初始套机；原配置仍保留在存档中。"
	drone.apply_spec(resolved.spec)
	drone.rates_dps = clampf(float(store.data.settings.get("rates", 360)), 180, 600)
	drone.expo = clampf(float(store.data.settings.get("expo", 0.25)), 0, 0.6)
	chase_camera = Camera3D.new()
	chase_camera.fov = 75
	add_child(chase_camera)
	flight_input.connection_lost.connect(func():
		radio_required = true
		drone.armed = false
		_set_paused(true, "遥控器断开 · F2 重连或选择键盘")
		last_notice = "设备断开，已锁定电机并暂停。重连后不会自动恢复。")
	_restore_radio()
	_build_hud()
	_update_relay()
	_set_paused(true, "P 开始探索 · F2 校准遥控器")
	if not store.warning.is_empty():
		last_notice = store.warning
	if "--smoke" in OS.get_cmdline_user_args() or "--tour" in OS.get_cmdline_user_args():
		_smoke_tour()
	if "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()

func _restore_radio() -> void:
	var settings: Dictionary = store.data.settings
	if not settings.get("radio_active", false):
		return
	radio_required = true
	var profiles: Dictionary = settings.get("radio_profiles", {})
	var active_profile: String = settings.get("active_radio_profile", "")
	for device in Input.get_connected_joypads():
		var guid := Input.get_joy_guid(device)
		if profiles.has(active_profile) and profiles[active_profile].guid == guid and FlightInput.valid_profile(profiles[active_profile]):
			flight_input.activate_profile(profiles[active_profile], device)
			radio_required = false
			return
	last_notice = "未找到已校准的遥控器。F2 连接设备或明确切换键盘。"

func _build_environment() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("86a6b3")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d5dc")
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = Color("86a6b3")
	env.fog_density = 0.0017
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_color = Color("ffdfba")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	add_child(sun)

func _build_features() -> void:
	features = Node3D.new()
	add_child(features)
	features.add_child(WorldGeometry.create_box(Vector3(0, 0.25, 16), Vector3(8, 0.5, 8), Color("c19855")))
	for point: Vector3 in [RELAY_POSITION, SHOP_POSITION]:
		features.add_child(WorldGeometry.create_box(point, Vector3(1.5, 2.6, 1.5), Color("2c4754")))
		features.add_child(WorldGeometry.create_box(point + Vector3(0, -1.05, 5), Vector3(7, 0.5, 6), Color("63898a")))
		features.add_child(WorldGeometry.create_box(point + Vector3(0, 0.5, 0.8), Vector3(1.1, 0.65, 0.1), Color("74dbca"), false))
	gate = WorldGeometry.create_box(Vector3(0, 4, -12), Vector3(14, 8, 0.7), Color("a65e38"))
	features.add_child(gate)
	features.add_child(WorldGeometry.create_box(Vector3(-8, 5, -12), Vector3(1, 10, 2), Color("2f4650")))
	features.add_child(WorldGeometry.create_box(Vector3(8, 5, -12), Vector3(1, 10, 2), Color("2f4650")))
	_marker("中继维修 / E", RELAY_POSITION + Vector3(0, 3, 0), Color("ebbd77"))
	_marker("桨叶商店 / E", SHOP_POSITION + Vector3(0, 3, 0), Color("7cd9c9"))
	_marker("浮岛观测站 · 114 m", Vector3(100, 119, -68), Color("ebbd77"))
	_marker("地下入口 · 深 48 m", Vector3(-96, 4, -96), Color("a7bbef"))
	var chamber_light := OmniLight3D.new()
	chamber_light.position = Vector3(-96, -24, -96)
	chamber_light.light_color = Color("78b6ad")
	chamber_light.light_energy = 2.5
	chamber_light.omni_range = 65
	features.add_child(chamber_light)
	truck = Node3D.new()
	features.add_child(truck)
	truck.add_child(WorldGeometry.create_box(Vector3(0, 1.2, 0), Vector3(2.4, 1.8, 4.5), Color("c88e4c")))
	truck.add_child(WorldGeometry.create_box(Vector3(0, 2.3, -1.1), Vector3(2.1, 0.6, 1.6), Color("365260")))
	for x: float in [-1.2, 1.2]:
		for z: float in [-1.5, 1.5]:
			truck.add_child(WorldGeometry.create_box(Vector3(x, 0.45, z), Vector3(0.4, 0.8, 0.8), Color("182d39")))

func _marker(text: String, point: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.font_size = 36
	label.pixel_size = 0.012
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	features.add_child(label)

func _build_hud() -> void:
	canvas = CanvasLayer.new()
	add_child(canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIStyle.theme()
	canvas.add_child(root)
	var header := PanelContainer.new()
	header.position = Vector2(24, 20)
	header.custom_minimum_size = Vector2(520, 80)
	root.add_child(header)
	hud = UIStyle.label("", 18)
	header.add_child(hud)
	var right := PanelContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-420, 20)
	right.custom_minimum_size = Vector2(396, 100)
	root.add_child(right)
	objective = UIStyle.label("", 17)
	right.add_child(objective)
	telemetry = UIStyle.label("", 15, Color("cee2e7"))
	telemetry.position = Vector2(28, 135)
	root.add_child(telemetry)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 24
	bottom.offset_right = -24
	bottom.offset_top = -119
	bottom.offset_bottom = -20
	root.add_child(bottom)
	var column := UIStyle.column(bottom, 5)
	prompt = UIStyle.label("", 18, Color("f0c485"))
	column.add_child(prompt)
	notice = UIStyle.label("", 15)
	column.add_child(notice)
	column.add_child(UIStyle.label("空格 解锁   R 重置   P 暂停   F1 帮助   F2 遥控器   Tab 装备   M 地图   C 视角   F12 拍照", 15, Color("8daab8")))
	var center := UIStyle.label("+", 20, Color("ffffff80"))
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.add_child(center)
	menu_host = CenterContainer.new()
	menu_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_host)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(drone):
		return
	var ready := streamer.collision_ready(_world_position())
	ready_frames = maxi(0, ready_frames - 1) if ready else 2
	drone.freeze = paused or not ready or ready_frames > 0
	flight_input.enabled = not drone.freeze
	drone.controls = flight_input.channels if not drone.freeze else Vector4.ZERO
	if drone.position.length() > 1024:
		var shift := Vector3(WorldGenerator.key_at(drone.position)) * WorldGenerator.CHUNK_SIZE
		streamer.shift_origin(shift)
		drone.position -= shift
		features.position -= shift

func _process(delta: float) -> void:
	if not is_instance_valid(drone):
		return
	var point := _world_position()
	streamer.focus = point
	prompt.text = "沿道路探索 · 追随移动货车练习运镜 · M 部署到浮岛 / 地下"
	if not paused:
		world_time += delta
		_interactions(delta, point)
	var segment := fmod(world_time * 4.0, 256.0)
	var corners: Array[Vector3] = [Vector3(0, 0, 64), Vector3(0, 0, 128), Vector3(64, 0, 128), Vector3(64, 0, 64)]
	var index := int(segment / 64.0)
	truck.position = corners[index].lerp(corners[(index + 1) % 4], fmod(segment, 64.0) / 64)
	truck.rotation.y = [0.0, -PI * 0.5, PI, PI * 0.5][index]
	chase_camera.position = drone.position + drone.global_basis * Vector3(2.0, 1.6, 4.0)
	chase_camera.look_at(drone.position)
	var biome := generator.biome_at(point)
	var input_name: String = flight_input.profile.get("name", "USB 遥控器") if flight_input.using_radio else "键盘调试"
	hud.text = "OPENFPV   /   自由探索 P1\n%s  ·  %s  ·  %s" % ["已解锁" if drone.armed else "电机锁定", input_name, biome.display_name if biome else "边境"]
	telemetry.text = "%.1f km/h   %.1f m   油门 %d%%\n姿态 %+.0f / %+.0f / %+.0f °\n推力 %.1f N   %.0f g   %d FPS\n120 Hz · 帧 %.1f ms · 块 %d / %d · 提交 %.1f ms\n世界 %.0f, %.0f, %.0f · 种子 %d" % [drone.linear_velocity.length() * 3.6, point.y, flight_input.channels.w * 100, drone.rotation_degrees.x, drone.rotation_degrees.y, drone.rotation_degrees.z, drone.total_thrust, drone.mass * 1000, Engine.get_frames_per_second(), delta * 1000, streamer.active.size(), streamer.desired.size(), streamer.last_commit_ms, point.x, point.y, point.z, store.data.seed]
	var fixed := bool(store.data.facilities.get(RELAY_ID, false))
	objective.text = "重连锈港  /  %d 信用点\n%s\n%s" % [store.data.credits, "✓ 中继在线 · 轻型套机已解锁" if fixed else "◇ 靠近维修终端，稳定停留并按住 E", "自由探索没有倒计时或续航限制"]
	if paused:
		prompt.text = "已暂停  /  " + pause_reason
	elif drone.freeze:
		prompt.text = "正在准备周围地图与碰撞……"
	notice.text = last_notice

func _interactions(delta: float, point: Vector3) -> void:
	if drone.freeze:
		return
	var near_relay := point.distance_to(RELAY_POSITION) < 6.5
	var near_shop := point.distance_to(SHOP_POSITION) < 6.5
	if near_relay and not store.data.facilities.get(RELAY_ID, false):
		prompt.text = "维修终端 · 保持速度 < 1.5 m/s，按住 E 两秒"
		if Input.is_physical_key_pressed(KEY_E) and drone.linear_velocity.length() < 1.5:
			task_hold += delta
			prompt.text = "正在连接中继…… %d%%" % mini(100, int(task_hold * 50))
			if task_hold >= 2:
				var result := store.complete_relay(RELAY_ID, "maintenance.relay", "industrial")
				last_notice = result.message
				task_hold = 0
				_update_relay()
		else:
			task_hold = 0
	elif near_shop:
		prompt.text = "桨叶商店 · E 浏览商品"
		task_hold = 0
	else:
		task_hold = 0

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE:
			if menu != null or paused or drone.freeze:
				return
			if drone.armed:
				drone.armed = false
			elif flight_input.throttle_now() < 0.08:
				drone.armed = true
			else:
				last_notice = "先把油门降至最低，再解锁电机。"
		KEY_R:
			_deploy(spawn_world)
		KEY_P:
			if menu != null:
				_close_menu()
			_toggle_pause()
		KEY_ESCAPE:
			if menu != null:
				_close_menu()
			else:
				_toggle_pause()
		KEY_F1: _show_help()
		KEY_F2: _show_radio()
		KEY_TAB: _show_workshop()
		KEY_M: _show_map()
		KEY_C:
			if drone.camera.current:
				chase_camera.current = true
			else:
				drone.camera.current = true
		KEY_F12: _capture()
		KEY_E:
			if not paused and _world_position().distance_to(SHOP_POSITION) < 6.5 and drone.linear_velocity.length() < 1.5:
				_show_shop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(drone) and not integration_mode:
		drone.armed = false
		_set_paused(true, "窗口失焦 · P 恢复，再解锁电机")

func _set_paused(value: bool, reason: String = "P 恢复飞行") -> void:
	paused = value
	pause_reason = reason
	flight_input.enabled = not value
	if value:
		drone.freeze = true

func _toggle_pause() -> void:
	if paused and radio_required:
		last_notice = "先按 F2 连接遥控器，或明确选择键盘调试。"
		return
	_set_paused(not paused)

func _world_position() -> Vector3:
	return drone.position + streamer.origin_offset

func _deploy(point: Vector3) -> void:
	spawn_world = point
	drone.reset_drone(point - streamer.origin_offset)
	flight_input.reset_throttle()
	ready_frames = 2
	last_notice = "已部署，电机保持锁定。最低油门后按空格解锁。"
	if not integration_mode:
		var result := store.save_deployment(point)
		if not result.ok:
			last_notice = result.message

func _mount_menu(value: Control) -> void:
	_close_menu()
	_set_paused(true, "菜单已关闭后，按 P 恢复")
	menu = value
	menu_host.add_child(menu)

func _close_menu() -> void:
	if is_instance_valid(menu):
		menu_host.remove_child(menu)
		menu.queue_free()
	menu = null

func _simple_menu(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme = UIStyle.theme()
	panel.custom_minimum_size.x = 860
	_mount_menu(panel)
	var column := UIStyle.column(panel)
	column.add_child(UIStyle.label(title, 28, Color("70d7cb")))
	return column

func _show_help() -> void:
	var column := _simple_menu("欢迎来到 OpenFPV / 开放世界飞行原型")
	column.add_child(UIStyle.label("先按 F2 校准富斯 i6x。校准时三根回中轴归中、油门最低。\n本作采用 Acro：摇杆控制转动速度，松杆会保持倾角，机体不会自动回平。\n空格解锁后慢慢增加油门；推杆前倾，再加油门产生前进速度。", 18))
	column.add_child(UIStyle.label("键盘调试：W/S 俯仰 · A/D 横滚 · J/L 偏航 · ↑/↓ 持续调整油门\n空格 解锁/锁定 · R 回到部署点 · P 暂停/恢复 · C 第一/第三人称\nTab 装备台 · M 区域图/部署 · E 终端交互 · F12 保存照片\n窗口失焦或遥控器拔出时暂停并锁定；恢复后需要手动解锁。", 18))
	column.add_child(UIStyle.label("第一件事：前往左侧中继终端，稳定停留并按住 E 两秒。\n修复会打开前方闸门，授予轻型套机和 200 信用点。\n右侧商店以 150 点出售柔和桨叶；M 可部署到浮岛、地下和峡谷。\n可以跟随货车练习拍摄。没有计时压力，也没有续航补给。", 18, Color("e5c291")))
	column.add_child(UIStyle.button("关闭帮助 · 然后按 P 开始", _close_menu))

func _show_radio() -> void:
	var column := _simple_menu("选择飞行输入")
	column.add_child(UIStyle.label("USB 加密狗的通道顺序因设备而异，请逐轴校准。\n更换加密狗或系统设备标识后，重新校准即可。", 18))
	var profiles: Dictionary = store.data.settings.get("radio_profiles", {})
	for key: String in profiles:
		var profile: Dictionary = profiles[key]
		for device in Input.get_connected_joypads():
			if String(profile.get("guid", "")) == Input.get_joy_guid(device) and FlightInput.valid_profile(profile):
				var chosen_device := device
				var chosen_profile := profile
				column.add_child(UIStyle.button("使用已保存配置：" + String(profile.name), func(): _accept_radio(chosen_profile, chosen_device)))
	column.add_child(UIStyle.button("校准 / 重新连接遥控器", func():
		var calibration := RadioCalibration.new()
		calibration.closed.connect(_close_menu)
		calibration.accepted.connect(_accept_radio)
		_mount_menu(calibration)))
	column.add_child(UIStyle.button("明确切换为键盘调试", func():
		flight_input.using_radio = false
		flight_input.reset_throttle()
		radio_required = false
		var settings: Dictionary = store.data.settings.duplicate(true)
		settings.radio_active = false
		var result := store.save_settings(settings)
		last_notice = "已切换键盘调试 · P 恢复" if result.ok else result.message
		_close_menu()))
	column.add_child(UIStyle.button("返回", _close_menu))

func _accept_radio(profile: Dictionary, device: int) -> void:
	var settings: Dictionary = store.data.settings.duplicate(true)
	if not settings.has("radio_profiles"):
		settings.radio_profiles = {}
	var profile_key: String = profile.guid + "|" + profile.name
	settings.radio_profiles[profile_key] = profile
	settings.active_radio_profile = profile_key
	settings.radio_active = true
	var result := store.save_settings(settings)
	if not result.ok:
		last_notice = result.message
		return
	flight_input.activate_profile(profile, device)
	radio_required = false
	drone.armed = false
	last_notice = "遥控器校准已保存 · P 恢复，最低油门后空格解锁"
	_close_menu()

func _show_workshop() -> void:
	var workshop := Workshop.new()
	workshop.catalog = catalog
	workshop.store = store
	workshop.build = store.data.build.duplicate(true)
	if not assembler.resolve(workshop.build, store.data.owned).ok:
		workshop.build = assembler.from_preset(catalog.manifest.initial_preset_id)
	workshop.rate = drone.rates_dps
	workshop.expo = drone.expo
	workshop.closed.connect(_close_menu)
	workshop.apply_requested.connect(func(build: Dictionary, rate: float, expo_value: float):
		if drone.armed or not _grounded():
			workshop.message = "请先落地并锁定电机，或按 M 部署到平台。"
			workshop._preview()
			return
		var settings: Dictionary = store.data.settings.duplicate(true)
		settings.rates = rate
		settings.expo = expo_value
		var result := store.save_loadout(build, settings)
		if result.ok:
			drone.apply_spec(assembler.resolve(build, store.data.owned).spec)
			drone.rates_dps = rate
			drone.expo = expo_value
			result.message = "装配与操控设置已保存并应用"
		workshop.message = result.message
		workshop._preview()
		last_notice = result.message)
	_mount_menu(workshop)

func _grounded() -> bool:
	if drone.linear_velocity.length() > 1.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(drone.position, drone.position + Vector3.DOWN * 0.9)
	query.exclude = [drone.get_rid()]
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _show_map() -> void:
	var column := _simple_menu("区域图 / 自由部署")
	var map_view := RegionMap.new()
	map_view.drone_point = _world_position()
	column.add_child(map_view)
	column.add_child(UIStyle.label("棕：锈港工业区   绿：青穹街区   金：浮岛   蓝：地下入口\n城市样本向外衔接程序化峡谷。部署会锁定电机，保留世界进度。", 16))
	var locations := {"起降平台": Vector3(0, 1.2, 16), "维修终端": Vector3(-18, 1.2, 17), "商店平台": Vector3(18, 1.2, 17), "青穹街区": Vector3(64, 1.2, 16), "浮岛观测站": Vector3(100, 115, -68), "地下维修层": Vector3(-96, -43, -112), "峡谷入口": Vector3(240, 42, 0)}
	var row := HFlowContainer.new()
	column.add_child(row)
	for title: String in locations:
		var point: Vector3 = locations[title]
		row.add_child(UIStyle.button(title, func(): _deploy(point); _close_menu()))
	column.add_child(UIStyle.button("返回", _close_menu))

func _show_shop() -> void:
	var column := _simple_menu("锈港 / 桨叶商店")
	column.add_child(UIStyle.label("当前信用点 %d。配件取得后永久使用，所有套机都无需电池补给。" % store.data.credits, 18))
	for offer: OfferDefinition in catalog.manifest.offers:
		if offer.city_tag == "industrial":
			var offer_id := offer.id
			column.add_child(UIStyle.button("%s · %d 信用点%s" % [offer.display_name, offer.price, " [已取得]" if store.data.owned.has(offer.part_id) else ""], func():
				var result := store.purchase(offer_id, "industrial")
				last_notice = result.message
				_show_shop()))
	column.add_child(UIStyle.label(last_notice, 17, Color("e5c291")))
	column.add_child(UIStyle.button("返回", _close_menu))

func _update_relay() -> void:
	if store.data.facilities.get(RELAY_ID, false) and is_instance_valid(gate):
		gate.queue_free()
		gate = null
		_marker("中继在线", RELAY_POSITION + Vector3(0, 4, 0), Color("6de9be"))

func _capture() -> void:
	if screenshot_busy or DisplayServer.get_name() == "headless":
		return
	screenshot_busy = true
	await RenderingServer.frame_post_draw
	var capture_directory := "user://tests/captures" if integration_mode else "user://captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := capture_directory.path_join(stamp + "-" + str(Time.get_ticks_msec()) + ".png")
	var error := get_viewport().get_texture().get_image().save_png(path)
	var details := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if details:
		details.store_string(JSON.stringify({"seed": store.data.seed, "world_version": store.data.world_version, "build": store.data.build, "position": str(_world_position()), "rotation": str(drone.rotation), "input": flight_input.profile, "settings": store.data.settings}, "\t"))
		details.close()
	if error != OK or details == null:
		push_error("Photo or metadata could not be saved")
	elif integration_mode:
		print("PHOTO_CAPTURE_OK ", ProjectSettings.globalize_path(path))
	last_notice = "照片已保存：" + ProjectSettings.globalize_path(path) if error == OK else "照片保存失败"
	screenshot_busy = false

func _wait_for_world() -> void:
	for frame in 900:
		await get_tree().process_frame
		if streamer.collision_ready(spawn_world) and frame > 5:
			await get_tree().physics_frame
			return
	push_error("World collision readiness timed out")

func _smoke_tour() -> void:
	await _wait_for_world()
	await get_tree().create_timer(1).timeout
	if "--tour" in OS.get_cmdline_user_args():
		var overview := Camera3D.new()
		add_child(overview)
		overview.position = Vector3(75, 65, 115) - streamer.origin_offset
		overview.look_at(Vector3(0, 14, -30) - streamer.origin_offset)
		overview.current = true
		await get_tree().create_timer(0.4).timeout
		await _smoke_image("overview")
		overview.queue_free()
		drone.camera.current = true
		for point: Vector3 in [Vector3(100, 115, -68), Vector3(-96, -43, -112), Vector3(240, 42, 0), Vector3(0, 1.2, 16)]:
			_deploy(point)
			await _wait_for_world()
			await get_tree().create_timer(0.5).timeout
			await _smoke_image("tour_" + str(int(point.y)))
		_show_workshop()
		await get_tree().create_timer(0.5).timeout
		await _smoke_image("workshop")
		_close_menu()
		var calibration := RadioCalibration.new()
		_mount_menu(calibration)
		await get_tree().create_timer(0.5).timeout
		await _smoke_image("calibration")
		_close_menu()
		_show_map()
		await get_tree().create_timer(0.5).timeout
		await _smoke_image("map")
		_close_menu()
	await _smoke_image("prototype")
	if DisplayServer.get_name() != "headless":
		await _capture()
	print("SMOKE_OK chunks=", streamer.active.size(), " collision_ready=", streamer.collision_ready(spawn_world))
	print("CONTENT_FINGERPRINT ", catalog.fingerprint())
	get_tree().quit()

func _smoke_image(name_value: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var directory := "user://test-captures"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-dir="):
				directory = argument.trim_prefix("--capture-dir=")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var target := directory.path_join(name_value + ".png")
		var error := get_viewport().get_texture().get_image().save_png(target)
		if error != OK:
			push_error("Smoke capture failed: " + target)

func _benchmark() -> void:
	await _wait_for_world()
	var window := get_window()
	window.size = Vector2i(1920, 1080)
	window.position = Vector2i(0, 0)
	var duration := 120.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			duration = clampf(float(argument.get_slice("=", 1)), 10, 900)
	var points: Array[Vector3] = [Vector3(0, 24, 0), Vector3(-180, 30, -160), Vector3(100, 145, -68), Vector3(-96, -25, -96), Vector3(280, 38, 160), Vector3(1200, 80, 128), Vector3(-1200, 80, -128)]
	var index := 0
	var elapsed := 0.0
	var next_move := 0.0
	var peak_memory := 0
	var peak_nodes := 0
	var freeze_frames := 0
	var started := Time.get_ticks_usec()
	var previous := started
	while elapsed < duration:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var delta := (now - previous) / 1000000.0
		previous = now
		elapsed = (now - started) / 1000000.0
		if elapsed >= next_move:
			_deploy(points[index % points.size()])
			index += 1
			next_move = elapsed + 3
		chase_camera.current = true
		chase_camera.position = drone.position + Vector3(5, 8, 16)
		chase_camera.look_at(drone.position)
		benchmark_samples.append(delta * 1000)
		peak_memory = maxi(peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if not streamer.collision_ready(_world_position()):
			freeze_frames += 1
		if int(elapsed) % 30 == 0 and int(elapsed - delta) != int(elapsed):
			print("BENCHMARK_PROGRESS seconds=", int(elapsed), " memory_mb=", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	benchmark_samples.sort()
	var report := {"kind": "scripted streaming tour, not human flight or RC validation", "measurement": "monotonic wall-clock frame intervals", "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(), "physics_backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "seed": store.data.seed, "resolution": str(window.size), "seconds": elapsed, "frames": benchmark_samples.size(), "p50_ms": benchmark_samples[int(benchmark_samples.size() * 0.5)], "p95_ms": benchmark_samples[int(benchmark_samples.size() * 0.95)], "p99_ms": benchmark_samples[int(benchmark_samples.size() * 0.99)], "max_ms": benchmark_samples.back(), "peak_static_memory_mb": peak_memory / 1048576.0, "final_static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "peak_nodes": peak_nodes, "final_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "collision_wait_frames": freeze_frames, "discarded_jobs": streamer.discarded}
	var file := FileAccess.open("res://../.local/benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BENCHMARK_RESULT ", JSON.stringify(report))
	get_tree().quit()
