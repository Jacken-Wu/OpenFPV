class_name FlightInput
extends Node
## Independent RC axes. Never normalize roll and pitch as a circular gamepad stick.

signal connection_lost

const CHANNELS: Array[String] = ["roll", "pitch", "yaw", "throttle"]
var channels := Vector4.ZERO
var keyboard_throttle := 0.0
var profile: Dictionary = {}
var selected_device := -1
var using_radio := false
var enabled := true

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
	if not enabled:
		return
	if using_radio:
		if not Input.get_connected_joypads().has(selected_device):
			using_radio = false
			channels = Vector4.ZERO
			connection_lost.emit()
			return
		channels = Vector4(read_channel("roll"), read_channel("pitch"), read_channel("yaw"), read_channel("throttle"))
	else:
		keyboard_throttle = clampf(keyboard_throttle + Input.get_axis("throttle_down", "throttle_up") * delta * 0.4, 0.0, 1.0)
		channels = Vector4(Input.get_axis("roll_left", "roll_right"), Input.get_axis("pitch_back", "pitch_forward"), Input.get_axis("yaw_left", "yaw_right"), keyboard_throttle)

func read_channel(channel: String) -> float:
	if not profile.get("axes", {}).has(channel):
		return 0.0
	var axis: Dictionary = profile.axes[channel]
	var raw := Input.get_joy_axis(selected_device, int(axis.axis))
	return normalize_axis(raw, axis, channel == "throttle")

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
		return clampf(value, 0.0, 1.0)
	var center := float(axis.center)
	value = (raw - center) / maxf(0.1, high - center if raw >= center else center - low)
	if bool(axis.invert):
		value = -value
	var deadzone := float(axis.get("deadzone", 0.025))
	return signf(value) * clampf((absf(value) - deadzone) / (1.0 - deadzone), 0.0, 1.0)

func activate_profile(value: Dictionary, device: int) -> void:
	profile = value.duplicate(true)
	selected_device = device
	using_radio = device >= 0 and Input.get_connected_joypads().has(device)
	channels = Vector4.ZERO

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
		var index := int(axis.axis)
		if used.has(index) or index < 0 or index >= 10 or not is_finite(float(axis.min)) or not is_finite(float(axis.max)) or not is_finite(float(axis.center)) or float(axis.max) - float(axis.min) < 0.2:
			return false
		if channel != "throttle" and (float(axis.center) <= float(axis.min) or float(axis.center) >= float(axis.max)):
			return false
		var deadzone := float(axis.get("deadzone", 0.025))
		if not is_finite(deadzone) or deadzone < 0 or deadzone > 0.2 or not axis.invert is bool:
			return false
		used.append(index)
	return true

func reset_throttle() -> void:
	keyboard_throttle = 0.0
	channels = Vector4.ZERO

func throttle_now() -> float:
	if using_radio:
		return read_channel("throttle") if Input.get_connected_joypads().has(selected_device) else 1.0
	return keyboard_throttle

func _on_connection_changed(device: int, connected: bool) -> void:
	if not connected and using_radio and device == selected_device:
		using_radio = false
		channels = Vector4.ZERO
		connection_lost.emit()
