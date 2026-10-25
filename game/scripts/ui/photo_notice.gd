class_name PhotoNotice
extends PanelContainer
var image_path := ""
var remaining := 0.0
var suppressed := false
var exposing := false
var path_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -780
	offset_right = -24
	offset_top = -315
	offset_bottom = -135
	z_index = 210
	theme = UIStyle.theme()
	var column := UIStyle.column(self, 5)
	column.add_child(UIStyle.label("照片已保存", 19, Color("83e2c7")))
	path_label = UIStyle.label("", 15)
	path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	path_label.custom_minimum_size.x = 660
	column.add_child(path_label)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(UIStyle.button("复制完整路径", func(): DisplayServer.clipboard_set(image_path)))
	row.add_child(UIStyle.button("打开照片文件夹", func(): OS.shell_open(image_path.get_base_dir())))
	visible = false

func announce(path: String) -> void:
	image_path = ProjectSettings.globalize_path(path)
	path_label.text = image_path
	remaining = 10.0
	visible = true

func _process(delta: float) -> void:
	remaining = maxf(0, remaining - delta)
	visible = remaining > 0 and not suppressed and not exposing
