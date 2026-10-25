class_name RadioMenu
extends PanelContainer
signal edit_requested(key: String, device: int)
signal use_requested(key: String, device: int)
signal delete_requested(key: String)
signal keyboard_requested
signal closed
var settings: Dictionary = {}
var keys: Array[String] = []
var devices: Array[int] = []
var profile_select: OptionButton
var device_select: OptionButton
var feedback: Label
var details: Label
var use_button: Button
var edit_button: Button
var delete_button: Button
var confirmation: HBoxContainer
var pending_delete := ""

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(780, 540)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("遥控器与输入设备", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("先选择配置，再选择 USB 输入设备；核对通道方向后使用。", 17))
	profile_select = _select_row(column, "遥控器配置")
	profile_select.item_selected.connect(func(_index: int): _selection_changed())
	device_select = _select_row(column, "输入设备")
	device_select.item_selected.connect(func(_index: int): _selection_changed())
	column.add_child(UIStyle.button("刷新设备与配置", refresh))
	details = UIStyle.label("", 17, Color("a2bbc4"))
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.y = 60
	column.add_child(details)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	use_button = UIStyle.button("使用所选配置与设备", func(): use_requested.emit(selected_key(), selected_device()))
	actions.add_child(use_button)
	edit_button = UIStyle.button("编辑配置", func(): edit_requested.emit(selected_key(), selected_device()))
	actions.add_child(edit_button)
	delete_button = UIStyle.button("删除配置", _request_delete)
	actions.add_child(delete_button)
	column.add_child(UIStyle.button("新建配置 / 校准", func(): edit_requested.emit("", selected_device())))
	confirmation = HBoxContainer.new()
	column.add_child(confirmation)
	confirmation.add_child(UIStyle.button("确认删除所选配置", func(): delete_requested.emit(pending_delete)))
	confirmation.add_child(UIStyle.button("取消删除", func(): pending_delete = ""; confirmation.hide()))
	confirmation.hide()
	feedback = UIStyle.label("", 17, Color("e5c291"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	column.add_child(UIStyle.button("明确切换为键盘调试", func(): keyboard_requested.emit()))
	column.add_child(UIStyle.button("返回", func(): closed.emit()))
	refresh()

func _select_row(parent: Node, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := UIStyle.label(caption, 18)
	label.custom_minimum_size.x = 130
	row.add_child(label)
	var select := OptionButton.new()
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select.clip_text = true
	row.add_child(select)
	return select

func selected_key() -> String:
	return keys[profile_select.selected] if profile_select.selected >= 0 and profile_select.selected < keys.size() else ""

func selected_device() -> int:
	return devices[device_select.selected] if device_select.selected >= 0 and device_select.selected < devices.size() else -1

func refresh() -> void:
	var previous := selected_key()
	var previous_device := selected_device()
	keys.clear()
	profile_select.clear()
	var profiles: Dictionary = settings.get("radio_profiles", {})
	keys.assign(profiles.keys())
	keys.sort_custom(func(a: String, b: String):
		var first := String(profiles[a].get("name", ""))
		var second := String(profiles[b].get("name", ""))
		return a < b if first == second else first.naturalnocasecmp_to(second) < 0)
	var counts: Dictionary = {}
	for key in keys:
		var name_text := String(profiles[key].get("name", "未命名")).strip_edges().to_lower()
		counts[name_text] = int(counts.get(name_text, 0)) + 1
	for index in keys.size():
		var profile: Dictionary = profiles[keys[index]]
		var name_text := String(profile.get("name", "未命名"))
		var suffix := " · %s · #%d" % [profile.get("device_name", "旧设备"), index + 1] if counts.get(name_text.strip_edges().to_lower(), 0) > 1 else ""
		profile_select.add_item(name_text + suffix + (" [当前]" if settings.get("active_radio_profile", "") == keys[index] else ""))
	if keys.is_empty():
		profile_select.add_item("暂无配置，请新建并校准")
	var preferred: String = previous if keys.has(previous) else settings.get("active_radio_profile", "")
	profile_select.select(maxi(0, keys.find(preferred)))
	devices.assign(Input.get_connected_joypads())
	device_select.clear()
	for device in devices:
		device_select.add_item("%s [设备 %d]" % [Input.get_joy_name(device), device])
	if devices.is_empty():
		device_select.add_item("未连接 USB 控制器")
	if previous_device < 0 and not selected_key().is_empty():
		var guid: String = profiles[selected_key()].get("guid", "")
		for device in devices:
			if Input.get_joy_guid(device) == guid:
				previous_device = device
				break
	device_select.select(maxi(0, devices.find(previous_device)))
	_selection_changed()

func _selection_changed() -> void:
	pending_delete = ""
	confirmation.hide()
	var key := selected_key()
	var valid: bool = not key.is_empty() and FlightInput.valid_profile(settings.radio_profiles[key])
	use_button.disabled = not valid or selected_device() < 0
	edit_button.disabled = not valid
	delete_button.disabled = key.is_empty()
	if key.is_empty():
		details.text = "配置与输入设备分别选择；没有连接设备时仍可管理已保存的配置。"
	else:
		var profile: Dictionary = settings.radio_profiles[key]
		details.text = "已保存%d份配置 · %s · %d个辅助通道\n%s" % [keys.size(), profile.get("device_name", "旧设备"), profile.get("auxiliary", []).size(), "使用到不同设备前，请核对轴号、正反与死区。" if valid else "此配置无效，可删除后重新校准。"]

func _request_delete() -> void:
	pending_delete = selected_key()
	if pending_delete.is_empty():
		return
	confirmation.show()
	feedback.text = "删除「%s」？删除当前配置后会暂停，需重新选择输入。" % settings.radio_profiles[pending_delete].get("name", "未命名")
