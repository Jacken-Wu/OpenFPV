class_name DeveloperConsole
extends PanelContainer
signal submitted(command: String)
var output: RichTextLabel
var entry: LineEdit
var history: Array[String] = []
var history_index := 0

func _ready() -> void:
	theme = UIStyle.theme()
	custom_minimum_size = Vector2(960, 480)
	var column := UIStyle.column(self)
	column.add_child(UIStyle.label("开发控制台   /   Esc 返回飞行", 25, Color("70d7cb")))
	output = RichTextLabel.new()
	output.custom_minimum_size = Vector2(900, 310)
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.scroll_following = true
	output.selection_enabled = true
	output.bbcode_enabled = false
	column.add_child(output)
	entry = LineEdit.new()
	entry.placeholder_text = "/help 查看指令；↑ / ↓ 历史；Enter 执行"
	entry.text = "/"
	column.add_child(entry)
	entry.text_submitted.connect(_submit)
	entry.gui_input.connect(_entry_input)
	column.add_child(UIStyle.label("定位不解锁地图或传送点；/tp 为开发调试传送。", 16, Color("e5c291")))
	write("/help  帮助    /location list  群系列表    /pos  坐标    /seed  种子\n/location <群系名称或 ID>  最近群系定位    /tp <x> <y> <z> 或 /tp location\n/volume <0~100>  音量    /clear  清屏")
	entry.grab_focus.call_deferred()
	entry.set_caret_column.call_deferred(1)

func write(message: String) -> void:
	output.append_text(message + "\n")
	# Keep long developer sessions bounded.
	if output.get_line_count() > 300:
		output.clear()
		output.append_text("…较早输出已清除…\n" + message + "\n")

func _submit(command: String) -> void:
	if command.strip_edges().is_empty() or command.strip_edges() == "/":
		return
	history.append(command)
	if history.size() > 100:
		history.pop_front()
	history_index = history.size()
	write("> " + command)
	entry.clear()
	submitted.emit(command)

func _entry_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode in [KEY_UP, KEY_DOWN]:
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else ""
		entry.caret_column = entry.text.length()
		entry.accept_event()
