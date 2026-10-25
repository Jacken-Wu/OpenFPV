class_name SaveMenu
extends PanelContainer
signal closed
signal activated(store: ProgressStore, message: String)
var library: SaveLibrary
var current: ProgressStore
var list: ItemList
var name_field: LineEdit
var seed_field: SpinBox
var feedback: Label
var rows: Array[Dictionary] = []
var selected_id := ""
var load_button: Button
var delete_button: Button
var rename_button: Button
var confirm_id := ""

func _ready() -> void:
	theme = UIStyle.theme()
	z_index = 250
	custom_minimum_size = Vector2(1010, 730)
	var column := UIStyle.column(self, 10)
	column.add_child(UIStyle.label("存档管理", 28, Color("70d7cb")))
	column.add_child(UIStyle.label("自动保存任务与取得记录；读取世界回到最近安全平台。遥控器/操控设置随玩家保留。", 16))
	list = ItemList.new()
	list.custom_minimum_size = Vector2(950, 260)
	column.add_child(list)
	list.item_selected.connect(_select)
	list.item_activated.connect(func(index: int): _select(index); load_selected())
	var names := HBoxContainer.new()
	column.add_child(names)
	names.add_child(UIStyle.label("存档名称", 17))
	name_field = LineEdit.new()
	name_field.max_length = 48
	name_field.placeholder_text = "输入名称，用于改名、另存或新建"
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(name_field)
	var seeds := HBoxContainer.new()
	column.add_child(seeds)
	seeds.add_child(UIStyle.label("新世界种子", 17))
	seed_field = SpinBox.new()
	seed_field.min_value = -2147483648
	seed_field.max_value = 2147483647
	seed_field.step = 1
	seed_field.value = int(current.data.seed)
	seed_field.custom_minimum_size.x = 260
	seeds.add_child(seed_field)
	var primary := HBoxContainer.new()
	column.add_child(primary)
	primary.add_child(UIStyle.button("保存当前进度", func(): _report(library.save(current))))
	primary.add_child(UIStyle.button("当前世界另存副本", func(): _report(library.duplicate_current(current, name_field.text))))
	primary.add_child(UIStyle.button("新建并进入世界", new_world))
	var actions := HBoxContainer.new()
	column.add_child(actions)
	load_button = UIStyle.button("读取选中存档", load_selected)
	actions.add_child(load_button)
	rename_button = UIStyle.button("修改选中名称", func(): _report(library.rename_slot(selected_id, name_field.text, current)))
	actions.add_child(rename_button)
	delete_button = UIStyle.button("删除选中存档…", delete_selected)
	actions.add_child(delete_button)
	feedback = UIStyle.label("", 17, Color("e5c291"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size = Vector2(920, 58)
	column.add_child(feedback)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	bottom.add_child(UIStyle.button("打开存档目录", func(): OS.shell_open(ProjectSettings.globalize_path(library.root))))
	bottom.add_child(UIStyle.button("返回暂停菜单", func(): closed.emit()))
	refresh()

func refresh() -> void:
	rows = library.entries(current.path)
	list.clear()
	var selected := -1
	for index in rows.size():
		var row := rows[index]
		list.add_item("%s%s  ·  种子 %d  ·  %d 信用点  ·  %s%s" % ["[当前] " if row.active else "", row.name, row.seed, row.credits, row.updated, "  [备份恢复]" if row.backup and row.valid else "  [损坏]" if not row.valid else "  [版本不兼容]" if not row.compatible else ""])
		if row.id == selected_id or (selected_id.is_empty() and row.active):
			selected = index
	if selected >= 0:
		list.select(selected)
		_select(selected)
	else:
		selected_id = ""
		load_button.disabled = true
		delete_button.disabled = true
		rename_button.disabled = true

func _select(index: int) -> void:
	var row := rows[index]
	selected_id = row.id
	name_field.text = row.name
	load_button.disabled = row.active or not row.valid or not row.compatible
	delete_button.disabled = row.active
	rename_button.disabled = not row.valid
	confirm_id = ""
	delete_button.text = "删除选中存档…"

func _report(result: Dictionary) -> void:
	feedback.text = result.get("message", "已保存")
	refresh()

func new_world() -> void:
	if seed_field.get_line_edit().has_focus():
		seed_field.apply()
	var result := library.new_world(current, name_field.text, int(seed_field.value))
	if result.ok:
		activated.emit(result.store, result.message)
	else:
		_report(result)

func load_selected() -> void:
	if load_button.disabled:
		return
	var result := library.load_slot(selected_id, current)
	if result.ok:
		activated.emit(result.store, result.message)
	else:
		_report(result)

func delete_selected() -> void:
	if delete_button.disabled:
		return
	if confirm_id != selected_id:
		confirm_id = selected_id
		delete_button.text = "确认移入回收目录"
		feedback.text = "再次点击确认删除选中存档。文件会保留在trash目录；当前世界不能删除。"
		return
	_report(library.delete_slot(selected_id, current))
