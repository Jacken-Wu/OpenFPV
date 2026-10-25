class_name Workshop
extends PanelContainer

signal apply_requested(build: Dictionary, flight: Dictionary)
signal closed
signal purchase_requested(id: String)
var catalog: ContentCatalog
var store: ProgressStore
var build: Dictionary
var flight_profile := FlightTuning.defaults()
var column: VBoxContainer
var tuning_box: VBoxContainer
var preview: Label
var feedback: Label
var tabs: TabContainer
var curve_plot: RateCurve
var curve_sample: Label
var rate_controls: Dictionary = {}
var advanced_controls: Dictionary = {}
var pid_controls: Dictionary = {}
var pid_filter: SpinBox
var selects: Dictionary = {}
var values: Dictionary = {}
var message := ""
var close_after_apply := false
var station_name := "综合服务平台"
var city_tag := "industrial"
var shop_credit: Label
var offer_buttons: Dictionary = {}
var preset_buttons: Dictionary = {}
var shop_category: OptionButton
var shop_cards: Dictionary = {}

func _ready() -> void:
	flight_profile = FlightTuning.with_pid(flight_profile)
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(1130, 810)
	column = UIStyle.column(self, 8)
	column.add_child(UIStyle.label(station_name + " / 综合服务", 26, Color("70d7cb")))
	column.add_child(UIStyle.label("已停靠 · 配件与套机商店 / 更换装备 / 参数微调 · 再次按交互键：保存并关闭", 17))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var equipment := _tab("装备")
	var presets := GridContainer.new()
	presets.columns = 2
	equipment.add_child(presets)
	for id: String in catalog.presets:
		var preset: DronePresetDefinition = catalog.presets[id]
		var preset_id := id
		var preset_button := UIStyle.button(preset.display_name + ("" if store.data.owned.has(id) else " [未取得]"), func():
			build = DroneAssembler.new(catalog).from_preset(preset_id)
			_sync_selects()
			_rebuild_tuning())
		presets.add_child(preset_button)
		preset_buttons[id] = preset_button
	for slot: String in DroneAssembler.SLOTS:
		var row := HBoxContainer.new()
		equipment.add_child(row)
		var label := UIStyle.label({"frame": "机架", "motor_set": "电机组", "propeller_set": "桨叶组"}[slot])
		label.custom_minimum_size.x = 110
		row.add_child(label)
		var select := OptionButton.new()
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(select)
		for id: String in catalog.sorted_ids():
			if catalog.parts.has(id) and catalog.parts[id].kind == slot:
				var part: PartDefinition = catalog.parts[id]
				select.add_item(part.display_name + ("" if store.data.owned.has(id) else " [未取得]"))
				select.set_item_metadata(select.item_count - 1, id)
		selects[slot] = select
		var selected_slot := slot
		select.item_selected.connect(func(index: int):
			build[DroneAssembler.SLOTS[selected_slot]] = selects[selected_slot].get_item_metadata(index)
			build.tuning = {}
			_rebuild_tuning())
	tuning_box = UIStyle.column(equipment, 6)
	preview = UIStyle.label("", 18, Color("e5c291"))
	preview.custom_minimum_size.y = 74
	equipment.add_child(preview)
	_build_rates(_tab("操控曲线"))
	_build_advanced(_tab("高级环境"))
	_build_shop(_tab("商店"))
	feedback = UIStyle.label("", 17, Color("e5c291"))
	column.add_child(feedback)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIStyle.button("保存并应用", func(): submit(false)))
	buttons.add_child(UIStyle.button("取消 / 返回", func(): closed.emit()))
	_sync_selects()
	_rebuild_tuning()
	_refresh_flight_preview()
	refresh_shop()

func _build_shop(content: VBoxContainer) -> void:
	shop_credit = UIStyle.label("", 22, Color("e5c291"))
	content.add_child(shop_credit)
	content.add_child(UIStyle.label("购买后永久解锁；套机包含机架、四个匹配电机与四片桨叶。", 17))
	shop_category = OptionButton.new()
	for title: String in ["全部商品", "完整套机", "机架", "电机组", "桨叶组"]:
		shop_category.add_item(title)
	content.add_child(shop_category)
	shop_category.item_selected.connect(func(_index: int): _filter_shop())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for offer: OfferDefinition in catalog.manifest.offers:
		if offer.city_tag != city_tag:
			continue
		var id := offer.id
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 490
		grid.add_child(card)
		shop_cards[id] = card
		var details := UIStyle.column(card, 6)
		var title := UIStyle.label(offer.display_name, 20, Color("70d7cb"))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(title)
		var description := UIStyle.label(offer.description if not offer.description.is_empty() else "永久解锁 · 可在装备页查看规格和兼容性。", 16)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(description)
		var button := UIStyle.button("", func(): purchase_requested.emit(id))
		details.add_child(button)
		offer_buttons[id] = button
	_filter_shop()

func _filter_shop() -> void:
	for id: String in shop_cards:
		var offer: OfferDefinition = catalog.entries[id]
		var category: int = 1 if not offer.preset_id.is_empty() else {"frame": 2, "motor_set": 3, "propeller_set": 4}[catalog.parts[offer.part_id].kind]
		shop_cards[id].visible = shop_category.selected == 0 or shop_category.selected == category

func refresh_shop() -> void:
	shop_credit.text = "余额 %d 信用点 · 完成探索委托可取得信用点" % store.data.credits
	for id: String in preset_buttons:
		preset_buttons[id].text = catalog.presets[id].display_name + ("" if store.data.owned.has(id) else " [未取得]")
	for id: String in offer_buttons:
		var offer: OfferDefinition = catalog.entries[id]
		var owned: bool = store.data.owned.has(offer.preset_id if not offer.preset_id.is_empty() else offer.part_id)
		offer_buttons[id].text = "%s · %d 信用点%s" % [offer.display_name, offer.price, " [已取得]" if owned else ""]
		offer_buttons[id].disabled = owned or store.data.credits < offer.price
	for slot: String in selects:
		var select: OptionButton = selects[slot]
		for index in select.item_count:
			var id: String = select.get_item_metadata(index)
			select.set_item_text(index, catalog.parts[id].display_name + ("" if store.data.owned.has(id) else " [未取得]"))

func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := UIStyle.column(scroll, 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return content

func _build_rates(content: VBoxContainer) -> void:
	content.add_child(UIStyle.label("分别设置横滚、俯仰、偏航。Expo 越大，中间越柔和；满杆仍达到该轴角速度上限。", 17))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	content.add_child(row)
	var controls := UIStyle.column(row, 4)
	controls.custom_minimum_size.x = 390
	for index in 3:
		var axis := FlightTuning.AXES[index]
		controls.add_child(UIStyle.label(["横滚", "俯仰", "偏航"][index], 20, RateCurve.COLORS[index]))
		rate_controls[axis] = {}
		for key: String in ["max_rate_dps", "expo"]:
			rate_controls[axis][key] = _flight_field(controls, "角速度上限 °/s" if key == "max_rate_dps" else "Expo", key, flight_profile.axes[axis][key])
	var graph := UIStyle.column(row, 8)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph.add_child(UIStyle.label("摇杆输入 → 目标角速度  /  三轴实时曲线", 18))
	curve_plot = RateCurve.new()
	graph.add_child(curve_plot)
	var legend := HBoxContainer.new()
	graph.add_child(legend)
	for index in 3:
		legend.add_child(UIStyle.label(["横滚", "俯仰", "偏航"][index] + "   ", 17, RateCurve.COLORS[index]))
	curve_sample = UIStyle.label("", 16)
	graph.add_child(curve_sample)
	graph.add_child(UIStyle.label("鼠标移到曲线上查看精确值；相同参数的曲线会重合。\n横轴：摇杆百分比；纵轴：角速度 °/s。", 16))
	controls.add_child(UIStyle.button("恢复默认操控", func():
		var defaults := FlightTuning.defaults()
		for axis in FlightTuning.AXES:
			for key: String in rate_controls[axis]:
				rate_controls[axis][key].value = defaults.axes[axis][key]))
	_build_pid(content)

func _build_pid(content: VBoxContainer) -> void:
	content.add_child(UIStyle.label("角速度 PID", 23, Color("70d7cb")))
	content.add_child(UIStyle.label("P 控制跟随力度，I 修正持续偏差，D 增加快速回杆的刹停阻尼。\n这些数值使用本游戏的控制单位；修改后保存应用，可独立恢复默认。", 17))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	content.add_child(row)
	for index in 3:
		var axis := FlightTuning.AXES[index]
		var group := UIStyle.column(row, 4)
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_child(UIStyle.label(["横滚", "俯仰", "偏航"][index], 20, RateCurve.COLORS[index]))
		pid_controls[axis] = {}
		for key: String in ["p", "i", "d"]:
			pid_controls[axis][key] = _flight_field(group, {"p": "P · 1/s", "i": "I · 1/s²", "d": "D · 阻尼"}[key], key, flight_profile.pid[axis][key])
	pid_filter = _flight_field(content, "D 项低通滤波 Hz", "d_filter_hz", flight_profile.d_filter_hz)
	content.add_child(UIStyle.button("恢复默认 PID", func():
		var defaults := FlightTuning.defaults()
		for axis in FlightTuning.AXES:
			for key: String in pid_controls[axis]:
				pid_controls[axis][key].value = defaults.pid[axis][key]
		pid_filter.value = defaults.d_filter_hz))

func _build_advanced(content: VBoxContainer) -> void:
	content.add_child(UIStyle.label("调整当前飞行仿真的环境参数。保存后生效，配件原始规格保持不变。", 17))
	for key: String in ["gravity", "air_drag", "angular_drag"]:
		var names := {"gravity": "重力加速度 m/s²", "air_drag": "空气阻力倍率", "angular_drag": "转动阻力倍率"}
		advanced_controls[key] = _flight_field(content, names[key], key, flight_profile[key])
	content.add_child(UIStyle.label("重力默认 9.81 m/s²，设为 0 可体验失重。\n阻力默认 1 倍；0 关闭对应阻力，大于 1 增强阻力。\n空气阻力影响平移减速，转动阻力影响转动时的阻尼。", 17, Color("a2bbc4")))
	content.add_child(UIStyle.button("恢复默认环境", func():
		var defaults := FlightTuning.defaults()
		for key: String in advanced_controls:
			advanced_controls[key].value = defaults[key]))

func _flight_field(parent: Node, title: String, key: String, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := UIStyle.label(title, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var rule: Dictionary = FlightTuning.RULES[key]
	var spin := SpinBox.new()
	spin.min_value = rule.min
	spin.max_value = rule.max
	spin.step = rule.step
	spin.value = initial
	spin.custom_minimum_size.x = 125
	row.add_child(spin)
	var slider := _slider(rule.min, rule.max, rule.step, initial)
	parent.add_child(slider)
	spin.value_changed.connect(func(value: float): slider.value = value; _refresh_flight_preview())
	slider.value_changed.connect(func(value: float): spin.value = value)
	return spin

func _refresh_flight_preview() -> void:
	if not is_instance_valid(curve_plot) or advanced_controls.size() < 3:
		return
	for axis in FlightTuning.AXES:
		for key: String in rate_controls[axis]:
			flight_profile.axes[axis][key] = rate_controls[axis][key].value
	for key: String in advanced_controls:
		flight_profile[key] = advanced_controls[key].value
	if pid_controls.size() == 3 and is_instance_valid(pid_filter):
		for axis in FlightTuning.AXES:
			for key: String in pid_controls[axis]:
				flight_profile.pid[axis][key] = pid_controls[axis][key].value
		flight_profile.d_filter_hz = pid_filter.value
	curve_plot.set_profile(flight_profile)
	var samples := curve_plot.sample(0.5)
	curve_sample.text = "半杆输出：横滚 %.1f · 俯仰 %.1f · 偏航 %.1f °/s" % [samples.x, samples.y, samples.z]

func _sync_selects() -> void:
	for slot: String in selects:
		var select: OptionButton = selects[slot]
		for index in select.item_count:
			if select.get_item_metadata(index) == build[DroneAssembler.SLOTS[slot]]:
				select.select(index)

func _rebuild_tuning() -> void:
	for child in tuning_box.get_children():
		tuning_box.remove_child(child)
		child.queue_free()
	values.clear()
	for slot: String in DroneAssembler.SLOTS:
		var part: PartDefinition = catalog.parts[build[DroneAssembler.SLOTS[slot]]]
		values[slot] = {}
		for key: String in part.tuning:
			var rule: Dictionary = part.tuning[key]
			var requested := float(build.get("tuning", {}).get(slot, {}).get(key, rule.default))
			var label := UIStyle.label("", 16)
			tuning_box.add_child(label)
			var slider := _slider(rule.min, rule.max, rule.step, requested)
			tuning_box.add_child(slider)
			values[slot][key] = slider
			var title: String = {"camera_mount_tilt_deg": "相机上仰角", "response_trim": "电机响应微调（越小越快）", "aero_trim": "桨叶推力微调"}.get(key, key)
			var update := func(v: float): label.text = "%s   %.3f   [%.3f — %.3f]" % [title, v, rule.min, rule.max]; _preview()
			slider.value_changed.connect(update)
			label.text = "%s   %.3f   [%.3f — %.3f]" % [title, requested, rule.min, rule.max]
	_preview()

func _current_build() -> Dictionary:
	var result := build.duplicate(true)
	result.tuning = {}
	for slot: String in values:
		result.tuning[slot] = {}
		for key: String in values[slot]:
			result.tuning[slot][key] = values[slot][key].value
	return result

func _preview() -> void:
	feedback.text = message
	var resolved := DroneAssembler.new(catalog).resolve(_current_build(), store.data.owned)
	if resolved.ok:
		preview.text = "整机 %.0f g  ·  标准重力推重比 %.2f  ·  电机响应 %.0f ms\n%s" % [resolved.spec.mass * 1000, resolved.spec.thrust_weight, resolved.spec.response * 1000, message]
	else:
		preview.text = " / ".join(resolved.errors)

func _slider(low: float, high: float, step_value: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_value
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 20)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return slider

func submit(close_after: bool = false) -> void:
	for field: SpinBox in find_children("*", "SpinBox", true, false):
		# Hidden/unfocused fields may still display text from the previous frame.
		# Only commit the active editor; slider/value changes are already authoritative.
		if field.get_line_edit().has_focus():
			field.apply()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_refresh_flight_preview()
	close_after_apply = close_after
	apply_requested.emit(_current_build(), flight_profile.duplicate(true))
