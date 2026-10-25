class_name AudioMenu
extends PanelContainer
signal closed
var mixer: GameAudioMixer
var store: ProgressStore
var baseline: Dictionary
var draft: Dictionary
var committed := false
var device_select: OptionButton
var devices := PackedStringArray()
var fields: Dictionary = {}
var feedback: Label

func _ready() -> void:
	baseline = mixer.settings.duplicate(true)
	draft = baseline.duplicate(true)
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(690, 590)
	var column := UIStyle.column(self, 14)
	column.add_child(UIStyle.label("声音设置", 30, Color("70d7cb")))
	column.add_child(UIStyle.label("调节时实时试听；保存后保留，取消或 Esc 撤销。", 17))
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(UIStyle.label("输出设备", 18))
	device_select = OptionButton.new()
	device_select.custom_minimum_size.x = 350
	device_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	device_select.clip_text = true
	row.add_child(device_select)
	row.add_child(UIStyle.button("刷新", refresh_devices))
	device_select.item_selected.connect(func(index: int): draft.output_device = devices[index]; _preview())
	feedback = UIStyle.label("", 16, Color("e5c291"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for key: String in GameAudioSettings.LABELS:
		var volume_row := HBoxContainer.new()
		column.add_child(volume_row)
		var label := UIStyle.label(GameAudioSettings.LABELS[key], 18)
		label.custom_minimum_size.x = 165
		volume_row.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		volume_row.add_child(slider)
		var number := SpinBox.new()
		number.max_value = 100
		number.suffix = "%"
		number.custom_minimum_size.x = 110
		volume_row.add_child(number)
		fields[key] = number
		number.value = float(draft[key]) * 100
		slider.value = number.value
		number.value_changed.connect(func(value: float):
			slider.set_value_no_signal(value)
			draft[key] = value / 100
			_preview())
		slider.value_changed.connect(func(value: float): number.value = value)
	column.add_child(UIStyle.label("音效总音量控制电机和快门；音乐独立调节。\n群系切换时音乐渐变衔接，暂停菜单中继续播放。", 17))
	column.add_child(feedback)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	footer.add_child(UIStyle.button("保存并返回", submit))
	footer.add_child(UIStyle.button("恢复默认", func():
		draft = GameAudioSettings.defaults()
		for key: String in fields:
			fields[key].value = draft[key] * 100
		refresh_devices()
		_preview()))
	footer.add_child(UIStyle.button("取消 / 返回", func(): closed.emit()))
	refresh_devices()

func refresh_devices() -> void:
	devices = mixer.output_devices()
	if not devices.has("Default"):
		devices.insert(0, "Default")
	if not devices.has(draft.output_device):
		devices.append(draft.output_device)
	device_select.clear()
	for device in devices:
		device_select.add_item("系统默认设备" if device == "Default" else device)
	device_select.select(devices.find(draft.output_device))
	_preview()

func _preview() -> void:
	mixer.apply(draft)
	feedback.text = "设备不可用，暂用系统默认设备；重新连接后自动恢复。" if not mixer.output_devices().has(draft.output_device) and draft.output_device != "Default" else "0% 静音 · 设置跨存档保留"

func submit() -> void:
	for field: SpinBox in fields.values():
		if field.get_line_edit().has_focus():
			field.apply()
	var settings: Dictionary = store.data.settings.duplicate(true)
	settings.audio = draft.duplicate(true)
	var result := store.save_settings(settings)
	if not result.ok:
		feedback.text = result.message
		return
	committed = true
	mixer.apply(draft)
	closed.emit()

func _exit_tree() -> void:
	if not committed and is_instance_valid(mixer):
		mixer.apply(baseline)
