class_name MissionBoard
extends PanelContainer

signal accept_requested(id: String)
signal track_requested(id: String)
signal map_requested(id: String)
signal closed

var controller: MissionController
var selected_id := ""
var list: VBoxContainer
var detail: Label
var accept_button: Button
var track_button: Button
var map_button: Button
var message: Label
var rows: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(980, 0)
	var column := UIStyle.column(self, 16)
	column.add_child(UIStyle.label("探索委托  /  任务面板", 27, Color("f0c485")))
	column.add_child(UIStyle.label("领取后开启地图指引 · 无倒计时 · 完成时自动保存并发放一次性奖励", 17))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(350, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	list = UIStyle.column(scroll, 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail = UIStyle.label("", 18)
	detail.custom_minimum_size = Vector2(570, 360)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	for mission: MissionDefinition in controller.definitions():
		var id := mission.id
		var button := UIStyle.button(mission.display_name, func(): selected_id = id; refresh())
		list.add_child(button)
		button.add_theme_font_size_override("font_size", 14)
		button.clip_text = true
		rows[id] = button
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	accept_button = UIStyle.button("领取并追踪", func(): accept_requested.emit(selected_id))
	track_button = UIStyle.button("追踪任务", func(): track_requested.emit(selected_id))
	map_button = UIStyle.button("在地图查看", func(): map_requested.emit(selected_id))
	actions.add_child(accept_button)
	actions.add_child(track_button)
	actions.add_child(map_button)
	actions.add_child(UIStyle.button("停止追踪", func(): track_requested.emit("")))
	actions.add_child(UIStyle.button("返回飞行", func(): closed.emit()))
	message = UIStyle.label("", 16, Color("f0c485"))
	message.custom_minimum_size = Vector2(900, 48)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	if selected_id.is_empty():
		var current := controller.tracked()
		selected_id = current.id if current != null else controller.definitions()[0].id if not controller.definitions().is_empty() else ""
	refresh()

func refresh() -> void:
	for id: String in rows:
		var status := controller.store.mission_status(id)
		var state: String = {"available": "可领取", "active": "进行中", "completed": "已完成", "failed": "超高失败 · 可重试"}[status]
		rows[id].text = ("▶ " if id == selected_id else "") + controller.store.mission_definition(id).display_name + " · " + state
	var mission := controller.store.mission_definition(selected_id)
	accept_button.disabled = mission == null or controller.store.mission_status(selected_id) == "active"
	accept_button.text = "再次接取并追踪" if mission != null and controller.store.mission_status(selected_id) == "completed" else "领取并追踪"
	track_button.disabled = mission == null or controller.store.mission_status(selected_id) != "active"
	map_button.disabled = mission == null
	if mission == null:
		detail.text = "请选择任务。"
		return
	var status := controller.store.mission_status(selected_id)
	var status_text: String = {"available": "可领取", "active": "进行中", "completed": "已完成 · 奖励已发放", "failed": "气球超过限高 · 可重新挑战"}[status]
	detail.text = "%s\n%s%s\n\n%s\n\n%s" % [mission.display_name, status_text, " · 正在追踪" if controller.store.data.tracked_mission == mission.id else "", mission.description, controller.store.mission_reward_text(mission.id)]
	var photo_path: String = controller.store.data.assignments.get(selected_id, {}).get("photo_path", "")
	if not photo_path.is_empty():
		detail.text += "\n已保存完成照片；F12 普通拍照仍可继续。"
