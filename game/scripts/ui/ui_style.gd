class_name UIStyle
extends RefCounted

static func theme() -> Theme:
	var value := Theme.new()
	value.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101c29f2")
	panel.border_color = Color("3e5f6c")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	value.set_stylebox("panel", "PanelContainer", panel)
	var normal := panel.duplicate() as StyleBoxFlat
	normal.bg_color = Color("223544")
	normal.set_corner_radius_all(6)
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	for control: String in ["Button", "OptionButton"]:
		value.set_stylebox("normal", control, normal)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("305b65")
		value.set_stylebox("hover", control, hover)
		value.set_stylebox("pressed", control, hover)
		value.set_color("font_color", control, Color("e1ecee"))
	value.set_color("font_color", "Label", Color("d6e3e6"))
	return value

static func label(text: String, size: int = 18, color: Color = Color("d6e3e6")) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", size)
	value.add_theme_color_override("font_color", color)
	return value

static func button(text: String, action: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.pressed.connect(action)
	value.focus_mode = Control.FOCUS_NONE
	return value

static func column(parent: Node, separation: int = 12) -> VBoxContainer:
	var value := VBoxContainer.new()
	value.add_theme_constant_override("separation", separation)
	parent.add_child(value)
	return value
