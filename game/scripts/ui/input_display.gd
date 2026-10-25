class_name InputDisplay
extends PanelContainer
## Read-only telemetry never advances auxiliary edges or emits flight actions.
class Sticks extends Control:
	var channels := Vector4.ZERO
	var mode := 2
	func _init() -> void:
		custom_minimum_size = Vector2(152, 76)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var pairs := InputDisplay.stick_positions(channels, mode)
		var font := ThemeDB.fallback_font
		for index in 2:
			var center := Vector2(38 + index * 76, 28)
			var bounds := Rect2(center - Vector2.ONE * 26, Vector2.ONE * 52)
			draw_style_box(_background(), bounds)
			# Two antialiased pixels survive fractional viewport/window scaling.
			draw_line(center - Vector2(25, 0), center + Vector2(25, 0), Color("93bbc9"), 2, true)
			draw_line(center - Vector2(0, 25), center + Vector2(0, 25), Color("93bbc9"), 2, true)
			draw_circle(center + pairs[index] * 22, 3.5, Color("71e0d0"), true, -1, true)
			var caption := ("偏航 / 油门" if index == 0 else "横滚 / 俯仰") if mode == 2 else ("偏航 / 俯仰" if index == 0 else "横滚 / 油门")
			draw_string(font, Vector2(index * 76 + 2, 72), caption, HORIZONTAL_ALIGNMENT_CENTER, 72, 12, Color("d5e8ec"))
	func _background() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("0b1723aa")
		style.border_color = Color("7a9baaaa")
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		return style

var input: FlightInput
var radio_required := false
var preferences := defaults()
var sticks: Sticks
var status: Label
var aux_list: GridContainer
var aux_labels: Dictionary = {}
var last_profile := ""

static func defaults() -> Dictionary:
	return {"sticks": false, "switches": false, "mode": 2}

static func valid(value: Variant) -> bool:
	return value is Dictionary and value.get("sticks") is bool and value.get("switches") is bool and FlightInput.valid_index(value.get("mode"), 3) and float(value.mode) >= 1

static func from_settings(settings: Dictionary) -> Dictionary:
	return settings.input_display.duplicate(true) if valid(settings.get("input_display")) else defaults()

static func stick_positions(channels: Vector4, mode: int) -> Array[Vector2]:
	var throttle := 1.0 - channels.w * 2.0
	var left := Vector2(channels.z, throttle if mode == 2 else -channels.y)
	var right := Vector2(channels.x, -channels.y if mode == 2 else throttle)
	var positions: Array[Vector2] = [left, right]
	return positions

func _ready() -> void:
	theme = UIStyle.theme()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("65839270")
	style.border_width_left = 1
	style.content_margin_left = 10
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var column := UIStyle.column(self, 2)
	status = UIStyle.label("操作预览", 12, Color("a8c8d3"))
	status.clip_text = true
	column.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	sticks = Sticks.new()
	row.add_child(sticks)
	aux_list = GridContainer.new()
	aux_list.add_theme_constant_override("h_separation", 8)
	aux_list.add_theme_constant_override("v_separation", 2)
	row.add_child(aux_list)

func sample() -> void:
	if not is_instance_valid(input) or sticks == null:
		return
	var connected := input.using_radio and input.radio_connected()
	var channels := input.current_channels() if not radio_required else Vector4.ZERO
	sticks.channels = channels
	sticks.mode = preferences.mode
	sticks.visible = preferences.sticks
	sticks.queue_redraw()
	aux_list.visible = preferences.switches
	status.text = "操作预览 · " + ("未选择输入 / 遥控器断开" if radio_required or (input.using_radio and not connected) else String(input.profile.get("name", "USB 遥控器")) if connected else "键盘调试")
	# Rebuild only when definitions change, not on every frame or channel value.
	var signature := JSON.stringify(input.profile.get("auxiliary", []))
	if last_profile != signature or (aux_labels.is_empty() and aux_list.get_child_count() == 0):
		last_profile = signature
		for child in aux_list.get_children():
			aux_list.remove_child(child)
			child.queue_free()
		aux_labels.clear()
		for control: Dictionary in input.profile.get("auxiliary", []):
			var label := UIStyle.label("", 13)
			label.clip_text = true
			label.custom_minimum_size.x = 110
			aux_list.add_child(label)
			aux_labels[control.id] = label
		if aux_labels.is_empty():
			aux_list.add_child(UIStyle.label("暂无辅助通道", 13, Color("91aab9")))
	# Prefer four rows; add columns within the right half of the status bar.
	var budget := minf(640, get_viewport_rect().size.x * 0.48 - 48)
	var available := budget - 10 - (160 if preferences.sticks else 0)
	var max_columns := maxi(2, int((available + 8) / 118))
	aux_list.columns = mini(max_columns, maxi(2, ceili(aux_labels.size() / 4.0))) if aux_labels.size() > 1 else 1
	if connected:
		var axes := input.radio_axes()
		var buttons := input.radio_buttons()
		for control: Dictionary in input.profile.get("auxiliary", []):
			var value := FlightInput.auxiliary_value(control, axes[int(control.get("axis", 0))], buttons)
			var detent := FlightInput.auxiliary_position(control, axes[int(control.get("axis", 0))], buttons, int(input.auxiliary_positions.get(control.id, -1)))
			var caption := "%.0f%%" % (value * 100) if control.type == "analog" else ("按下" if detent > 0 else "松开") if control.type == "momentary" else "%d档" % (detent + 1)
			var title := String(control.name)
			aux_labels[control.id].text = "%s · %s" % [title.left(4) + ("…" if title.length() > 4 else ""), caption]
			aux_labels[control.id].tooltip_text = title
	else:
		for id: String in aux_labels:
			aux_labels[id].text = "— 未连接"
