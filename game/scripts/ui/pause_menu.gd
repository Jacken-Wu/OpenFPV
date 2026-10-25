class_name PauseMenu
extends PanelContainer
signal resume_requested
signal saves_requested
signal help_requested
signal radio_requested
signal audio_requested
signal input_display_requested
signal achievements_requested
signal about_requested
signal quit_requested
var feedback: Label

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(490, 420)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("已暂停", 30, Color("70d7cb")))
	column.add_child(UIStyle.label("Esc 返回进入菜单前的状态", 16))
	column.add_child(UIStyle.button("继续游戏", func(): resume_requested.emit()))
	column.add_child(UIStyle.button("存档管理", func(): saves_requested.emit()))
	column.add_child(UIStyle.button("探索成就", func(): achievements_requested.emit()))
	column.add_child(UIStyle.button("操作帮助", func(): help_requested.emit()))
	column.add_child(UIStyle.button("遥控器设置", func(): radio_requested.emit()))
	column.add_child(UIStyle.button("声音设置", func(): audio_requested.emit()))
	column.add_child(UIStyle.button("操作预览", func(): input_display_requested.emit()))
	column.add_child(UIStyle.button("关于与许可", func(): about_requested.emit()))
	column.add_child(UIStyle.button("保存并退出游戏", func(): quit_requested.emit()))
	feedback = UIStyle.label("", 16, Color("e5c291"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
