extends SceneTree

class VirtualRadio:
	extends RadioCalibration
	var connected := true
	var axes: Array[float] = [0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var buttons: Array[bool] = [false, false, false, false]
	func _connected() -> bool:
		return connected
	func _read_axes() -> Array[float]:
		return axes.duplicate()
	func _read_buttons() -> Array[bool]:
		return buttons.duplicate()
	func _device_guid() -> String:
		return "virtual-radio"
	func _device_name() -> String:
		return "测试遥控器"
	func _refresh_devices() -> void:
		devices = [99]
		device_select.clear()
		device_select.add_item("测试遥控器 · 模拟 USB 输入")
		_select_device(0)

var failed := 0
var saved: Dictionary = {}

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture := RadioCapture.new()
	capture.begin([0.0, -1.0, 0.1, 0.0, 0.0, 0.0])
	capture.sample([-0.9, -1.0, -0.8, -0.7, 0.02, 0.0])
	capture.sample([0.8, 1.0, 0.9, 0.8, -0.02, 0.0])
	var mapping := capture.stick_mapping([0.0, -1.0, 0.1, 0.0, 0.0, 0.0])
	check(FlightInput.valid_profile({"axes": mapping}) and mapping.throttle.axis == 1, "one sweep discovers four axes and non-centering throttle regardless of channel order")
	check(mapping.roll.min == -0.9 and mapping.pitch.center == 0.1 and mapping.yaw.max == 0.8, "simultaneous full travel and asymmetric centers are retained")
	check(capture.stick_mapping([0.0, 0.0, 0.1, 0.0, 0.0, 0.0]).is_empty(), "throttle must be at an endpoint when completing capture")
	capture.sample([0.0, -1.0, 0.1, 0.0, 1.0, 0.0])
	check(capture.stick_mapping([0.0, -1.0, 0.1, 0.0, 0.0, 0.0]).is_empty(), "moving a fifth axis requires retry instead of silently choosing a wrong stick")
	capture.begin([0.0, 1.0, 0.0, 0.0])
	capture.sample([-1.0, -1.0, -1.0, -1.0])
	capture.sample([1.0, 1.0, 1.0, 1.0])
	var reversed := capture.stick_mapping([0.0, 1.0, 0.0, 0.0])
	check(reversed.throttle.invert and FlightInput.normalize_axis(1.0, reversed.throttle, true) == 0.0, "reversed non-centering throttle starts at zero after collective calibration")
	var previous := {"roll": mapping.yaw, "pitch": mapping.pitch, "yaw": mapping.roll}
	mapping = capture.stick_mapping([0.0, 1.0, 0.0, 0.0], previous)
	check(mapping.roll.axis == 3 and mapping.pitch.axis == 2 and mapping.yaw.axis == 0, "recalibration retains existing attitude assignments")
	var switch := {"id": "test", "name": "开关", "source": "axis", "axis": 4, "min": -0.8, "max": 0.8, "type": "three_position", "invert": false}
	check(FlightInput.auxiliary_value(switch, -0.8) == 0 and FlightInput.auxiliary_value(switch, 0.02) == 1 and FlightInput.auxiliary_value(switch, 0.8) == 2, "axis switch resolves all three detents")
	switch.invert = true
	check(FlightInput.auxiliary_value(switch, -0.8) == 2 and FlightInput.auxiliary_value(switch, 0.0) == 1, "three-position inversion exchanges ends while retaining middle")
	switch.type = "analog"
	check(is_equal_approx(FlightInput.auxiliary_value(switch, 0), 0.5), "knobs preserve continuous travel")
	var button := {"id": "button", "name": "回弹", "source": "buttons", "buttons": [0], "type": "momentary", "invert": false}
	check(FlightInput.auxiliary_value(button, 0, [false]) == 0 and FlightInput.auxiliary_value(button, 0, [true]) == 1 and FlightInput.auxiliary_value(button, 0, [false]) == 0, "momentary buttons follow press and release without latching")
	var pair := {"id": "pair", "name": "三档", "source": "buttons", "buttons": [1, 2], "type": "three_position", "invert": false}
	check(FlightInput.auxiliary_value(pair, 0, [false, true, false]) == 0 and FlightInput.auxiliary_value(pair, 0, [false, false, false]) == 1 and FlightInput.auxiliary_value(pair, 0, [false, false, true]) == 2, "two USB buttons can represent a three-position switch with neutral middle")
	var triple := pair.duplicate(true)
	triple.buttons = [0, 1, 2]
	check(FlightInput.auxiliary_value(triple, 0, [true, false, false]) == 0 and FlightInput.auxiliary_value(triple, 0, [false, true, false]) == 1 and FlightInput.auxiliary_value(triple, 0, [false, false, true]) == 2, "one-hot USB buttons can represent all three switch positions")
	var profile := {"name": "Test", "guid": "test", "axes": reversed, "auxiliary": [switch, button, pair]}
	check(FlightInput.valid_profile(profile) and FlightInput.valid_profile(JSON.parse_string(JSON.stringify(profile))), "mixed auxiliary sources survive JSON roundtrip and integer-to-float conversion")
	var invalid := profile.duplicate(true)
	invalid.auxiliary[0].axis = 0
	check(not FlightInput.valid_profile(invalid), "auxiliary cannot reuse a stick axis")
	invalid = profile.duplicate(true)
	invalid.auxiliary[2].buttons = [0, 2]
	check(not FlightInput.valid_profile(invalid), "auxiliary controls cannot share USB buttons")
	invalid = profile.duplicate(true)
	invalid.auxiliary[0].min = NAN
	check(not FlightInput.valid_profile(invalid), "invalid auxiliary ranges rejected")
	invalid = profile.duplicate(true)
	invalid.auxiliary[1].type = "three_position"
	check(not FlightInput.valid_profile(invalid), "single USB button cannot claim three independent positions")
	invalid = profile.duplicate(true)
	invalid.axes.roll.axis = NAN
	check(not FlightInput.valid_profile(invalid), "non-finite stick index rejected before integer conversion")
	invalid = profile.duplicate(true)
	invalid.auxiliary[0].min = "invalid"
	check(not FlightInput.valid_profile(invalid), "malformed saved range rejected without numeric coercion")
	var ui := VirtualRadio.new()
	var host := CenterContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	host.add_child(ui)
	ui.device = 99
	ui._begin()
	ui.axes = [-0.8, -0.9, -0.7, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	ui._process(0)
	ui.axes = [0.8, 0.9, 0.7, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	ui._process(0)
	ui.axes = [0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	ui._record()
	check(ui.mapping.size() == 4 and ui.mode.is_empty() and ui.record_button.disabled, "production UI completes all four axes with one finish action")
	ui._assign_axis("roll", 2)
	check(ui.mapping.roll.axis == 2 and ui.mapping.yaw.axis == 0, "assignment selector swaps channels without creating duplicate sources")
	var roll_invert: CheckButton = ui.axis_rows.get_child(0).get_child(2)
	roll_invert.button_pressed = true
	check(ui.mapping.roll.invert, "per-channel direction switch edits captured mapping")
	ui._aux_capture()
	ui.axes[4] = -0.8
	ui._process(0)
	ui.axes[4] = 0.8
	ui._process(0)
	ui._aux_capture()
	check(ui.auxiliary.size() == 1 and ui.auxiliary[0].axis == 4, "production UI discovers a spare axis as auxiliary")
	check(ui.auxiliary[0].name == "通道 4" and ui.binding_rows.get_child(0).text.begins_with("通道 4"), "axis four is shown as channel four in identification and binding headings")
	check(ui.live.text.contains("4:"), "channel number matches the raw preview axis index without an offset")
	var select: OptionButton = ui.aux_rows.get_child(0).get_child(2)
	select.select(1)
	select.item_selected.emit(1)
	check(ui.auxiliary[0].type == "three_position", "settings selector changes identified channel to three-position switch")
	ui._aux_capture()
	ui.buttons[0] = true
	ui._process(0)
	ui.buttons[0] = false
	ui._process(0)
	ui._aux_capture()
	check(ui.auxiliary.size() == 2 and ui.auxiliary[1].source == "buttons", "production UI discovers press and release even when final state equals initial state")
	check(ui.binding_rows.get_child(2).text.begins_with("按钮 0"), "button controls use their USB button index rather than a made-up axis channel")
	ui._aux_capture()
	ui.buttons[0] = true
	ui._process(0)
	ui._aux_capture()
	check(ui.auxiliary.size() == 2, "reidentifying the same input does not duplicate it")
	var action_names: Array = FlightInput.ACTION_NAMES.keys()
	var binding_select: OptionButton = ui.binding_rows.get_child(1).get_child(0).get_child(1)
	binding_select.select(action_names.find("pause"))
	binding_select.item_selected.emit(action_names.find("pause"))
	var attitude_select: OptionButton = ui.binding_rows.get_child(1).get_child(1).get_child(1)
	attitude_select.select(action_names.find("reset_attitude"))
	attitude_select.item_selected.emit(action_names.find("reset_attitude"))
	var resume_select: OptionButton = ui.binding_rows.get_child(1).get_child(2).get_child(1)
	resume_select.select(action_names.find("resume"))
	resume_select.item_selected.emit(action_names.find("resume"))
	var reset_select: OptionButton = ui.binding_rows.get_child(3).get_child(1).get_child(1)
	reset_select.select(action_names.find("reset"))
	reset_select.item_selected.emit(action_names.find("reset"))
	check(ui.auxiliary[0].bindings["0"] == "pause" and ui.auxiliary[0].bindings["1"] == "reset_attitude" and ui.auxiliary[0].bindings["2"] == "resume" and ui.auxiliary[1].bindings["1"] == "reset", "action selectors distinguish in-place attitude reset from returning to deployment")
	ui.accepted.connect(func(value: Dictionary, _device: int): saved = value)
	ui._accept()
	check(saved.get("auxiliary", []).size() == 2 and FlightInput.valid_profile(saved), "saving UI emits complete calibrated profile and auxiliary definitions")
	var catalog := ContentCatalog.new()
	var path := "user://tests/radio_" + str(Time.get_ticks_usec()) + "/progress.json"
	var store := ProgressStore.new(catalog, path)
	var settings: Dictionary = store.data.settings.duplicate(true)
	settings.radio_profiles = {"test": saved}
	var committed := store.save_settings(settings)
	var restored: Dictionary = ProgressStore.new(catalog, path).data.settings.radio_profiles.test
	check(committed.ok and FlightInput.valid_profile(restored) and restored.auxiliary[0].type == "three_position" and restored.axes.roll.invert and int(restored.axes.roll.axis) == 2 and is_equal_approx(restored.axes.roll.min, saved.axes.roll.min), "settings persistence restores switch types, assignments and inversions")
	check(restored.auxiliary[0].bindings["0"] == "pause" and restored.auxiliary[0].bindings["1"] == "reset_attitude" and restored.auxiliary[1].bindings["1"] == "reset", "real settings persistence restores both distinct reset action bindings")
	var reopened := VirtualRadio.new()
	reopened.initial_profile = restored
	host.remove_child(ui)
	host.add_child(reopened)
	check(reopened.mapping.roll.invert and reopened.auxiliary[0].type == "three_position", "reopening settings loads saved directions and channel types without recapturing")
	var old_label: Dictionary = restored.auxiliary[0].duplicate(true)
	old_label.name = "通道 1"
	RadioCalibration._normalize_channel_name(old_label)
	check(old_label.name == "通道 4", "old discovery-order channel names normalize to the actual axis index")
	old_label.name = "我的开关"
	RadioCalibration._normalize_channel_name(old_label)
	check(old_label.name == "我的开关", "custom channel aliases remain intact")
	if DisplayServer.get_name() != "headless":
		await capture_image("radio-sticks")
		reopened.tabs.current_tab = 1
		await capture_image("radio-switches")
		reopened.tabs.current_tab = 2
		await capture_image("radio-bindings")
	var reopened_select: OptionButton = reopened.binding_rows.get_child(1).get_child(2).get_child(1)
	check(reopened_select.selected == action_names.find("resume"), "reopened action selector shows saved resume binding")
	var reopened_type: OptionButton = reopened.aux_rows.get_child(0).get_child(2)
	reopened_type.item_selected.emit(0)
	check(not reopened.auxiliary[0].has("bindings") and reopened.auxiliary[1].bindings["1"] == "reset", "changing a channel type clears only that channel's now-ambiguous bindings")
	reopened.queue_free()
	host.add_child(ui)
	ui._aux_capture()
	ui.connected = false
	ui._process(0)
	check(ui.mode.is_empty() and ui.save_button.disabled, "disconnect cancels capture and disables saving")
	var reader := FlightInput.new()
	reader.profile = saved
	reader.enabled = false
	reader.using_radio = true
	check(reader.read_auxiliary(saved.auxiliary[0].id) == 0, "paused input exposes no active auxiliary output")
	reader.free()
	ui.queue_free()
	host.queue_free()
	await process_frame
	print("RADIO_RESULT failures=", failed)
	quit(1 if failed else 0)

func capture_image(filename: String) -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			await process_frame
			await RenderingServer.frame_post_draw
			var directory := argument.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(directory)
			root.get_texture().get_image().save_png(directory.path_join(filename + ".png"))
