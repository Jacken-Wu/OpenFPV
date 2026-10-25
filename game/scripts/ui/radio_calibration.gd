class_name RadioCalibration
extends PanelContainer

signal accepted(profile: Dictionary, device: int)
signal closed
const NAMES: Array[String] = ["横滚", "俯仰", "偏航", "油门"]
const TYPE_NAMES: Array[String] = ["二档开关", "三档开关", "可回弹二档", "旋钮 / 滑杆"]
var initial_profile: Dictionary = {}
var existing_profiles: Dictionary = {}
var editing_key := ""
var preferred_device := -1
var allow_offline_edit := false
var device_select: OptionButton
var status: Label
var live: Label
var record_button: Button
var save_button: Button
var aux_button: Button
var profile_name: LineEdit
var tabs: TabContainer
var axis_rows: VBoxContainer
var aux_rows: VBoxContainer
var binding_rows: VBoxContainer
var axis_monitors: Dictionary = {}
var aux_monitors: Dictionary = {}
var devices: Array[int] = []
var device := -1
var mode := ""
var capture := RadioCapture.new()
var mapping: Dictionary = {}
var auxiliary: Array = []

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(980, 800)
	var column := UIStyle.column(self, 8)
	column.add_child(UIStyle.label("遥控器设置", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("支持以 USB 控制器连接的遥控器。关闭遥控器混控，使用完整通道行程。", 17))
	var devices_row := HBoxContainer.new()
	column.add_child(devices_row)
	device_select = OptionButton.new()
	device_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	devices_row.add_child(device_select)
	device_select.item_selected.connect(_select_device)
	devices_row.add_child(UIStyle.button("刷新设备", _refresh_devices))
	profile_name = LineEdit.new()
	profile_name.placeholder_text = "配置名称，例如 我的遥控器"
	profile_name.text = "我的遥控器"
	column.add_child(profile_name)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var sticks := _tab("摇杆校准")
	sticks.add_child(UIStyle.label("1  开始采集后，同时或依次将两根摇杆绕满全部行程数次。不要操作开关。\n2  横滚、俯仰、偏航回中，油门放最低，再完成采集。\n3  核对下方轴分配：右滚 / 前倾 / 右转应为正；可随时切换正反。", 17))
	var row := HBoxContainer.new()
	sticks.add_child(row)
	row.add_child(UIStyle.button("一次校准四轴", _begin))
	record_button = UIStyle.button("完成采集 · 三轴回中、油门最低", _record)
	record_button.disabled = true
	row.add_child(record_button)
	axis_rows = UIStyle.column(sticks, 6)
	var switches := _tab("拨杆与开关")
	switches.add_child(UIStyle.label("点击识别后，只操作一个拨杆 / 开关，走遍所有档位，再完成识别。\n可回弹开关请按下并松开；三档开关请经过中位和两端。\n类型由你选择，档位与正反可实时核对。转换器未输出的通道无法识别。", 17))
	aux_button = UIStyle.button("识别一个拨杆 / 开关", _aux_capture)
	switches.add_child(aux_button)
	aux_rows = UIStyle.column(switches, 8)
	var bindings := _tab("动作绑定")
	bindings.add_child(UIStyle.label("为每个档位选择动作；进入该档位时执行一次，交互支持按住。\n例如：二档开关 1 档暂停、2 档恢复；回弹开关按下时重置。\n旋钮按低 / 中 / 高区间绑定。设置、失焦与重连时不会自动触发。", 17))
	binding_rows = UIStyle.column(bindings, 10)
	status = UIStyle.label("选择设备后，一次采集四轴；已有配置可直接调整正反和开关类型。", 17, Color("ebbd77"))
	status.custom_minimum_size.y = 48
	column.add_child(status)
	live = UIStyle.label("", 15, Color("a2bbc4"))
	live.custom_minimum_size.y = 56
	column.add_child(live)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	save_button = UIStyle.button("保存并使用遥控器", _accept)
	footer.add_child(save_button)
	if allow_offline_edit:
		save_button.text = "保存配置"
	footer.add_child(UIStyle.button("取消 / 返回", func(): closed.emit()))
	_refresh_devices()

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column := UIStyle.column(scroll, 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return column

func _refresh_devices() -> void:
	devices.assign(Input.get_connected_joypads())
	device_select.clear()
	for id in devices:
		device_select.add_item("%s  [设备 %d]" % [Input.get_joy_name(id), id])
	if devices.is_empty():
		device_select.add_item("未检测到 USB 游戏控制器 · 插入后刷新")
	var selected := 0
	for index in devices.size():
		if devices[index] == preferred_device or (preferred_device < 0 and Input.get_joy_guid(devices[index]) == initial_profile.get("guid", "")):
			selected = index
	device_select.select(selected)
	_select_device(selected)

func _select_device(index: int) -> void:
	device = devices[index] if index >= 0 and index < devices.size() else -1
	mode = ""
	mapping.clear()
	auxiliary.clear()
	profile_name.text = RadioProfiles.suggested_name(existing_profiles)
	if FlightInput.valid_profile(initial_profile) and (allow_offline_edit or (device >= 0 and (device == preferred_device or initial_profile.get("guid", "") == _device_guid()))):
		mapping = initial_profile.axes.duplicate(true)
		auxiliary = initial_profile.get("auxiliary", []).duplicate(true)
		for control: Dictionary in auxiliary:
			_normalize_channel_name(control)
		profile_name.text = initial_profile.get("name", "我的遥控器")
	record_button.disabled = true
	aux_button.text = "识别一个拨杆 / 开关"
	_rebuild_axes()
	_rebuild_auxiliary()
	status.text = "已载入配置，可调整后保存。" if not mapping.is_empty() else "选择设备后，点击「一次校准四轴」。"

func _connected() -> bool:
	return device >= 0 and Input.get_connected_joypads().has(device)

func _read_axes() -> Array[float]:
	return FlightInput.axis_values(device)

func _read_buttons() -> Array[bool]:
	return FlightInput.button_values(device)

func _device_guid() -> String:
	return Input.get_joy_guid(device)

func _device_name() -> String:
	return Input.get_joy_name(device)

func _begin() -> void:
	if not _connected():
		status.text = "未检测到设备。确认 USB 模拟器模式后刷新。"
		return
	mode = "sticks"
	capture.begin(_read_axes())
	record_button.disabled = false
	aux_button.text = "识别一个拨杆 / 开关"
	status.text = "正在采集四轴行程……两根摇杆走满行程后，三轴回中、油门最低，再完成采集。"

func _record() -> void:
	if mode != "sticks" or not _connected():
		return
	var rest := _read_axes()
	capture.sample(rest)
	var result := capture.stick_mapping(rest, mapping)
	if result.is_empty():
		status.text = "需要恰好 4 根轴走满行程，当前 %d 根。请三轴回中、油门最低；误碰开关可重新开始。" % capture.moved_axes().size()
		return
	for control: Dictionary in auxiliary.duplicate():
		if control.source == "axis" and capture.moved_axes().has(int(control.axis)):
			auxiliary.erase(control)
	mapping = result
	mode = ""
	record_button.disabled = true
	_rebuild_axes()
	_rebuild_auxiliary()
	status.text = "四轴行程已记录。动一下摇杆核对分配和正反；USB 没有统一的通道顺序。"

func _clear_rows(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _rebuild_axes() -> void:
	_clear_rows(axis_rows)
	axis_monitors.clear()
	if mapping.size() != 4:
		return
	var indices: Array[int] = []
	for axis: Dictionary in mapping.values():
		indices.append(int(axis.axis))
	indices.sort()
	for index in 4:
		var role := FlightInput.CHANNELS[index]
		var row := HBoxContainer.new()
		axis_rows.add_child(row)
		row.add_child(UIStyle.label(NAMES[index], 18))
		var select := OptionButton.new()
		for source in indices:
			select.add_item("轴 %d" % source, source)
		select.select(indices.find(int(mapping[role].axis)))
		select.item_selected.connect(func(selected: int): _assign_axis(role, select.get_item_id(selected)))
		row.add_child(select)
		var invert := CheckButton.new()
		invert.text = "反向"
		invert.button_pressed = mapping[role].invert
		invert.toggled.connect(func(value: bool): mapping[role].invert = value)
		row.add_child(invert)
		_deadzone_editor(row, mapping[role], 0.0 if role == "throttle" else 0.025, "最低油门死区" if role == "throttle" else "回中死区")
		var monitor := UIStyle.label("", 16)
		row.add_child(monitor)
		axis_monitors[role] = monitor

func _deadzone_editor(row: Node, control: Dictionary, fallback: float, caption: String) -> void:
	row.add_child(UIStyle.label(caption, 15))
	var field := SpinBox.new()
	field.min_value = 0
	field.max_value = 20
	field.step = 0.5
	field.suffix = "%"
	field.custom_minimum_size.x = 112
	field.value = float(control.get("deadzone", fallback)) * 100
	field.tooltip_text = "死区内输出保持稳定，死区外连续映射到满行程。0% 关闭；最大 20%。"
	field.value_changed.connect(func(value: float): control.deadzone = value / 100)
	row.add_child(field)

func _assign_axis(role: String, source: int) -> void:
	for other: String in mapping:
		if other != role and int(mapping[other].axis) == source:
			var old: Dictionary = mapping[role]
			mapping[role] = mapping[other]
			mapping[other] = old
			break
	_rebuild_axes()

func _aux_capture() -> void:
	if not _connected():
		return
	if mode == "auxiliary":
		_finish_auxiliary()
		return
	if mapping.size() != 4:
		status.text = "请先完成四轴校准，再识别拨杆与开关。"
		return
	mode = "auxiliary"
	record_button.disabled = true
	capture.begin(_read_axes(), _read_buttons())
	aux_button.text = "完成识别 · 已走遍所有档位"
	status.text = "只操作一个拨杆 / 开关，往返全部档位；可回弹开关按下并松开，再完成识别。"

func _finish_auxiliary() -> void:
	capture.sample(_read_axes(), _read_buttons())
	var excluded: Array[int] = []
	for axis: Dictionary in mapping.values():
		excluded.append(int(axis.axis))
	var moved := capture.moved_axes(excluded)
	var buttons := capture.changed_buttons.duplicate()
	buttons.sort()
	if moved.size() > 1 or (not moved.is_empty() and not buttons.is_empty()) or (moved.is_empty() and (buttons.is_empty() or buttons.size() > 3)):
		status.text = "未检测到唯一通道：请重新识别，只操作一个开关，走遍所有档位。"
		mode = ""
		aux_button.text = "识别一个拨杆 / 开关"
		return
	var control := {"id": "aux_" + str(Time.get_ticks_usec()), "name": "", "type": "two_position", "invert": false}
	if not moved.is_empty():
		var source := moved[0]
		control.merge({"source": "axis", "axis": source, "min": capture.lows[source], "max": capture.highs[source]})
	else:
		control.merge({"source": "buttons", "buttons": buttons})
		if buttons.size() >= 2:
			control.type = "three_position"
	control.name = source_label(control)
	for existing: Dictionary in auxiliary:
		var duplicate: bool = existing.source == control.source and ((control.source == "axis" and existing.axis == control.axis) or (control.source == "buttons" and _overlapping_buttons(existing.buttons, buttons)))
		if duplicate:
			status.text = "此输入已识别为「%s」，可直接修改它的类型或先移除。" % existing.name
			mode = ""
			aux_button.text = "识别一个拨杆 / 开关"
			return
	auxiliary.append(control)
	mode = ""
	aux_button.text = "识别一个拨杆 / 开关"
	_rebuild_auxiliary()
	status.text = "已识别。请选择实际开关类型，核对档位和正反，然后保存。"

static func _overlapping_buttons(first: Array, second: Array) -> bool:
	for index: Variant in first:
		if second.has(index):
			return true
	return false

static func source_label(control: Dictionary) -> String:
	if control.source == "axis":
		return "通道 %d" % int(control.axis)
	var numbers := PackedStringArray()
	for source: Variant in control.buttons:
		numbers.append(str(int(source)))
	return "按钮 " + "/".join(numbers)

static func _normalize_channel_name(control: Dictionary) -> void:
	# Old generated labels used discovery order; retain actual custom names.
	var name_text := String(control.name).strip_edges()
	if name_text.begins_with("通道 ") and name_text.trim_prefix("通道 ").is_valid_int():
		control.name = source_label(control)

func _rebuild_auxiliary() -> void:
	_clear_rows(aux_rows)
	aux_monitors.clear()
	for control: Dictionary in auxiliary:
		var row := HBoxContainer.new()
		aux_rows.add_child(row)
		var name_edit := LineEdit.new()
		name_edit.custom_minimum_size.x = 150
		name_edit.text = control.name
		name_edit.text_changed.connect(func(value: String): control.name = value; _rebuild_bindings())
		row.add_child(name_edit)
		var source_name := source_label(control)
		row.add_child(UIStyle.label(source_name, 15))
		var type_select := OptionButton.new()
		for index in TYPE_NAMES.size():
			type_select.add_item(TYPE_NAMES[index])
			var compatible: bool = control.source == "axis" or (control.buttons.size() >= 2 if index == 1 else control.buttons.size() == 1 and index != 3)
			type_select.set_item_disabled(index, not compatible)
		type_select.select(FlightInput.AUX_TYPES.find(control.type))
		type_select.item_selected.connect(func(index: int):
			if control.type != FlightInput.AUX_TYPES[index]:
				control.type = FlightInput.AUX_TYPES[index]
				control.erase("bindings")
				_rebuild_bindings()
				status.text = "类型已改变，已清除这个通道的动作绑定，请按新档位重新选择。")
		row.add_child(type_select)
		var invert := CheckButton.new()
		invert.text = "反向"
		invert.button_pressed = control.invert
		invert.toggled.connect(func(value: bool): control.invert = value)
		row.add_child(invert)
		if control.source == "axis":
			_deadzone_editor(row, control, 0.0, "回中死区" if control.type in ["analog", "three_position"] else "低端死区")
		var monitor := UIStyle.label("", 16)
		row.add_child(monitor)
		aux_monitors[control.id] = monitor
		row.add_child(UIStyle.button("移除", func(): auxiliary.erase(control); _rebuild_auxiliary()))
	_rebuild_bindings()

func _rebuild_bindings() -> void:
	_clear_rows(binding_rows)
	if auxiliary.is_empty():
		binding_rows.add_child(UIStyle.label("先在「拨杆与开关」页识别通道，即可绑定动作。", 17))
	for control: Dictionary in auxiliary:
		var title := source_label(control)
		if control.name != title:
			title += " · " + String(control.name)
		binding_rows.add_child(UIStyle.label(title + "  /  " + TYPE_NAMES[FlightInput.AUX_TYPES.find(control.type)], 18, Color("70d7cb")))
		var row := HFlowContainer.new()
		binding_rows.add_child(row)
		for position in FlightInput.binding_count(control):
			var group := HBoxContainer.new()
			row.add_child(group)
			var caption := "%d 档" % (position + 1)
			if control.type == "momentary":
				caption = "松开" if position == 0 else "按下"
			elif control.type == "analog":
				caption = ["低位", "中位", "高位"][position]
			group.add_child(UIStyle.label(caption, 16))
			var select := OptionButton.new()
			select.custom_minimum_size.x = 180
			var actions: Array = FlightInput.ACTION_NAMES.keys()
			for action: String in actions:
				select.add_item(FlightInput.ACTION_NAMES[action])
			select.select(actions.find(control.get("bindings", {}).get(str(position), "")))
			select.item_selected.connect(func(index: int):
				if not control.has("bindings"):
					control.bindings = {}
				control.bindings[str(position)] = actions[index])
			group.add_child(select)

func _process(_delta: float) -> void:
	if not is_instance_valid(live):
		return
	var connected := _connected()
	save_button.disabled = (not connected and not allow_offline_edit) or not mode.is_empty() or mapping.size() != 4
	aux_button.disabled = not connected or mode == "sticks"
	if not connected:
		if device >= 0:
			status.text = "设备已断开，请重新插入后刷新；未保存修改将丢弃。"
		mode = ""
		record_button.disabled = true
		live.text = "离线编辑已有配置 · 连接设备后再选择使用" if allow_offline_edit else "未连接设备"
		return
	var axes := _read_axes()
	var buttons := _read_buttons()
	if not mode.is_empty():
		capture.sample(axes, buttons)
	var raw_values := PackedStringArray()
	for index in axes.size():
		raw_values.append("%d:%+.2f" % [index, axes[index]])
	var pressed := PackedStringArray()
	for index in buttons.size():
		if buttons[index]:
			pressed.append(str(index))
	live.text = "通道（轴号） " + "  ".join(raw_values.slice(0, 5)) + "\n                     " + "  ".join(raw_values.slice(5)) + "   按钮 " + (",".join(pressed) if not pressed.is_empty() else "无")
	for role: String in axis_monitors:
		var axis: Dictionary = mapping[role]
		var value := FlightInput.normalize_axis(axes[int(axis.axis)], axis, role == "throttle")
		axis_monitors[role].text = "%+.2f   行程 %.2f ～ %.2f" % [value, axis.min, axis.max]
	for control: Dictionary in auxiliary:
		var value := FlightInput.auxiliary_value(control, axes[int(control.get("axis", 0))], buttons)
		aux_monitors[control.id].text = "%.0f%%" % (value * 100) if control.type == "analog" else ("按下" if value > 0 else "松开") if control.type == "momentary" else "%d 档" % (int(value) + 1)

func _accept() -> void:
	if not mode.is_empty() or (not _connected() and not allow_offline_edit):
		status.text = "请先完成采集，并保持设备连接。"
		return
	for field: SpinBox in find_children("*", "SpinBox", true, false):
		if field.get_line_edit().has_focus():
			field.apply()
	var error := RadioProfiles.name_error(existing_profiles, profile_name.text, editing_key)
	if not error.is_empty():
		status.text = error
		return
	var profile := {"name": profile_name.text.strip_edges(), "device_name": _device_name() if _connected() else initial_profile.get("device_name", ""), "guid": _device_guid() if _connected() else initial_profile.get("guid", ""), "axes": mapping.duplicate(true), "auxiliary": auxiliary.duplicate(true)}
	if profile.name.is_empty() or not FlightInput.valid_profile(profile):
		status.text = "请检查配置名称、通道名称和轴分配；三根姿态轴的中点必须位于行程内。"
		return
	accepted.emit(profile, device)
