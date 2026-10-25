class_name FlightInput
extends Node
## Independent RC axes. Never normalize roll and pitch as a circular gamepad stick.

signal connection_lost
signal action_requested(action: String)

const CHANNELS: Array[String] = ["roll", "pitch", "yaw", "throttle"]
const AUX_TYPES: Array[String] = ["two_position", "three_position", "momentary", "analog"]
const ACTION_NAMES := {"": "不绑定", "toggle_pause": "暂停 / 恢复", "pause": "暂停", "resume": "恢复飞行", "reset": "回到部署点", "reset_attitude": "原地重置姿态", "toggle_camera": "切换视角", "photo": "拍照", "map": "地图 开 / 关", "missions": "任务地图 开 / 关", "help": "打开帮助", "interact": "交互 / 平台保存退出（任务可按住）"}
var channels := Vector4.ZERO
var keyboard_throttle := 0.0
var profile: Dictionary = {}
var selected_device := -1
var using_radio := false
var enabled := true
var actions_enabled := true
var auxiliary_positions: Dictionary = {}
var held_controls: Dictionary = {}

func _ready() -> void:
	Input.joy_connection_changed.connect(_on_connection_changed)
	var bindings := {
		"pitch_forward": KEY_W, "pitch_back": KEY_S,
		"roll_left": KEY_A, "roll_right": KEY_D,
		"yaw_left": KEY_J, "yaw_right": KEY_L,
		"throttle_up": KEY_UP, "throttle_down": KEY_DOWN,
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)

func _process(delta: float) -> void:
	if using_radio:
		if not radio_connected():
			_on_connection_changed(selected_device, false)
			return
		# Commands stay live while physics/flight axes are paused.
		update_auxiliary(radio_axes(), radio_buttons())
	if not enabled:
		return
	if not using_radio:
		keyboard_throttle = clampf(keyboard_throttle + Input.get_axis("throttle_down", "throttle_up") * delta * 0.4, 0.0, 1.0)
	channels = current_channels()

func radio_connected() -> bool:
	return Input.get_connected_joypads().has(selected_device)

func radio_axis(index: int) -> float:
	return Input.get_joy_axis(selected_device, index)

func radio_axes() -> Array[float]:
	var values: Array[float] = []
	for index in JOY_AXIS_MAX:
		values.append(radio_axis(index))
	return values

func radio_buttons() -> Array[bool]:
	return button_values(selected_device)

func current_channels() -> Vector4:
	if using_radio:
		return Vector4(read_channel("roll"), read_channel("pitch"), read_channel("yaw"), read_channel("throttle")) if radio_connected() else Vector4.ZERO
	return Vector4(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_back", "pitch_forward"), Input.get_axis("yaw_left", "yaw_right"), keyboard_throttle)

func set_actions_enabled(value: bool) -> void:
	if actions_enabled != value:
		reset_auxiliary_tracking()
	actions_enabled = value

func reset_auxiliary_tracking() -> void:
	auxiliary_positions.clear()
	held_controls.clear()

func action_held(action: String) -> bool:
	return actions_enabled and using_radio and held_controls.values().has(action)

func update_auxiliary(axes: Array[float], buttons: Array[bool]) -> void:
	if not actions_enabled:
		reset_auxiliary_tracking()
		return
	var pending: Array[String] = []
	for control: Dictionary in profile.get("auxiliary", []):
		var previous := int(auxiliary_positions.get(control.id, -1))
		var raw := axes[int(control.get("axis", 0))]
		var position := auxiliary_position(control, raw, buttons, previous)
		auxiliary_positions[control.id] = position
		if previous < 0 or previous == position:
			continue
		held_controls.erase(control.id)
		var action: String = control.get("bindings", {}).get(str(position), "")
		if action == "interact":
			held_controls[control.id] = action
		if not action.is_empty() and not pending.has(action):
			pending.append(action)
	for action in pending:
		# A handler may open a menu and disable the remaining commands this frame.
		if not actions_enabled:
			break
		action_requested.emit(action)

func read_channel(channel: String) -> float:
	if not profile.get("axes", {}).has(channel):
		return 0.0
	var axis: Dictionary = profile.axes[channel]
	var raw := radio_axis(int(axis.axis))
	return normalize_axis(raw, axis, channel == "throttle")

func read_auxiliary(id: String) -> float:
	if not enabled or not using_radio or not Input.get_connected_joypads().has(selected_device):
		return 0.0
	for control: Dictionary in profile.get("auxiliary", []):
		if control.id == id:
			return auxiliary_value(control, Input.get_joy_axis(selected_device, int(control.get("axis", 0))), button_values(selected_device))
	return 0.0

static func axis_values(device: int) -> Array[float]:
	var values: Array[float] = []
	for index in JOY_AXIS_MAX:
		values.append(Input.get_joy_axis(device, index))
	return values

static func button_values(device: int) -> Array[bool]:
	var values: Array[bool] = []
	for index in JOY_BUTTON_MAX:
		values.append(Input.is_joy_button_pressed(device, index))
	return values

static func auxiliary_value(control: Dictionary, raw: float, buttons: Array[bool] = []) -> float:
	var value := auxiliary_unit_value(control, raw, buttons)
	match control.type:
		"three_position": return 0.0 if value < 0.25 else (2.0 if value > 0.75 else 1.0)
		"analog": return value
		_: return 1.0 if value >= 0.5 else 0.0

static func auxiliary_position(control: Dictionary, raw: float, buttons: Array[bool], previous: int = -1) -> int:
	var value := auxiliary_unit_value(control, raw, buttons)
	if binding_count(control) == 3:
		var lower := 0.30 if previous == 0 else 0.20 if previous > 0 else 0.25
		var upper := 0.70 if previous == 2 else 0.80 if previous >= 0 else 0.75
		return 0 if value < lower else 2 if value > upper else 1
	var threshold := 0.60 if previous == 0 else 0.40 if previous == 1 else 0.50
	return 1 if value >= threshold else 0

static func binding_count(control: Dictionary) -> int:
	return 3 if control.type in ["three_position", "analog"] else 2

static func auxiliary_unit_value(control: Dictionary, raw: float, buttons: Array[bool] = []) -> float:
	var value := 0.0
	if control.source == "axis":
		value = clampf((raw - float(control.min)) / maxf(0.2, float(control.max) - float(control.min)), 0, 1)
	else:
		var indices: Array = control.buttons
		var first := int(indices[0]) < buttons.size() and buttons[int(indices[0])]
		if indices.size() == 3:
			value = 0.5
			for index in 3:
				if int(indices[index]) < buttons.size() and buttons[int(indices[index])]:
					value = index * 0.5
		elif indices.size() == 2:
			var second := int(indices[1]) < buttons.size() and buttons[int(indices[1])]
			value = 0.5 if first == second else (0.0 if first else 1.0)
		else:
			value = 1.0 if first else 0.0
	if control.invert:
		value = 1.0 - value
	if control.source == "axis":
		var deadzone := float(control.get("deadzone", 0.0))
		if control.type in ["analog", "three_position"]:
			value = 0.5 + apply_deadzone(value * 2.0 - 1.0, deadzone) * 0.5
		else:
			value = apply_deadzone(value, deadzone)
	return value

static func normalize_axis(raw: float, axis: Dictionary, throttle: bool) -> float:
	var low := float(axis.min)
	var high := float(axis.max)
	if high - low < 0.2:
		return 0.0
	var value: float
	if throttle:
		value = (raw - low) / (high - low)
		if bool(axis.invert):
			value = 1.0 - value
		# Non-centering throttle has its deadzone at idle, never at mid-stick.
		return apply_deadzone(clampf(value, 0.0, 1.0), float(axis.get("deadzone", 0.0)))
	var center := float(axis.center)
	value = (raw - center) / maxf(0.1, high - center if raw >= center else center - low)
	if bool(axis.invert):
		value = -value
	var deadzone := float(axis.get("deadzone", 0.025))
	return apply_deadzone(value, deadzone)

static func apply_deadzone(value: float, deadzone: float) -> float:
	return signf(value) * clampf((absf(value) - deadzone) / (1.0 - deadzone), 0.0, 1.0)

func activate_profile(value: Dictionary, device: int) -> void:
	profile = value.duplicate(true)
	selected_device = device
	using_radio = device >= 0 and radio_connected()
	channels = Vector4.ZERO
	reset_auxiliary_tracking()

static func valid_profile(value: Dictionary) -> bool:
	if not value.has("axes") or not value.axes is Dictionary:
		return false
	var used: Array[int] = []
	for channel: String in CHANNELS:
		if not value.axes.has(channel) or not value.axes[channel] is Dictionary:
			return false
		var axis: Dictionary = value.axes[channel]
		if not axis.has_all(["axis", "min", "max", "center", "invert"]):
			return false
		if not valid_index(axis.axis, JOY_AXIS_MAX) or not valid_range(axis) or not finite_number(axis.center):
			return false
		var index := int(axis.axis)
		if used.has(index):
			return false
		if channel != "throttle" and (float(axis.center) <= float(axis.min) or float(axis.center) >= float(axis.max)):
			return false
		var deadzone: Variant = axis.get("deadzone", 0.025)
		if not finite_number(deadzone) or deadzone < 0 or deadzone > 0.2 or not axis.invert is bool:
			return false
		used.append(index)
	if not value.get("auxiliary", []) is Array:
		return false
	var ids: Array[String] = []
	var used_buttons: Array[int] = []
	for item: Variant in value.get("auxiliary", []):
		if not item is Dictionary or not item.has_all(["id", "name", "type", "source", "invert"]):
			return false
		if not item.id is String or item.id.is_empty() or ids.has(item.id) or not item.name is String or item.name.strip_edges().is_empty() or not item.type in AUX_TYPES or not item.invert is bool:
			return false
		ids.append(item.id)
		if not item.get("bindings", {}) is Dictionary:
			return false
		for position: Variant in item.get("bindings", {}):
			if not position is String or not position in (["0", "1", "2"] if binding_count(item) == 3 else ["0", "1"]) or not item.bindings[position] is String or not ACTION_NAMES.has(item.bindings[position]):
				return false
		if item.source == "axis":
			var deadzone: Variant = item.get("deadzone", 0.0)
			if not finite_number(deadzone) or deadzone < 0 or deadzone > 0.2:
				return false
			if not item.has_all(["axis", "min", "max"]) or not valid_index(item.axis, JOY_AXIS_MAX):
				return false
			if used.has(int(item.axis)) or not valid_range(item):
				return false
			used.append(int(item.axis))
		elif item.source == "buttons":
			if not item.get("buttons") is Array or item.buttons.size() < 1 or item.buttons.size() > 3 or item.type == "analog" or (item.buttons.size() >= 2) != (item.type == "three_position"):
				return false
			for index: Variant in item.buttons:
				if not valid_index(index, JOY_BUTTON_MAX) or used_buttons.has(int(index)):
					return false
				used_buttons.append(int(index))
		else:
			return false
	return true

static func valid_index(value: Variant, limit: int) -> bool:
	return finite_number(value) and float(value) == floorf(float(value)) and value >= 0 and value < limit

static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func valid_range(axis: Dictionary) -> bool:
	return finite_number(axis.min) and finite_number(axis.max) and float(axis.min) >= -1 and float(axis.max) <= 1 and float(axis.max) - float(axis.min) >= 0.2

func reset_throttle() -> void:
	keyboard_throttle = 0.0
	channels = Vector4.ZERO

func _on_connection_changed(device: int, connected: bool) -> void:
	if not connected and using_radio and device == selected_device:
		using_radio = false
		channels = Vector4.ZERO
		reset_auxiliary_tracking()
		connection_lost.emit()
