class_name InputDisplayMenu
extends PanelContainer
signal closed
var store: ProgressStore
var draft := InputDisplay.defaults()
var feedback: Label
var sticks: CheckButton
var switches: CheckButton
var layout_select: OptionButton

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(650, 410)
	draft = InputDisplay.from_settings(store.data.settings)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("操作预览", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("在底部状态栏右侧显示，便于查看当前输入和录制操作。", 17))
	sticks = CheckButton.new()
	sticks.text = "显示双摇杆预览"
	sticks.button_pressed = draft.sticks
	column.add_child(sticks)
	switches = CheckButton.new()
	switches.text = "显示拨杆 / 开关状态"
	switches.button_pressed = draft.switches
	column.add_child(switches)
	layout_select = OptionButton.new()
	layout_select.add_item("左手油门 · Mode 2", 2)
	layout_select.add_item("右手油门 · Mode 1", 1)
	layout_select.select(0 if draft.mode == 2 else 1)
	column.add_child(layout_select)
	column.add_child(UIStyle.label("显示校准、正反和死区处理后的输入；暂停时仍可观察遥控器。\n菜单和拍照曝光时隐藏预览。辅助通道自动分为多列同时显示。", 17))
	feedback = UIStyle.label("", 17, Color("e5c291"))
	column.add_child(feedback)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(UIStyle.button("保存并返回", submit))
	row.add_child(UIStyle.button("取消 / 返回", func(): closed.emit()))

func submit() -> void:
	draft = {"sticks": sticks.button_pressed, "switches": switches.button_pressed, "mode": layout_select.get_selected_id()}
	var settings: Dictionary = store.data.settings.duplicate(true)
	settings.input_display = draft.duplicate(true)
	var result := store.save_settings(settings)
	if not result.ok:
		feedback.text = result.message
		return
	closed.emit()
