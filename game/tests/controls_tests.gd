extends SceneTree
class VirtualInput extends FlightInput:
	var connected := true
	var axes: Array[float] = [0.7, -0.5, 0.25, -0.6, 1.0, 0.0]
	var buttons: Array[bool] = [true]
	func radio_connected() -> bool:
		return connected
	func radio_axis(index: int) -> float:
		return axes[index] if index < axes.size() else 0.0
	func radio_buttons() -> Array[bool]:
		return buttons
class TestGame extends "res://scripts/main.gd":
	var virtual_input := VirtualInput.new()
	func _create_flight_input() -> FlightInput:
		return virtual_input
var failed := 0
var checked := 0
var directory := "res://../.local/test-results/controls"
var game: TestGame

func _initialize() -> void:
	Engine.max_fps = 120
	call_deferred("run")
func check(value: bool, description: String) -> void:
	checked += 1
	print("PASS " if value else "FAIL ", description)
	if not value:
		failed += 1
func frames(count: int) -> void:
	for index in count:
		await physics_frame
func screenshot(name_text: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(name_text + ".png")) == OK, "capture " + name_text)
func profile(name_text: String = "试飞", guid: String = "test") -> Dictionary:
	var result := {"name": name_text, "guid": guid, "device_name": "测试遥控器", "axes": {}, "auxiliary": [{"id": "switch", "name": "三档开关", "source": "axis", "axis": 4, "min": -1.0, "max": 1.0, "invert": false, "type": "three_position", "bindings": {"2": "reset"}}, {"id": "button", "name": "回弹", "source": "buttons", "buttons": [0], "invert": false, "type": "momentary"}]}
	for index in 4:
		result.axes[FlightInput.CHANNELS[index]] = {"axis": index, "min": -1.0, "max": 1.0, "center": 0.0, "invert": false, "deadzone": 0.02}
	return result

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			directory = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var catalog := ContentCatalog.new()
	var store := ProgressStore.new(catalog, "user://tests/controls_%d/progress.json" % Time.get_ticks_usec())
	var settings := {"radio_profiles": {"legacy-a": profile("同名", "first"), "legacy-b": profile("同名", "second"), "legacy-c": profile("另一份")}, "active_radio_profile": "legacy-a", "radio_active": true}
	check(store.save_settings(settings).ok, "existing duplicate names load without deleting player configurations")
	check(not RadioProfiles.upsert(settings, profile(" 同名 ")).ok and not RadioProfiles.upsert(settings, profile("另一份")).ok, "new profiles reject duplicate names across different device GUIDs and trimmed spaces")
	check(not RadioProfiles.upsert({"radio_profiles": {"x": profile("RADIO")}}, profile("radio")).ok, "duplicate name detection ignores letter case")
	var result := RadioProfiles.upsert(settings, profile("改名后"), "legacy-a")
	check(result.ok and result.key == "legacy-a" and result.settings.radio_profiles.size() == 3 and result.settings.radio_profiles["legacy-b"].name == "同名", "editing and renaming preserves one stable profile key and all siblings")
	check(not RadioProfiles.upsert(settings, profile("另一份"), "legacy-a").ok and RadioProfiles.upsert(settings, profile("同名"), "legacy-a").ok, "legacy duplicate remains editable but renaming cannot collide with another name")
	check(not RadioProfiles.upsert(settings, profile(" ")).ok and not RadioProfiles.upsert(settings, profile("x".repeat(49))).ok, "empty and oversized names rejected before persistence")
	var removed := RadioProfiles.remove(settings, "legacy-a")
	check(removed.ok and removed.active and removed.settings.radio_selection_required and not removed.settings.radio_active and settings.radio_profiles.size() == 3, "active deletion prepares a paused input selection state without mutating the source")
	var keyboard_settings := settings.duplicate(true)
	keyboard_settings.radio_active = false
	var keyboard_removed := RadioProfiles.remove(keyboard_settings, "legacy-a")
	check(not keyboard_removed.active and not keyboard_removed.settings.get("radio_selection_required", false), "deleting a remembered profile does not interrupt explicitly selected keyboard input")
	check(store.save_settings(removed.settings).ok, "delete commits through normal settings transaction")
	for key: String in ["legacy-b", "legacy-c"]:
		removed = RadioProfiles.remove(store.data.settings, key)
		store.save_settings(removed.settings)
	var restart := ProgressStore.new(catalog, store.path)
	check(restart.data.settings.radio_profiles.is_empty() and restart.data.settings.radio_profiles_managed, "deleting every profile survives restart without backup recovery resurrecting deleted entries")
	check(not RadioProfiles.remove(restart.data.settings, "missing").ok, "unknown deletion does not erase other preferences")
	game = TestGame.new()
	root.add_child(game)
	await game._wait_for_world()
	game.store.save_settings(settings)
	game._show_radio()
	var menu: RadioMenu = game.menu
	check(menu.keys.size() == 3 and menu.profile_select.item_count == 3 and menu.device_select.item_count >= 1 and menu.find_children("*", "OptionButton", true, false).size() == 2, "production F2 uses exactly two independent dropdowns for configurations and input devices")
	var labels := PackedStringArray()
	for index in menu.profile_select.item_count:
		labels.append(menu.profile_select.get_item_text(index))
	check(labels[menu.keys.find("legacy-a")] != labels[menu.keys.find("legacy-b")], "legacy duplicate names have distinct visible identifiers")
	menu.profile_select.select(menu.keys.find("legacy-b"))
	menu._selection_changed()
	menu._request_delete()
	check(menu.pending_delete == "legacy-b" and menu.confirmation.visible and game.store.data.settings.radio_profiles.size() == 3, "deletion asks for explicit UI confirmation without changing the store")
	await screenshot("radio-dropdowns")
	game.store.writable = false
	check(not game._delete_radio_profile("legacy-b").ok and game.store.data.settings.radio_profiles.size() == 3, "failed deletion leaves all profiles and active input intact")
	game.store.writable = true
	check(game._delete_radio_profile("legacy-b").ok and game.store.data.settings.radio_profiles.has("legacy-a"), "deleting selected inactive duplicate retains active configuration")
	game.virtual_input.using_radio = true
	game.virtual_input.profile = profile()
	check(game._delete_radio_profile("legacy-a").ok and game.paused and game.radio_required and not game.flight_input.using_radio, "deleting active profile pauses physics and requires explicit input selection")
	game._restore_radio()
	check(game.radio_required, "startup restoration respects deletion's required input selection")
	game._edit_radio(profile("另一份"), "legacy-c", -1)
	var editor: RadioCalibration = game.menu
	if editor.device < 0:
		editor.profile_name.text = "离线改名"
		editor._accept()
		check(game.store.data.settings.radio_profiles["legacy-c"].name == "离线改名" and game.store.data.settings.radio_profiles.size() == 1, "offline editor renames in place without needing an attached controller")
	game._close_menu()
	game._show_input_display_menu()
	var display_menu: InputDisplayMenu = game.menu
	display_menu.sticks.button_pressed = true
	display_menu.switches.button_pressed = true
	game.store.writable = false
	display_menu.submit()
	check(game.menu == display_menu and not game.store.data.settings.has("input_display"), "preview preferences stay uncommitted when a save fails")
	game.store.writable = true
	display_menu.submit()
	check(game.menu is PauseMenu and game.store.data.settings.input_display.sticks and game.store.data.settings.input_display.switches, "both optional input display modes save from production menu")
	var restored := ProgressStore.new(catalog, game.store.path)
	check(InputDisplay.from_settings(restored.data.settings).sticks, "input display preference persists across restart")
	game._close_menu()
	game.radio_required = false
	game.virtual_input.using_radio = true
	game.virtual_input.profile = profile()
	game.virtual_input.selected_device = 99
	game.virtual_input.set_actions_enabled(false)
	game.virtual_input.enabled = false
	game.input_display.preferences = InputDisplay.from_settings(game.store.data.settings)
	game.input_display.sample()
	var tracking_before := game.virtual_input.auxiliary_positions.duplicate(true)
	var before := game.drone.global_transform
	game.input_display.sample()
	check(game.input_display.sticks.channels.x > 0.6 and game.input_display.sticks.channels.y < -0.4 and game.input_display.sticks.channels.w > 0.1, "paused overlay reads calibrated live sticks rather than frozen control output")
	check(game.input_display.aux_labels.switch.text.contains("3档") and game.input_display.aux_labels.button.text.contains("按下"), "overlay displays actual axis detent and momentary button state")
	check(game.virtual_input.auxiliary_positions == tracking_before and game.drone.global_transform == before, "read-only overlay cannot trigger a bound reset or advance input edge history")
	game.virtual_input.axes[4] = 0.52
	game.virtual_input.auxiliary_positions["switch"] = 1
	game.input_display.sample()
	check(game.input_display.aux_labels.switch.text.contains("2档") and game.virtual_input.auxiliary_positions["switch"] == 1, "displayed switch state uses the same hysteresis as bound actions without mutating it")
	game.virtual_input.axes[4] = 1
	game.input_display.sample()
	var positions := InputDisplay.stick_positions(Vector4(0.3, -0.5, -0.4, 0.2), 2)
	check(positions[0].is_equal_approx(Vector2(-0.4, 0.6)) and positions[1].is_equal_approx(Vector2(0.3, 0.5)), "Mode2 places throttle/yaw on left and pitch/roll on right with correct signs")
	positions = InputDisplay.stick_positions(Vector4(0.3, -0.5, -0.4, 0.2), 1)
	check(is_equal_approx(positions[1].y, 0.6) and is_equal_approx(positions[0].y, 0.5), "Mode1 swaps vertical stick roles")
	game.input_display.radio_required = true
	game.input_display.sample()
	check(game.input_display.sticks.channels == Vector4.ZERO and game.input_display.status.text.contains("断开"), "disconnected display does not show stale live input")
	game.input_display.radio_required = false
	game.radio_required = false
	game.input_display.show()
	game.input_display.sample()
	await screenshot("live-input-overlay")
	game._show_pause_menu()
	await process_frame
	check(not game.input_display.visible, "input display hides behind menus")
	var legacy := FlightTuning.defaults()
	legacy.erase("pid")
	legacy.erase("d_filter_hz")
	check(FlightTuning.valid(legacy) and FlightTuning.from_settings({"flight": legacy}).pid == FlightTuning.defaults().pid, "old rate and environment profiles acquire default PID without losing their settings")
	for key: String in ["p", "i", "d"]:
		for value: Variant in [-1.0, NAN, INF, "bad", 1000]:
			var invalid := FlightTuning.defaults()
			invalid.pid.roll[key] = value
			check(not FlightTuning.valid(invalid), "invalid PID rejected: %s %s" % [key, str(value)])
	var workshop := Workshop.new()
	workshop.catalog = game.catalog
	workshop.store = game.store
	workshop.build = game.store.data.build.duplicate(true)
	workshop.flight_profile = FlightTuning.defaults()
	game._mount_menu(workshop)
	workshop.tabs.current_tab = 1
	workshop.pid_controls.roll.p.value = 22
	workshop.pid_controls.pitch.i.value = 4.5
	workshop.pid_controls.yaw.d.value = 1.1
	workshop.pid_filter.value = 25
	workshop.submit()
	check(workshop.flight_profile.pid.roll.p == 22 and workshop.flight_profile.pid.pitch.i == 4.5 and workshop.flight_profile.pid.yaw.d == 1.1 and workshop.flight_profile.d_filter_hz == 25, "PID editor collects independent per-axis P/I/D and derivative filter")
	var saved_settings: Dictionary = game.store.data.settings.duplicate(true)
	saved_settings.flight = workshop.flight_profile.duplicate(true)
	check(game.store.save_loadout(game.store.data.build, saved_settings).ok and game.drone.apply_tuning(workshop.flight_profile), "custom PID uses normal equipment transaction and applies to actual controller")
	check(ProgressStore.new(catalog, game.store.path).data.settings.flight.pid == workshop.flight_profile.pid, "custom PID survives restart")
	var scroll: ScrollContainer = workshop.tabs.get_child(1)
	await process_frame
	await process_frame
	scroll.scroll_vertical = 10000
	await screenshot("pid-controls")
	var invalid_settings := saved_settings.duplicate(true)
	invalid_settings.flight.pid.yaw.d = NAN
	check(not game.store.save_settings(invalid_settings).ok and not game.store.save_loadout(game.store.data.build, invalid_settings).ok, "invalid PID cannot enter either settings persistence path")
	game.drone.rate_integral = Vector3.ONE
	game.drone.rate_derivative = Vector3.ONE
	game.drone.reset_attitude()
	check(game.drone.rate_integral == Vector3.ZERO and game.drone.rate_derivative == Vector3.ZERO and not game.drone.rate_history_valid, "reset clears I and derivative history to avoid a restart kick")
	game.queue_free()
	await process_frame
	print("CONTROLS_RESULT failures=%d checks=%d" % [failed, checked])
	quit(1 if failed else 0)
