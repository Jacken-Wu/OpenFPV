class_name AboutMenu
extends PanelContainer
signal closed
var tabs: TabContainer

static func license_status() -> Dictionary:
	var project_path := "res://legal/openfpv-license.txt"
	var engine_path := "res://legal/godot-notices.txt"
	if not FileAccess.file_exists(project_path) or not FileAccess.file_exists(engine_path): return {"ok": false}
	var project := FileAccess.get_file_as_string(project_path)
	var engine := FileAccess.get_file_as_string(engine_path)
	return {"ok": project.contains("MIT License") and engine.contains(Engine.get_license_text()) and engine.contains("Third-party components") and engine.length() > 50000, "project_sha256": project.sha256_text(), "engine_sha256": engine.sha256_text()}

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(1000, 720)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("OpenFPV · 关于与许可", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("自由飞行，探索重连边境。", 18))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	for entry: Array in [["项目 MIT 许可", "res://legal/openfpv-license.txt"], ["Godot 与第三方声明", "res://legal/godot-notices.txt"]]:
		var text := TextEdit.new()
		text.name = entry[0]
		text.text = FileAccess.get_file_as_string(entry[1])
		text.editable = false
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.add_theme_font_size_override("font_size", 16)
		text.add_theme_color_override("font_readonly_color", Color("d6e3e6"))
		tabs.add_child(text)
	column.add_child(UIStyle.button("返回", func(): closed.emit()))
