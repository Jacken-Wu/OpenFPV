class_name UnlockNotifications
extends VBoxContainer
var shown: Array[String] = []
var suppressed := false

func set_suppressed(value: bool) -> void:
	visible = not value
	if value == suppressed:
		return
	suppressed = value
	for panel in get_children():
		var tween: Tween = panel.get_meta("lifetime", null)
		if tween != null and tween.is_valid():
			if value:
				tween.pause()
			else:
				tween.play()
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	offset_left = -230
	offset_right = 230
	offset_top = 132
	offset_bottom = 132
	custom_minimum_size.x = 460
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	add_theme_constant_override("separation", 6)
func announce(text: String) -> void:
	shown.append(text)
	if shown.size() > 12:
		shown.pop_front()
	while get_child_count() >= 3:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.16, 0.2, 0.68)
	style.border_color = Color("72d9bc")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var label := UIStyle.label(text, 20, Color("b6f0d7"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	panel.add_child(label)
	add_child(panel)
	var tween := panel.create_tween()
	panel.set_meta("lifetime", tween)
	tween.tween_interval(3.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
	if suppressed:
		tween.pause()
