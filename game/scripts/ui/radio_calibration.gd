class_name RadioCalibration
extends PanelContainer

signal accepted(profile: Dictionary, device: int)
signal closed
var device_select: OptionButton
var status: Label
var live: Label
var record_button: Button
var profile_name: LineEdit
var devices: Array[int] = []
var device := -1
var step := -1
var recording := false
var lows: Array[float] = []
var highs: Array[float] = []
var centers: Array[float] = []
var mapping: Dictionary = {}
const ROLES: Array[String] = ["roll", "pitch", "yaw", "throttle"]
const NAMES: Array[String] = ["横滚", "俯仰", "偏航", "油门"]
const POSITIVE: Array[String] = ["最右端", "最前端", "最右端", "最低油门位置"]

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(850, 610)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("遥控器 / 独立轴校准", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("适用于富斯 i6x + USB 加密狗。先关闭遥控器混控，四个通道使用完整行程。\n解锁、重置和菜单使用键盘；游戏不依赖加密狗是否传输开关通道。", 17))
	device_select = OptionButton.new()
	column.add_child(device_select)
	_refresh_devices()
	profile_name = LineEdit.new()
	profile_name.placeholder_text = "给这份配置命名，例如 i6x-我的摇杆设置"
	profile_name.text = "i6x"
	column.add_child(profile_name)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(UIStyle.button("刷新设备", _refresh_devices))
	row.add_child(UIStyle.button("开始：回中三轴，油门放最低", _begin))
	status = UIStyle.label("选择设备，然后按提示依次移动每根摇杆。", 19)
	status.custom_minimum_size.y = 100
	column.add_child(status)
	live = UIStyle.label("", 16, Color("a2bbc4"))
	live.custom_minimum_size.y = 140
	column.add_child(live)
	record_button = UIStyle.button("记录这根轴", _record)
	record_button.disabled = true
	column.add_child(record_button)
	column.add_child(UIStyle.button("保存并使用遥控器", _accept))
	column.add_child(UIStyle.button("返回", func(): closed.emit()))

func _refresh_devices() -> void:
	devices.assign(Input.get_connected_joypads())
	device_select.clear()
	for id in devices:
		device_select.add_item("%s  [设备 %d]" % [Input.get_joy_name(id), id])
	if devices.is_empty():
		device_select.add_item("未检测到 USB 游戏控制器 · 插入后刷新")
	device = devices[0] if not devices.is_empty() else -1
	recording = false
	step = -1
	mapping.clear()

func _begin() -> void:
	if devices.is_empty():
		status.text = "未检测到设备。确认 USB 加密狗处于模拟器模式后刷新。"
		return
	device = devices[device_select.selected]
	centers.clear()
	for axis in 10:
		centers.append(Input.get_joy_axis(device, axis))
	mapping.clear()
	step = 0
	_start_step()

func _start_step() -> void:
	lows.clear()
	highs.clear()
	for axis in 10:
		var raw := Input.get_joy_axis(device, axis)
		lows.append(raw)
		highs.append(raw)
	recording = true
	record_button.disabled = false
	status.text = "%d / 4   %s\n只移动这根轴，往返完整行程数次，最后停在%s，再点击记录。" % [step + 1, NAMES[step], POSITIVE[step]]

func _record() -> void:
	if not recording:
		return
	var chosen := -1
	var span := 0.0
	for axis in 10:
		var used := false
		for previous: Dictionary in mapping.values():
			used = used or int(previous.axis) == axis
		if not used and highs[axis] - lows[axis] > span:
			span = highs[axis] - lows[axis]
			chosen = axis
	if span < 0.6:
		status.text += "\n行程不足或重复轴，请只移动当前轴并走满行程。"
		return
	var raw := Input.get_joy_axis(device, chosen)
	if step < 3 and absf(raw - centers[chosen]) < span * 0.25:
		status.text += "\n请停在提示的正向端点，以便识别反向。"
		return
	mapping[ROLES[step]] = {"axis": chosen, "min": lows[chosen], "max": highs[chosen], "center": centers[chosen], "invert": raw < centers[chosen] if step < 3 else raw > (lows[chosen] + highs[chosen]) * 0.5, "deadzone": 0.025}
	step += 1
	if step == 4:
		recording = false
		record_button.disabled = true
		status.text = "校准完成。核对下方通道：右滚 / 前倾 / 右转为正，油门从 0 到 1。\n保存后仍保持暂停；最低油门时按 P 恢复，再按空格解锁。"
	else:
		_start_step()

func _process(_delta: float) -> void:
	if not is_instance_valid(live) or device < 0:
		return
	if not Input.get_connected_joypads().has(device):
		status.text = "设备已断开，请重新插入后刷新和校准。"
		recording = false
		return
	var lines := PackedStringArray()
	var raw_values := PackedStringArray()
	for axis in 10:
		var raw := Input.get_joy_axis(device, axis)
		if recording:
			lows[axis] = minf(lows[axis], raw)
			highs[axis] = maxf(highs[axis], raw)
		raw_values.append("%d:%+.2f" % [axis, raw])
	lines.append("原始轴   " + "   ".join(raw_values.slice(0, 5)))
	lines.append("              " + "   ".join(raw_values.slice(5)))
	for role: String in mapping:
		var axis: Dictionary = mapping[role]
		var normalized := FlightInput.normalize_axis(Input.get_joy_axis(device, int(axis.axis)), axis, role == "throttle")
		lines.append("%s → 轴 %d   %+.2f   %s" % [role, axis.axis, normalized, "反向" if axis.invert else "正向"])
	live.text = "\n".join(lines)

func _accept() -> void:
	if mapping.size() != 4 or device < 0 or not Input.get_connected_joypads().has(device):
		status.text = "请先完成四轴校准。"
		return
	if profile_name.text.strip_edges().is_empty():
		status.text = "请填写配置名称。"
		return
	var profile := {"name": profile_name.text.strip_edges(), "device_name": Input.get_joy_name(device), "guid": Input.get_joy_guid(device), "axes": mapping.duplicate(true)}
	if not FlightInput.valid_profile(profile):
		status.text = "端点或中点无效，请将三根回中轴归中后重新开始。"
		return
	accepted.emit(profile, device)
