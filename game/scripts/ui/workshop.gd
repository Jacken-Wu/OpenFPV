class_name Workshop
extends PanelContainer

signal apply_requested(build: Dictionary, rate: float, expo: float)
signal closed
var catalog: ContentCatalog
var store: ProgressStore
var build: Dictionary
var column: VBoxContainer
var tuning_box: VBoxContainer
var preview: Label
var rate_slider: HSlider
var expo_slider: HSlider
var rate := 360.0
var expo := 0.25
var selects: Dictionary = {}
var values: Dictionary = {}
var message := ""

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(900, 650)
	column = UIStyle.column(self, 9)
	column.add_child(UIStyle.label("装备台 / 永久取得，自由调整", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("机架、电机、桨叶须兼容；落地且锁定电机时应用。锁定内容可预览。", 17))
	var presets := HBoxContainer.new()
	column.add_child(presets)
	for id: String in catalog.presets:
		var preset: DronePresetDefinition = catalog.presets[id]
		var preset_id := id
		presets.add_child(UIStyle.button(preset.display_name + ("" if store.data.owned.has(id) else " [未取得]"), func():
			build = DroneAssembler.new(catalog).from_preset(preset_id)
			_sync_selects()
			_rebuild_tuning()))
	for slot: String in DroneAssembler.SLOTS:
		var row := HBoxContainer.new()
		column.add_child(row)
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
	tuning_box = UIStyle.column(column, 6)
	preview = UIStyle.label("", 18, Color("e5c291"))
	preview.custom_minimum_size.y = 74
	column.add_child(preview)
	var control_label := UIStyle.label("", 16)
	column.add_child(control_label)
	rate_slider = _slider(180, 600, 10, rate)
	expo_slider = _slider(0, 0.6, 0.05, expo)
	column.add_child(rate_slider)
	column.add_child(expo_slider)
	var refresh_controls := func(): control_label.text = "Acro 最大角速度 %d °/s   |   Expo %.2f   （偏航为 70%%）" % [rate_slider.value, expo_slider.value]
	rate_slider.value_changed.connect(func(_v: float): refresh_controls.call())
	expo_slider.value_changed.connect(func(_v: float): refresh_controls.call())
	refresh_controls.call()
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(UIStyle.button("保存并应用", func(): apply_requested.emit(_current_build(), rate_slider.value, expo_slider.value)))
	buttons.add_child(UIStyle.button("返回", func(): closed.emit()))
	_sync_selects()
	_rebuild_tuning()

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
	var resolved := DroneAssembler.new(catalog).resolve(_current_build(), store.data.owned)
	if resolved.ok:
		preview.text = "整机 %.0f g  ·  推重比 %.2f  ·  电机响应 %.0f ms\n%s" % [resolved.spec.mass * 1000, resolved.spec.thrust_weight, resolved.spec.response * 1000, message]
	else:
		preview.text = " / ".join(resolved.errors)

func _slider(low: float, high: float, step_value: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_value
	slider.value = initial
	slider.custom_minimum_size = Vector2(500, 20)
	return slider
