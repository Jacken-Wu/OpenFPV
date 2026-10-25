extends Node3D
## Composition root: physics, content, world generation and progression stay separate.

var catalog: ContentCatalog
var store: ProgressStore
var assembler: DroneAssembler
var generator: WorldGenerator
var streamer: WorldStreamer
var drone: FPVDrone
var flight_input: FlightInput
var features: Node3D
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
var input_focused := true
var navigation := MapNavigation.new()
var navigation_hud: NavigationHUD
var navigation_preview: NavigationRoutePreview
var missions: MissionController
var hold_target_id := ""
var exploration: WorldExploration
var flight_region := Vector2i(999999, 999999)
var service_id := ""
var exploration_timer := 0.0
var menu_was_paused := true
var focus_was_paused := true
var focus_snapshot_valid := false
var unlock_notifications: UnlockNotifications
var pending_unlocks: Array[String] = []
var crosshair: Label
var flight_effects: FlightEffects
var flight_audio: FlightAudio
var event_audio: GameEventAudio
var developer_commands: DeveloperCommands
var console_history: Array[String] = []
var save_library: SaveLibrary
var photo_notice: PhotoNotice
var audio_mixer: GameAudioMixer
var biome_music: BiomeMusic
var input_display: InputDisplay
var bottom_bar: PanelContainer
var hud_shortcuts: Label
var challenge_view: MissionChallengeView

func _ready() -> void:
	if "--distribution-probe" in OS.get_cmdline_user_args():
		var report := BuildChannelProbe.run()
		print("CHANNEL_RESULT " + JSON.stringify(report))
		get_tree().quit(0 if report.ok else 1)
		return
	if "--build-info" in OS.get_cmdline_user_args():
		print("BUILD_INFO " + JSON.stringify({"configuration": "Debug" if OS.is_debug_build() else "Release", "debug": OS.is_debug_build(), "editor": OS.has_feature("editor"), "template": OS.has_feature("template"), "user_data_dir": OS.get_user_data_dir(), "licenses": AboutMenu.license_status()}))
		get_tree().quit()
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("OpenFPV · 重连边境" + (" [Debug]" if OS.is_debug_build() else ""))
	integration_mode = "--smoke" in OS.get_cmdline_user_args() or "--tour" in OS.get_cmdline_user_args() or "--test-session" in OS.get_cmdline_user_args() or "--benchmark" in OS.get_cmdline_user_args()
	catalog = ContentCatalog.new()
	if not catalog.errors.is_empty():
		push_error("Content validation failed: " + str(catalog.errors))
		get_tree().quit(1)
		return
	assembler = DroneAssembler.new(catalog)
	store = _create_progress_store()
	if save_library == null:
		save_library = SaveLibrary.new(catalog, store.path.get_base_dir())
	store.unlocked.connect(_on_unlocked)
	store.feedback.connect(_on_feedback)
	navigation = MapNavigation.new(int(store.data.world_version))
	if store.regions != null:
		exploration = WorldExploration.new(store, navigation)
		var saved: Array = store.data.deployment
		exploration.visit(Vector3(saved[0], saved[1], saved[2]))
		exploration.refresh(RegionalWorld.key_at(Vector3(saved[0], saved[1], saved[2])))
		navigation.teleport_resolver = store.portal_unlocked
	missions = MissionController.new(catalog, store, navigation)
	missions.balloon_popped.connect(_on_balloon_popped)
	missions.race_gate_passed.connect(_on_race_gate_passed)
	missions.race_finished.connect(_on_race_finished)
	missions.exploration = exploration
	var deployment: Variant = store.data.get("deployment", [0.0, 1.2, 16.0])
	if deployment is Array and deployment.size() == 3:
		var point := Vector3(float(deployment[0]), float(deployment[1]), float(deployment[2]))
		if point.is_finite():
			spawn_world = point
			# Older saves may contain shop/mission deployments. Resume at a real portal.
			if store.regions is BiomeWorld:
				var distance := INF
				for station: Dictionary in store.regions.region(RegionalWorld.key_at(point)).stations:
					if point.distance_squared_to(station.point) < distance:
						distance = point.distance_squared_to(station.point)
						spawn_world = station.point
			else:
				var nearest := navigation.nearest_teleport(point)
				if nearest != null:
					spawn_world = nearest.point
	generator = WorldGenerator.new(catalog, int(store.data.seed), int(store.data.world_version), int(store.data.get("extension_radius", 4)))
	generator.regions = store.regions
	WorldMaterials.warm_textures()
	_build_environment()
	streamer = WorldStreamer.new()
	streamer.generator = generator
	add_child(streamer)
	_build_features()
	flight_input = _create_flight_input()
	add_child(flight_input)
	drone = FPVDrone.new()
	add_child(drone)
	drone.set_simulation_paused(true)
	drone.position = spawn_world
	drone.camera.current = true
	var resolved := assembler.resolve(store.data.build, store.data.owned)
	if not resolved.ok:
		resolved = assembler.resolve(assembler.from_preset(catalog.manifest.initial_preset_id), store.data.owned)
		last_notice = "旧装配已失效，暂用初始套机；原配置仍保留在存档中。"
	drone.apply_spec(resolved.spec)
	drone.apply_tuning(FlightTuning.from_settings(store.data.settings))
	if store.data.settings.has("flight") and not FlightTuning.valid(store.data.settings.flight):
		last_notice = "已保存的飞行参数无效，本次使用默认参数；原存档保留。"
	chase_camera = Camera3D.new()
	chase_camera.fov = 75
	chase_camera.near = 0.15
	chase_camera.far = 1400
	add_child(chase_camera)
	flight_input.connection_lost.connect(func():
		radio_required = true
		_set_paused(true, "遥控器断开 · F2 重连或选择键盘")
		last_notice = "设备断开，已暂停。重连后不会自动恢复。")
	flight_input.action_requested.connect(_on_radio_action)
	_restore_radio()
	_build_hud()
	audio_mixer = GameAudioMixer.new()
	audio_mixer.settings = GameAudioSettings.from_settings(store.data.settings)
	add_child(audio_mixer)
	biome_music = BiomeMusic.new()
	add_child(biome_music)
	flight_audio = FlightAudio.new()
	flight_audio.drone = drone
	add_child(flight_audio)
	event_audio = GameEventAudio.new()
	add_child(event_audio)
	challenge_view = MissionChallengeView.new()
	add_child(challenge_view)
	developer_commands = DeveloperCommands.new(self)
	missions.sync_navigation(_world_position())
	_set_paused(true, "P 开始探索 · F2 校准遥控器")
	if not store.warning.is_empty():
		last_notice = store.warning
	if not save_library.warning.is_empty():
		last_notice = save_library.warning
	if "--smoke" in OS.get_cmdline_user_args() or "--tour" in OS.get_cmdline_user_args():
		_smoke_tour()
	if "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()

func _create_flight_input() -> FlightInput:
	return FlightInput.new()

func _create_progress_store() -> ProgressStore:
	save_library = SaveLibrary.new(catalog, "user://tests/integration_" + str(Time.get_ticks_usec()) if integration_mode else "user://profile")
	return ProgressStore.new(catalog, save_library.active_path())

func _restore_radio() -> void:
	var settings: Dictionary = store.data.settings
	radio_required = settings.get("radio_selection_required", false)
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
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("6396bd")
	sky_material.sky_horizon_color = Color("c4d6dd")
	sky_material.ground_bottom_color = Color("63716d")
	sky_material.ground_horizon_color = Color("c4d6dd")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d5dc")
	env.ambient_light_energy = 0.42
	env.fog_enabled = true
	env.fog_light_color = Color("86a6b3")
	env.fog_density = 0.0017
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -28, 0)
	sun.light_color = Color("fff0d8")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 480
	sun.directional_shadow_split_1 = 0.18
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_pancake_size = 320
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.2
	add_child(sun)

func _build_features() -> void:
	features = Node3D.new()
	add_child(features)
	_refresh_region_features()

func _refresh_region_features() -> void:
	for child in features.get_children():
		child.queue_free()
	if exploration == null:
		return
	var nearby: Array = store.regions.region(RegionalWorld.key_at(spawn_world if not is_instance_valid(drone) else _world_position())).stations
	for station: Dictionary in nearby:
		_marker("◇ " + station.name + " / 停稳后 E", station.point + Vector3(0, 3, 0), Color("83e2c7"))

func _marker(text: String, point: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.font_size = 36
	label.pixel_size = 0.012
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.visibility_range_end = 180.0
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
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(objective)
	telemetry = UIStyle.label("", 15, Color("cee2e7"))
	telemetry.position = Vector2(28, 135)
	root.add_child(telemetry)
	bottom_bar = PanelContainer.new()
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_left = 24
	bottom_bar.offset_right = -24
	bottom_bar.offset_top = -136
	bottom_bar.offset_bottom = -20
	var bottom_style := root.theme.get_stylebox("panel", "PanelContainer").duplicate() as StyleBoxFlat
	bottom_style.content_margin_left = 20
	bottom_style.content_margin_right = 20
	bottom_style.content_margin_top = 10
	bottom_style.content_margin_bottom = 10
	bottom_bar.add_theme_stylebox_override("panel", bottom_style)
	root.add_child(bottom_bar)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 14)
	bottom_bar.add_child(bottom_row)
	var column := UIStyle.column(bottom_row, 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.custom_minimum_size.x = 300
	prompt = UIStyle.label("", 18, Color("f0c485"))
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prompt)
	notice = UIStyle.label("", 15)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(notice)
	hud_shortcuts = UIStyle.label("P 暂停/恢复   R 重置到传送点   F1 帮助   F2 遥控器   E 交互   M 地图   C 视角   F12 拍照   / 控制台", 15, Color("8daab8"))
	hud_shortcuts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hud_shortcuts)
	var center := UIStyle.label("+", 20, Color.WHITE)
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -12
	center.offset_right = 12
	center.offset_top = -12
	center.offset_bottom = 12
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_theme_color_override("font_outline_color", Color("102030"))
	center.add_theme_constant_override("outline_size", 2)
	crosshair = center
	center.z_index = 100
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	navigation_hud = NavigationHUD.new()
	navigation_hud.navigation = navigation
	var navigation_layer := CanvasLayer.new()
	navigation_layer.layer = 21
	add_child(navigation_layer)
	navigation_layer.add_child(navigation_hud)
	center.reparent(navigation_hud)
	navigation_preview = NavigationRoutePreview.new()
	add_child(navigation_preview)
	menu_host = CenterContainer.new()
	menu_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_host)
	var notification_layer := CanvasLayer.new()
	notification_layer.layer = 20
	add_child(notification_layer)
	var notification_root := Control.new()
	notification_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notification_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_root.theme = root.theme
	notification_layer.add_child(notification_root)
	unlock_notifications = UnlockNotifications.new()
	notification_root.add_child(unlock_notifications)
	flight_effects = FlightEffects.new()
	root.add_child(flight_effects)
	photo_notice = PhotoNotice.new()
	root.add_child(photo_notice)
	navigation_hud.avoid_controls.assign([header, right, telemetry, bottom_bar, unlock_notifications, photo_notice])
	navigation_hud.bottom_panel = bottom_bar
	input_display = InputDisplay.new()
	input_display.input = flight_input
	bottom_row.add_child(input_display)
	for text in pending_unlocks:
		unlock_notifications.announce(text)
	pending_unlocks.clear()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(drone):
		return
	var ready := streamer.collision_ready(_world_position())
	ready_frames = maxi(0, ready_frames - 1) if ready else 2
	drone.set_simulation_paused(paused or not ready or ready_frames > 0)
	flight_input.enabled = not drone.freeze
	if not drone.freeze:
		flight_input.channels = flight_input.current_channels()
	drone.controls = flight_input.channels if not drone.freeze else Vector4.ZERO
	drone.update_altitude_protection(_world_position().y)
	if drone.position.length() > 1024:
		var shift := Vector3(WorldGenerator.key_at(drone.position)) * WorldGenerator.CHUNK_SIZE
		streamer.shift_origin(shift)
		drone.shift_origin(shift)
		features.position -= shift
		navigation_preview.position -= shift
		# Physics may rebase after the HUD's process callback, before drawing.
		navigation_hud.origin_offset = streamer.origin_offset
		navigation_hud.queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(drone):
		return
	_sync_action_context()
	var point := _world_position()
	exploration_timer -= delta
	if exploration != null and exploration_timer <= 0:
		exploration_timer = 0.5
		var discovery := exploration.visit(point)
		if discovery.get("changed", false):
			last_notice = discovery.message
	var region_key := RegionalWorld.key_at(point)
	if exploration != null and region_key != flight_region:
		flight_region = region_key
		exploration.refresh(region_key)
		if missions.tracked() != null and navigation.selected_id == missions.tracked().location_id:
			missions.sync_navigation(point)
		_refresh_region_features()
	streamer.focus = point
	prompt.text = "探索种子世界 · M 探索地图 · 任务按距离排序 · 落稳按 E 登记平台"
	if not paused:
		world_time += delta
	var near_interaction := _interactions(delta, point)
	challenge_view.controller = missions
	challenge_view.update_at(point, streamer.origin_offset, menu == null and not photo_notice.exposing, delta, paused)
	chase_camera.position = drone.position + drone.global_basis * Vector3(2.0, 1.6, 4.0)
	chase_camera.look_at(drone.position)
	var moving_mission := missions.tracked()
	if moving_mission != null and moving_mission.kind == "follow" and navigation.selected_id == moving_mission.location_id:
		var moving_location := navigation.selected()
		moving_location.point = missions.objective_point(moving_mission)
		if not navigation.route.is_empty():
			navigation.route[-1] = moving_location.point
	navigation.update(point)
	navigation_hud.camera = get_viewport().get_camera_3d()
	navigation_hud.origin_offset = streamer.origin_offset
	navigation_hud.drone_point = point
	crosshair.visible = menu == null
	input_display.preferences = InputDisplay.from_settings(store.data.settings)
	input_display.radio_required = radio_required
	input_display.visible = menu == null and not photo_notice.exposing and (input_display.preferences.sticks or input_display.preferences.switches)
	if input_display.visible:
		input_display.sample()
	navigation_hud.visible = menu == null and not photo_notice.exposing
	navigation_preview.update_route(navigation, point, streamer.origin_offset, get_viewport().get_camera_3d(), menu == null and not photo_notice.exposing)
	navigation_hud.queue_redraw()
	var biome := generator.biome_at(point)
	biome_music.observe(biome, delta)
	var input_name: String = flight_input.profile.get("name", "USB 遥控器") if flight_input.using_radio else "键盘调试"
	hud.text = "OPENFPV   /   自由探索 P1\n%s  ·  %s  ·  %s" % ["已暂停" if paused else "准备地图" if drone.freeze else "自由飞行", input_name, biome.display_name if biome else "边境"]
	var throttle := "%d%%" % (drone.effective_throttle() * 100)
	if drone.altitude_cutoff:
		throttle += "（保护 · 输入 %d%%）" % (flight_input.channels.w * 100)
	telemetry.text = "%.1f km/h   %.1f m   油门 %s\n姿态 %+.0f / %+.0f / %+.0f °\n推力 %.1f N   %.0f g   %d FPS\n120 Hz · 帧 %.1f ms · 块 %d / %d · 提交 %.1f ms\n世界 %.0f, %.0f, %.0f · 种子 %d" % [drone.motion_velocity().length() * 3.6, point.y, throttle, drone.rotation_degrees.x, drone.rotation_degrees.y, drone.rotation_degrees.z, drone.total_thrust, drone.mass * 1000, Engine.get_frames_per_second(), delta * 1000, streamer.active.size(), streamer.desired.size(), streamer.last_commit_ms, point.x, point.y, point.z, store.data.seed]
	var tracked := missions.tracked()
	var task_hint := "F3 领取探索委托 · 无倒计时"
	if tracked != null:
		task_hint = tracked.display_name + "\n"
		if tracked.kind == "photo":
			var assessment := _assess_photo(tracked)
			task_hint += "%s\n距离 %.0f m · 偏角 %.0f°" % [assessment.message, assessment.distance, assessment.angle]
		else:
			task_hint += missions.objective_hint(tracked)
	objective.text = "探索委托 / %d 信用点 · F3\n%s" % [store.data.credits, task_hint]
	flight_effects.update_warning(point.y, drone.altitude_cutoff, menu == null)
	photo_notice.suppressed = menu != null
	unlock_notifications.set_suppressed((menu != null and not menu is Workshop) or photo_notice.exposing)
	if drone.altitude_cutoff and menu == null:
		prompt.text = "高度保护：油门已强制关闭 · 下降至 280 m 后按当前遥控器油门恢复"
	if paused:
		prompt.text = "已暂停  /  " + (prompt.text if near_interaction else pause_reason)
	elif drone.freeze:
		prompt.text = "正在准备周围地图与碰撞……"
	notice.text = last_notice
	# Include wrapped notices and every auxiliary row when the bottom bar grows.
	bottom_bar.offset_top = -20 - maxf(99, bottom_bar.get_combined_minimum_size().y)

func _interactions(delta: float, point: Vector3) -> bool:
	if menu != null or not input_focused or (drone.freeze and not paused):
		task_hold = 0
		hold_target_id = ""
		return false
	var interaction := missions.interaction_at(point)
	var held := Input.is_physical_key_pressed(KEY_E) or flight_input.action_held("interact")
	var objective_result := missions.update_objective(point, drone.motion_velocity().length(), delta, held, paused, _challenge_camera(delta), drone.contact_serial)
	if not objective_result.is_empty():
		last_notice = objective_result.message
	var tracked := missions.tracked()
	if tracked != null and tracked.kind in ["survey", "circuit", "courier", "race", "balloons", "orbit", "follow", "regional"]:
		prompt.text = missions.objective_hint(tracked)
	if interaction != null:
		if hold_target_id != interaction.id:
			task_hold = 0
			hold_target_id = interaction.id
		prompt.text = "%s · 按住 E %.0f 秒%s" % [interaction.display_name, interaction.hold_seconds, "（暂停中可用）" if paused else " · 保持低速"]
		if store.mission_status(interaction.id) == "available":
			prompt.text = interaction.display_name + " · E 接取并追踪"
		if (Input.is_physical_key_pressed(KEY_E) or flight_input.action_held("interact")) and (drone.motion_velocity().length() < interaction.max_speed):
			if store.mission_status(interaction.id) == "available":
				var accepted := missions.accept(interaction.id, point)
				if not accepted.ok:
					last_notice = accepted.message
					task_hold = 0
					return true
			task_hold += delta
			prompt.text = "%s…… %d%%" % [interaction.display_name, mini(100, int(task_hold / interaction.hold_seconds * 100))]
			if task_hold >= interaction.hold_seconds:
				var result := missions.finish(interaction.id, {"point": point, "speed": drone.motion_velocity().length(), "seconds": task_hold})
				last_notice = result.message
				task_hold = 0
		else:
			task_hold = 0
		return true
	elif missions.platform_task_at(point) != null:
		var available := missions.platform_task_at(point)
		var action_text := "E 开始放球" if store.mission_status(available.id) == "active" else "E 接取并追踪"
		prompt.text = "%s · %s%s" % [available.display_name, action_text if _docked_task_id() == available.id else "降落在任务平台中央，停稳后按 E", "（再次挑战，无奖励）" if store.mission_completed_once(available.id) else ""]
		return true
	elif not _docked_station().is_empty():
		var repair := store.portal_repair_status(_docked_station().id)
		prompt.text = "传送网络离线 · 请完成本地区修复线路 %d/%d · E 查看解锁要求" % [repair.total - repair.remaining, repair.total] if repair.remaining > 0 else "已停靠综合服务平台 · E 商店 / 更换装备 / 参数微调"
		task_hold = 0
		return true
	else:
		task_hold = 0
		hold_target_id = ""
	return false

func _challenge_camera(delta: float) -> Dictionary:
	var mission := missions.tracked()
	if mission == null or mission.kind not in ["orbit", "follow"]:
		return {}
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var target := FlightChallengeRules.follow_point(mission, float(missions.challenge_state(mission).get("elapsed", 0)) + delta) if mission.kind == "follow" else mission.target_point
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, target - streamer.origin_offset)
	ray.exclude = [drone.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var clear := hit.is_empty() or (mission.kind == "orbit" and mission.target_bounds.has_point(hit.position + streamer.origin_offset))
	return {"origin": camera.global_position + streamer.origin_offset, "forward": -camera.global_basis.z, "clear": clear, "in_view": camera.is_position_in_frustum(target - streamer.origin_offset)}

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if menu is DeveloperConsole:
			if event.physical_keycode == KEY_ESCAPE:
				_close_menu()
				get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_ESCAPE:
			if menu is SaveMenu:
				_show_pause_menu()
			elif menu != null:
				_close_menu()
			else:
				_show_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if menu == null and (event.keycode == KEY_SLASH or event.physical_keycode == KEY_SLASH):
			_show_console()
			get_viewport().set_input_as_handled()
		elif menu is Workshop and event.physical_keycode == KEY_E:
			_perform_action("interact")
			get_viewport().set_input_as_handled()
		elif menu is RegionMap and event.physical_keycode in [KEY_M, KEY_F3]:
			_show_map()
			get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if menu is DeveloperConsole:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE, KEY_P:
			if menu != null:
				_close_menu()
				_resume_flight()
			else:
				_perform_action("toggle_pause")
		KEY_R: _perform_action("reset")
		KEY_ESCAPE:
			if menu != null:
				_close_menu()
			else:
				_show_pause_menu()
		KEY_F1: _perform_action("help")
		KEY_F2: _show_radio()
		KEY_F3: _perform_action("missions")
		KEY_TAB: last_notice = "请停在任一服务平台上按 E，更换装备或微调参数。"
		KEY_M: _perform_action("map")
		KEY_C: _perform_action("toggle_camera")
		KEY_F12: _perform_action("photo")
		KEY_E: _perform_action("interact")

func _on_radio_action(action: String) -> void:
	if input_focused and (menu == null or (menu is Workshop and action == "interact") or (menu is RegionMap and action in ["map", "missions"])):
		_perform_action(action)

func _perform_action(action: String) -> void:
	match action:
		"toggle_pause": _toggle_pause()
		"pause": _set_paused(true)
		"resume": _resume_flight()
		"reset": _deploy(spawn_world)
		"reset_attitude": _reset_attitude()
		"help": _show_help()
		"workshop": last_notice = "装备调整已迁到服务平台，请停稳后按交互键。"
		"map": _show_map()
		"missions": _show_missions()
		"toggle_camera":
			if drone.camera.current:
				chase_camera.current = true
			else:
				drone.camera.current = true
		"photo": _capture()
		"interact":
			if menu is Workshop and input_focused:
				menu.submit(true)
				return
			if menu != null or not input_focused:
				return
			# A delivery at its final platform consumes the same interaction first.
			var result := missions.update_objective(_world_position(), drone.motion_velocity().length(), 0, true, paused)
			if not result.is_empty():
				last_notice = result.message
				return
			var accepted := missions.accept_nearby(_world_position(), drone.motion_velocity().length(), _docked_task_id())
			if not accepted.is_empty():
				last_notice = accepted.message
				return
			if missions.interaction_at(_world_position()) != null:
				return
			_show_workshop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(drone) and not integration_mode:
		if not focus_snapshot_valid:
			focus_was_paused = paused
			focus_snapshot_valid = true
		input_focused = false
		_sync_action_context()
		_set_paused(true, "窗口失焦 · 返回后恢复原状态")
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and is_instance_valid(flight_input):
		input_focused = true
		_sync_action_context()
		if focus_snapshot_valid:
			focus_snapshot_valid = false
			if not focus_was_paused and menu == null:
				_resume_flight()

func _sync_action_context() -> void:
	if is_instance_valid(flight_input):
		flight_input.set_actions_enabled(input_focused and (menu == null or menu is RegionMap or menu is Workshop))

func _on_unlocked(category: String, title: String) -> void:
	_on_feedback(category)
	var text := ("成就已解锁 · " if category == "achievement" else "传送点已解锁 · " if category == "portal" else "新地区地图已解锁 · " if category == "region" else "发现未测绘地区 · ") + title
	if is_instance_valid(unlock_notifications):
		unlock_notifications.announce(text)
	else:
		pending_unlocks.append(text)

func _on_feedback(event: String) -> void:
	if is_instance_valid(event_audio):
		event_audio.play_event(event)

func _set_paused(value: bool, reason: String = "P / 空格或绑定开关恢复飞行") -> void:
	paused = value
	pause_reason = reason
	flight_input.enabled = not value
	if value:
		if missions != null:
			var checkpoint := missions.flush_challenge()
			if not checkpoint.get("ok", true):
				last_notice = checkpoint.message
			missions.invalidate_motion()
		drone.set_simulation_paused(true)
		drone.stop_control()
		flight_input.channels = Vector4.ZERO
		task_hold = 0.0

func _toggle_pause() -> void:
	if paused:
		_resume_flight()
	else:
		_set_paused(true)

func _resume_flight() -> void:
	if menu != null or not input_focused:
		return
	if radio_required or (flight_input.using_radio and not flight_input.radio_connected()):
		last_notice = "先按 F2 连接遥控器，或明确选择键盘调试。"
		return
	_set_paused(false)

func _world_position() -> Vector3:
	return drone.position + streamer.origin_offset

func _deploy(point: Vector3) -> void:
	_on_feedback("teleport")
	missions.invalidate_motion()
	spawn_world = point
	drone.world_origin_offset = streamer.origin_offset
	navigation.rebuild_route(point)
	drone.reset_drone(point - streamer.origin_offset)
	flight_input.reset_throttle()
	drone.set_simulation_paused(true)
	flight_input.enabled = false
	ready_frames = 2
	last_notice = "已回到部署点 · 按 P 或绑定开关恢复" if paused else "已回到部署点 · 地图就绪后继续飞行"
	if not integration_mode:
		var result := store.save_deployment(point)
		if not result.ok:
			last_notice = result.message

func _debug_teleport(point: Vector3) -> void:
	missions.invalidate_motion()
	# Developer movement does not overwrite the saved safe deployment or portal locks.
	drone.set_simulation_paused(true)
	drone.world_origin_offset = streamer.origin_offset
	drone.reset_drone(point - streamer.origin_offset)
	streamer.focus = point
	navigation.rebuild_route(point)
	ready_frames = 2
	flight_input.enabled = false
	last_notice = "已进行调试传送 · 周围地图就绪后恢复原状态"

func _show_console() -> void:
	var console := DeveloperConsole.new()
	console.history = console_history
	console.history_index = console_history.size()
	console.submitted.connect(func(command: String):
		var result := developer_commands.execute(command)
		if command.strip_edges().trim_prefix("/").to_lower() == "clear":
			console.output.clear()
		else:
			console.write(result))
	_mount_menu(console)

func _show_pause_menu() -> void:
	var panel := PauseMenu.new()
	panel.resume_requested.connect(func(): _close_menu(); _resume_flight())
	panel.saves_requested.connect(_show_save_menu)
	panel.help_requested.connect(_show_help)
	panel.radio_requested.connect(_show_radio)
	panel.audio_requested.connect(_show_audio_menu)
	panel.input_display_requested.connect(_show_input_display_menu)
	panel.achievements_requested.connect(_show_achievements)
	panel.about_requested.connect(_show_about)
	panel.quit_requested.connect(func():
		var result := save_library.save(store)
		if result.ok:
			get_tree().quit()
		else:
			panel.feedback.text = result.message)
	_mount_menu(panel)

func _show_about() -> void:
	var panel := AboutMenu.new()
	panel.closed.connect(_show_pause_menu)
	_mount_menu(panel)

func _show_achievements() -> void:
	var panel := AchievementsMenu.new()
	panel.store = store
	panel.closed.connect(_show_pause_menu)
	_mount_menu(panel)

func _show_save_menu() -> void:
	var panel := SaveMenu.new()
	panel.library = save_library
	panel.current = store
	panel.closed.connect(_show_pause_menu)
	panel.activated.connect(_switch_store)
	_mount_menu(panel)

func _show_audio_menu() -> void:
	var panel := AudioMenu.new()
	panel.mixer = audio_mixer
	panel.store = store
	panel.closed.connect(_show_pause_menu)
	_mount_menu(panel)

func _show_input_display_menu() -> void:
	var panel := InputDisplayMenu.new()
	panel.store = store
	panel.closed.connect(_show_pause_menu)
	_mount_menu(panel)

func _switch_store(next: ProgressStore, message: String) -> void:
	_close_menu(false)
	_set_paused(true)
	store = next
	audio_mixer.apply(GameAudioSettings.from_settings(store.data.settings))
	store.unlocked.connect(_on_unlocked)
	store.feedback.connect(_on_feedback)
	generator = WorldGenerator.new(catalog, int(store.data.seed), int(store.data.world_version), int(store.data.get("extension_radius", 4)))
	generator.regions = store.regions
	streamer.replace_generator(generator)
	navigation = MapNavigation.new(int(store.data.world_version))
	navigation.teleport_resolver = store.portal_unlocked
	exploration = WorldExploration.new(store, navigation)
	var saved: Array = store.data.deployment
	var point := Vector3(saved[0], saved[1], saved[2])
	var requested := point
	var nearest := INF
	for station: Dictionary in store.regions.region(RegionalWorld.key_at(requested)).stations:
		var distance := requested.distance_squared_to(station.point)
		if distance < nearest:
			nearest = distance
			point = station.point
	exploration.visit(point)
	exploration.refresh(RegionalWorld.key_at(point))
	flight_region = Vector2i(999999, 999999)
	missions = MissionController.new(catalog, store, navigation)
	missions.balloon_popped.connect(_on_balloon_popped)
	missions.race_gate_passed.connect(_on_race_gate_passed)
	missions.race_finished.connect(_on_race_finished)
	missions.exploration = exploration
	navigation_hud.navigation = navigation
	features.hide()
	features.queue_free()
	_build_features()
	_deploy(point)
	var resolved := assembler.resolve(store.data.build, store.data.owned)
	if not resolved.ok:
		resolved = assembler.resolve(assembler.from_preset(catalog.manifest.initial_preset_id), store.data.owned)
	drone.apply_spec(resolved.spec)
	drone.apply_tuning(FlightTuning.from_settings(store.data.settings))
	developer_commands.last_location.clear()
	last_notice = message + " · 按 P 或恢复开关开始"

func _reset_attitude() -> void:
	missions.invalidate_motion()
	drone.reset_attitude()
	flight_input.reset_throttle()
	drone.set_simulation_paused(true)
	flight_input.enabled = false
	ready_frames = maxi(ready_frames, 2)
	task_hold = 0.0
	last_notice = "已原地回正，保留位置和朝向，速度已清零。"

func _mount_menu(value: Control) -> void:
	if is_instance_valid(input_display):
		input_display.hide()
	if menu == null:
		menu_was_paused = paused
	else:
		_close_menu(false)
	_set_paused(true, "正在查看页面")
	menu = value
	_sync_action_context()
	menu_host.add_child(menu)
	unlock_notifications.set_suppressed(not menu is Workshop or photo_notice.exposing)

func _close_menu(restore_state: bool = true) -> void:
	var had_menu := is_instance_valid(menu)
	if had_menu:
		menu_host.remove_child(menu)
		menu.queue_free()
	menu = null
	_sync_action_context()
	unlock_notifications.set_suppressed(photo_notice.exposing)
	if had_menu and restore_state:
		if menu_was_paused:
			_set_paused(true)
		elif input_focused:
			_resume_flight()
		else:
			focus_was_paused = false

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
	column.add_child(UIStyle.label("先按 F2 设置遥控器，一次采集四轴行程，再核对分配和正反。\n本作采用 Acro：摇杆控制转动速度，松杆会保持倾角，机体不会自动回平。\n按 P / 空格或绑定开关恢复即可飞行，按当前油门输出；无需电机解锁。", 18))
	column.add_child(UIStyle.label("280 m 以上红边闪烁；超过 300 m 强制断油，降回 280 m 后按当前油门恢复。\n/ 打开开发控制台，/help 查看指令，/location list 查看群系，Esc 关闭。\nEsc → 声音设置：输出设备、主音量、电机、快门和群系音乐；/volume 仅本次。\nF2 → 编辑配置：各轴0～20%死区，油门在最低端抑制漂移。", 17))
	column.add_child(UIStyle.label("键盘调试：W/S 俯仰 · A/D 横滚 · J/L 偏航 · ↑/↓ 持续调整油门\nP / 空格 暂停或恢复 · R 回到部署点 · C 第一/第三人称\n平台 E 进入，再按 E 保存退出 · M / F3 探索地图 · E 交互 · F12 拍照\n地图点击选点、空白处建立临时路标；再次按地图键关闭。\nF2 → 编辑配置 → 动作绑定，为各档位选择动作。\n失焦返回恢复原状态；遥控器断连仍需重连或明确选择键盘。", 18))
	column.add_child(UIStyle.label("群系按不规则边界分布，浮岛群与地下迷宫独立生成，各有平台与委托。\n在平台中央停稳后按 E 打开综合服务：购买配件 / 套机、更换装备、微调参数。\nTab 不再打开装备台。遥控器也使用同一个交互动作。\nM / F3 同一地图：左侧任务按距离排序，右侧显示选中地点信息。\n地图到达后解锁，地下需完成测绘任务；平台停稳按 E 后才能传送。\n已解锁地区一直保留；迷宫按走廊导航，地表/空中参考航线不自动避障。", 18, Color("e5c291")))
	var seed_row := HBoxContainer.new()
	column.add_child(seed_row)
	seed_row.add_child(UIStyle.label("世界种子", 17))
	var seed_field := SpinBox.new()
	seed_field.min_value = -2147483648
	seed_field.max_value = 2147483647
	seed_field.step = 1
	seed_field.value = int(store.data.seed)
	seed_field.custom_minimum_size.x = 220
	seed_row.add_child(seed_field)
	seed_row.add_child(UIStyle.button("用此种子新建世界…", func():
		var chosen_seed := int(seed_field.value)
		var confirm := _simple_menu("按种子新建世界")
		confirm.add_child(UIStyle.label("种子 %d\n保存当前世界并创建独立新存档，回到新世界的初始服务平台。\n原世界进度保留，遥控器和飞行操控设置继续使用。" % chosen_seed, 18))
		confirm.add_child(UIStyle.button("确认新建世界", func():
			var result := save_library.new_world(store, "世界 %d" % chosen_seed, chosen_seed)
			if result.ok:
				_switch_store(result.store, result.message)
			else:
				last_notice = result.message))
		confirm.add_child(UIStyle.button("返回", _show_help))))
	column.add_child(UIStyle.button("关闭帮助 · 恢复进入前状态", _close_menu))

func _restart_seed(seed_value: int) -> Dictionary:
	var result := store.reset_world(seed_value)
	if not result.ok:
		last_notice = result.message
		return result
	_close_menu()
	_set_paused(true)
	generator = WorldGenerator.new(catalog, int(store.data.seed), int(store.data.world_version), int(store.data.get("extension_radius", 4)))
	generator.regions = store.regions
	streamer.replace_generator(generator)
	navigation = MapNavigation.new(int(store.data.world_version))
	exploration = WorldExploration.new(store, navigation)
	exploration.visit(store.regions.spawn_point())
	exploration.refresh(RegionalWorld.key_at(store.regions.spawn_point()))
	navigation.teleport_resolver = store.portal_unlocked
	flight_region = Vector2i.ZERO
	missions = MissionController.new(catalog, store, navigation)
	missions.balloon_popped.connect(_on_balloon_popped)
	missions.race_gate_passed.connect(_on_race_gate_passed)
	missions.race_finished.connect(_on_race_finished)
	missions.exploration = exploration
	navigation_hud.navigation = navigation
	features.hide()
	features.queue_free()
	_build_features()
	var saved: Array = store.data.deployment
	_deploy(Vector3(saved[0], saved[1], saved[2]))
	drone.apply_spec(assembler.resolve(store.data.build, store.data.owned).spec)
	drone.apply_tuning(FlightTuning.from_settings(store.data.settings))
	last_notice = result.message
	return result

func _show_radio() -> void:
	var panel := RadioMenu.new()
	panel.settings = store.data.settings.duplicate(true)
	panel.edit_requested.connect(func(key: String, device: int): _edit_radio(store.data.settings.get("radio_profiles", {}).get(key, {}), key, device))
	panel.use_requested.connect(func(key: String, device: int):
		if not Input.get_connected_joypads().has(device):
			panel.feedback.text = "设备已断开，请刷新。"
			return
		var profile: Dictionary = store.data.settings.radio_profiles[key].duplicate(true)
		profile.guid = Input.get_joy_guid(device)
		profile.device_name = Input.get_joy_name(device)
		_accept_radio(profile, device, key))
	panel.delete_requested.connect(func(key: String):
		var result := _delete_radio_profile(key)
		panel.settings = store.data.settings.duplicate(true)
		panel.refresh()
		panel.feedback.text = result.message)
	panel.keyboard_requested.connect(func():
		var settings: Dictionary = store.data.settings.duplicate(true)
		settings.radio_active = false
		settings.radio_selection_required = false
		var result := store.save_settings(settings)
		if not result.ok:
			panel.feedback.text = result.message
			return
		flight_input.using_radio = false
		flight_input.reset_throttle()
		radio_required = false
		last_notice = "已切换键盘调试 · P 恢复"
		_close_menu())
	panel.closed.connect(_close_menu)
	_mount_menu(panel)

func _edit_radio(profile: Dictionary = {}, profile_key: String = "", device: int = -1) -> void:
	var calibration := RadioCalibration.new()
	calibration.initial_profile = profile.duplicate(true)
	calibration.existing_profiles = store.data.settings.get("radio_profiles", {}).duplicate(true)
	calibration.editing_key = profile_key
	calibration.preferred_device = device
	calibration.allow_offline_edit = not profile_key.is_empty() and device < 0
	calibration.closed.connect(_show_radio)
	calibration.accepted.connect(func(value: Dictionary, selected: int): _accept_radio(value, selected, profile_key))
	_mount_menu(calibration)

func _accept_radio(profile: Dictionary, device: int, profile_key: String = "") -> void:
	if not FlightInput.valid_profile(profile) or (device >= 0 and not Input.get_connected_joypads().has(device)) or (device < 0 and profile_key.is_empty()):
		last_notice = "遥控器配置无效或设备已断开，请重新连接。"
		return
	var prepared := RadioProfiles.upsert(store.data.settings, profile, profile_key, device >= 0)
	if not prepared.ok:
		last_notice = prepared.message
		if menu is RadioCalibration:
			menu.status.text = prepared.message
		return
	var result := store.save_settings(prepared.settings)
	if not result.ok:
		last_notice = result.message
		if menu is RadioCalibration:
			menu.status.text = result.message
		return
	if device >= 0:
		flight_input.activate_profile(prepared.profile, device)
		radio_required = false
	last_notice = "遥控器配置已保存" + (" · 按 P / 空格或绑定开关恢复飞行" if device >= 0 else " · 连接设备后选择使用")
	_show_radio()

func _delete_radio_profile(key: String) -> Dictionary:
	var prepared := RadioProfiles.remove(store.data.settings, key)
	if not prepared.ok:
		return prepared
	var result := store.save_settings(prepared.settings)
	if not result.ok:
		return result
	if prepared.active:
		_set_paused(true, "当前遥控器配置已删除 · F2 重新选择输入")
		flight_input.using_radio = false
		flight_input.profile.clear()
		flight_input.reset_throttle()
		flight_input.reset_auxiliary_tracking()
		radio_required = true
	return {"ok": true, "message": "配置已删除" + (" · 请重新选择输入" if prepared.active else "")}

func _on_balloon_popped(point: Vector3, index: int) -> void:
	challenge_view.effects.spawn(point, index)
	flight_audio.play_balloon(point - streamer.origin_offset)

func _on_race_gate_passed(_stage: int) -> void:
	flight_audio.play_race_gate()

func _on_race_finished() -> void:
	flight_audio.play_race_finish()

func _docked_task_id() -> String:
	if not streamer.collision_ready(_world_position()) or ready_frames > 0 or drone.reset_pending or drone.motion_velocity().length() > 0.6 or drone.global_basis.y.dot(Vector3.UP) < 0.85:
		return ""
	var mission := missions.platform_task_at(_world_position())
	if mission == null or mission.pickup_platform.is_empty():
		return ""
	var pad: Dictionary = mission.pickup_platform
	var offset: Vector3 = _world_position() - pad.point
	if absf(offset.x) > float(pad.half) - 0.6 or absf(offset.z) > float(pad.half) - 0.6 or absf(_world_position().y - float(pad.top)) > 0.16:
		return ""
	var ray := PhysicsRayQueryParameters3D.create(drone.global_position + Vector3.UP * 0.05, drone.global_position - Vector3.UP * 0.25)
	ray.exclude = [drone.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return mission.id if not hit.is_empty() and hit.normal.dot(Vector3.UP) > 0.95 and absf(hit.position.y + streamer.origin_offset.y - float(pad.top)) < 0.04 else ""

func _docked_station() -> Dictionary:
	if exploration == null or not streamer.collision_ready(_world_position()) or ready_frames > 0 or drone.reset_pending or drone.motion_velocity().length() > 0.6 or drone.global_basis.y.dot(Vector3.UP) < 0.85:
		return {}
	var station := exploration.station_at(_world_position())
	if station.is_empty():
		return {}
	var ray := PhysicsRayQueryParameters3D.create(drone.global_position + Vector3.UP * 0.05, drone.global_position - Vector3.UP * 0.25)
	ray.exclude = [drone.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.95 or absf(hit.position.y + streamer.origin_offset.y - float(station.top)) > 0.04 or absf(_world_position().y - float(station.top)) > 0.16:
		return {}
	return station

func _service_valid(id: String) -> bool:
	var station := _docked_station()
	return not station.is_empty() and station.id == id

func _show_workshop() -> void:
	var station := _docked_station()
	if station.is_empty():
		last_notice = "请先在服务平台中央低速停稳，再按 E。"
		return
	var unlocked := store.unlock_portal(station.id)
	if not unlocked.ok:
		last_notice = unlocked.message
		return
	if unlocked.get("changed", false):
		last_notice = "已登记平台，解锁传送：" + station.name
	service_id = station.id
	var opened_id := service_id
	var workshop := Workshop.new()
	workshop.catalog = catalog
	workshop.store = store
	workshop.station_name = station.name
	workshop.city_tag = station.city_tag
	workshop.build = store.data.build.duplicate(true)
	if not assembler.resolve(workshop.build, store.data.owned).ok:
		workshop.build = assembler.from_preset(catalog.manifest.initial_preset_id)
	workshop.flight_profile = drone.tuning.duplicate(true)
	workshop.closed.connect(_close_menu)
	workshop.apply_requested.connect(func(build: Dictionary, profile: Dictionary):
		if not paused or not _service_valid(opened_id):
			workshop.message = "已离开停靠平台，无法应用装配；请重新停稳。"
			workshop._preview()
			return
		var settings: Dictionary = store.data.settings.duplicate(true)
		settings.flight = profile.duplicate(true)
		settings.erase("rates")
		settings.erase("expo")
		var result := store.save_loadout(build, settings)
		if result.ok:
			drone.apply_spec(assembler.resolve(build, store.data.owned).spec)
			drone.apply_tuning(profile)
			result.message = "装配与操控设置已保存并应用"
		workshop.message = result.message
		workshop._preview()
		last_notice = result.message
		var close_after := workshop.close_after_apply
		workshop.close_after_apply = false
		if result.ok and close_after:
			_close_menu())
	workshop.purchase_requested.connect(func(id: String):
		if not _service_valid(opened_id):
			workshop.message = "已离开停靠平台，无法购买。"
		else:
			var result := store.purchase(id, station.city_tag)
			workshop.message = result.message
			last_notice = result.message
			workshop.refresh_shop()
		workshop._preview())
	_mount_menu(workshop)

func _show_map() -> void:
	_open_exploration_map(false)

func _show_missions() -> void:
	_open_exploration_map(true)

func _open_exploration_map(tasks: bool) -> void:
	if menu is RegionMap:
		_close_menu()
		return
	if exploration != null:
		exploration.visit(_world_position())
		exploration.refresh(RegionalWorld.key_at(_world_position()))
	var map_view := RegionMap.new()
	map_view.navigation = navigation
	map_view.controller = missions
	map_view.open_tasks = tasks
	map_view.biomes = exploration.biomes if exploration != null else generator.biomes
	map_view.drone_point = _world_position()
	var forward := -drone.global_basis.z
	map_view.heading = Vector2(forward.x, forward.z)
	map_view.teleport_requested.connect(_teleport_to)
	map_view.closed.connect(_close_menu)
	map_view.accept_requested.connect(func(id: String):
		var result := missions.accept(id, _world_position())
		last_notice = result.message
		map_view.message.text = result.message
		if result.ok:
			map_view.task_filter.select(1)
		map_view.refresh())
	map_view.track_requested.connect(func(id: String):
		var result := missions.track(id, _world_position())
		last_notice = result.get("message", "已更新追踪")
		map_view.message.text = last_notice
		map_view.refresh())
	_mount_menu(map_view)

func _teleport_to(id: String) -> bool:
	var location := navigation.teleport_location(id)
	if location == null:
		last_notice = "只能传送到已登记的平台。请先飞抵平台，落稳后按 E 解锁。"
		return false
	_deploy(location.point)
	_close_menu()
	last_notice = "已传送至" + location.display_name
	return true

func _show_shop() -> void:
	_show_workshop()
	if menu is Workshop:
		menu.tabs.current_tab = 3

func _photo_selection() -> Dictionary:
	var mission := missions.photo_candidate()
	var assessment: Dictionary = _assess_photo(mission) if mission != null else {}
	if not assessment.get("ok", false):
		for candidate: MissionDefinition in missions.definitions():
			if candidate.kind != "photo" or store.mission_status(candidate.id) != "active" or candidate == mission:
				continue
			var other := _assess_photo(candidate)
			if other.get("ok", false):
				return {"mission": candidate, "assessment": other}
	return {"mission": mission, "assessment": assessment}

func _capture() -> void:
	if screenshot_busy or DisplayServer.get_name() == "headless":
		return
	if menu != null or not input_focused:
		last_notice = "请关闭菜单并回到飞行画面后拍照。"
		return
	screenshot_busy = true
	photo_notice.exposing = true
	navigation_hud.hide()
	navigation_preview.hide()
	photo_notice.hide()
	input_display.hide()
	challenge_view.set_labels_visible(false)
	await RenderingServer.frame_post_draw
	if menu != null or not input_focused:
		photo_notice.exposing = false
		screenshot_busy = false
		return
	# Assess this rendered frame, not the later camera pose after the file writes.
	var selection := _photo_selection()
	var mission: MissionDefinition = selection.mission
	var assessment: Dictionary = selection.assessment
	var camera := get_viewport().get_camera_3d()
	var camera_world := camera.global_transform
	camera_world.origin += streamer.origin_offset
	var metadata := {"seed": store.data.seed, "world_version": store.data.world_version, "build": store.data.build, "position": str(_world_position()), "rotation": str(drone.rotation), "input": flight_input.profile, "settings": store.data.settings, "camera_position": [camera_world.origin.x, camera_world.origin.y, camera_world.origin.z], "camera_forward": [-camera_world.basis.z.x, -camera_world.basis.z.y, -camera_world.basis.z.z], "mission_id": mission.id if mission != null and mission.kind == "photo" else "", "photo_check": assessment}
	var capture_directory := "user://tests/captures" if integration_mode else "user://captures"
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := capture_directory.path_join(stamp + "-" + str(Time.get_ticks_usec()) + ".png")
	var saved := _save_capture(get_viewport().get_texture().get_image(), path, metadata)
	photo_notice.exposing = false
	last_notice = saved.message
	if saved.ok:
		# This feedback starts after saving the clean exposure, so it is never in the photo.
		flight_effects.shutter_flash()
		flight_audio.play_shutter()
		photo_notice.announce(path)
		if integration_mode:
			print("PHOTO_CAPTURE_OK ", ProjectSettings.globalize_path(path))
		if not assessment.is_empty():
			if assessment.ok:
				var result := missions.finish(mission.id, {"photo_path": path})
				last_notice = result.message
			else:
				last_notice = "照片已保存 · 委托未完成：" + String(assessment.message)
	if saved.ok:
		await get_tree().create_timer(0.20).timeout
	screenshot_busy = false

func _save_capture(capture_image: Image, path: String, metadata: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path.get_base_dir()) or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return {"ok": false, "message": "无法创建照片目录，任务未提交。"}
	if capture_image.save_png(path) != OK:
		return {"ok": false, "message": "照片保存失败，任务未提交。"}
	var details := FileAccess.open(path.get_basename() + ".json", FileAccess.WRITE)
	if details == null:
		return {"ok": false, "message": "照片记录保存失败，任务未提交。"}
	details.store_string(JSON.stringify(metadata, "\t"))
	details.flush()
	var error := details.get_error()
	details.close()
	if error != OK:
		return {"ok": false, "message": "照片记录写入失败，任务未提交。"}
	return {"ok": true, "message": "照片已保存：" + ProjectSettings.globalize_path(path)}

func _assess_photo(mission: MissionDefinition) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var camera_world := camera.global_transform
	camera_world.origin += streamer.origin_offset
	var ready := streamer.collision_ready(camera_world.origin) and streamer.collision_ready(mission.target_point)
	var preliminary := PhotoObjective.evaluate(mission, camera_world, true, ready)
	if not preliminary.ok:
		return preliminary
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, mission.target_point - streamer.origin_offset)
	query.exclude = [drone.get_rid()]
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var unobstructed := hit.is_empty() or mission.target_bounds.has_point(hit.position + streamer.origin_offset)
	return PhotoObjective.evaluate(mission, camera_world, unobstructed, ready)

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
		var plan := store.regions.region(Vector2i.ZERO)
		for station: Dictionary in plan.stations:
			_deploy(station.point)
			await _wait_for_world()
			_set_paused(false)
			await get_tree().create_timer(1.0).timeout
			_set_paused(true)
			await _smoke_image("tour_" + station.id.replace(":", "-"))
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
	var points: Array[Vector3] = []
	for key: Vector2i in [Vector2i.ZERO, Vector2i(-4, 3), Vector2i(8, -8), Vector2i(40, 20), Vector2i(-40, -20)]:
		var plan := store.regions.region(key)
		for station: Dictionary in plan.stations:
			points.append(station.point + Vector3(0, 5 if station.get("layer", "") == "maze" else 12, 0 if station.get("layer", "") == "maze" else 8))

	var index := 0
	var elapsed := 0.0
	var next_move := 0.0
	var peak_memory := 0
	var peak_nodes := 0
	var freeze_frames := 0
	var slow_frames: Array[Dictionary] = []
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
		var underground := generator.biome_at(_world_position()).tags.has("underground")
		chase_camera.position = drone.position + (Vector3(2, 2, 5) if underground else Vector3(5, 8, 16))
		chase_camera.look_at(drone.position)
		benchmark_samples.append(delta * 1000)
		if delta > 0.025 and slow_frames.size() < 128:
			slow_frames.append({"seconds": elapsed, "ms": delta * 1000, "commit_ms": streamer.last_commit_ms, "point_index": posmod(index - 1, points.size()), "active": streamer.active.size(), "pending": streamer.pending.size()})
		peak_memory = maxi(peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if not streamer.collision_ready(_world_position()):
			freeze_frames += 1
		if int(elapsed) % 30 == 0 and int(elapsed - delta) != int(elapsed):
			print("BENCHMARK_PROGRESS seconds=", int(elapsed), " memory_mb=", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	benchmark_samples.sort()
	var route_points: Array = []
	for point in points:
		route_points.append([point.x, point.y, point.z])
	var report := {"kind": "scripted streaming tour, not human flight or RC validation", "measurement": "monotonic wall-clock frame intervals", "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(), "physics_backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "seed": store.data.seed, "resolution": str(window.size), "seconds": elapsed, "frames": benchmark_samples.size(), "p50_ms": benchmark_samples[int(benchmark_samples.size() * 0.5)], "p95_ms": benchmark_samples[int(benchmark_samples.size() * 0.95)], "p99_ms": benchmark_samples[int(benchmark_samples.size() * 0.99)], "max_ms": benchmark_samples.back(), "peak_static_memory_mb": peak_memory / 1048576.0, "final_static_memory_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, "peak_nodes": peak_nodes, "final_nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "collision_wait_frames": freeze_frames, "discarded_jobs": streamer.discarded}
	var file := FileAccess.open("res://../.local/benchmark.json", FileAccess.WRITE)
	report.world_version = int(store.data.world_version)
	report.route = route_points
	report.slow_frames = slow_frames
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BENCHMARK_RESULT ", JSON.stringify(report))
	get_tree().quit()
