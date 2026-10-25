class_name RegionMap
extends PanelContainer
## One selection model drives the task list, map highlight and floating details.
signal teleport_requested(id: String)
signal closed
signal accept_requested(id: String)
signal track_requested(id: String)
var navigation: MapNavigation
var controller: MissionController
var drone_point := Vector3.ZERO
var heading := Vector2.UP
var biomes: Array[BiomeDefinition] = []
var region_key := Vector2i.ZERO
var birth_region := Vector2i.ZERO
var open_tasks := false
var map_canvas: MapCanvas
var details: Label
var detail: Label
var teleport_button: Button
var accept_button: Button
var track_button: Button
var message: Label
var layers: OptionButton
var task_filter: OptionButton
var task_sidebar: VBoxContainer
var task_scroll: ScrollContainer
var task_list: VBoxContainer
var task_count: Label
var collapse_button: Button
var info_panel: PanelContainer
var rows: Dictionary = {}
var location_buttons: Dictionary = {}
var ordered: Array[MissionDefinition] = []
var selected_id := ""
var viewed_id := ""
var task_page := 0
const PAGE_SIZE := 8

func _ready() -> void:
	custom_minimum_size = Vector2(1190, 0)
	var column := UIStyle.column(self, 10)
	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(UIStyle.label("探索地图 / 委托", 25, Color("f0c485")))
	collapse_button = UIStyle.button("◀ 收起任务", func():
		task_sidebar.visible = not task_sidebar.visible
		collapse_button.text = "◀ 收起任务" if task_sidebar.visible else "▶ 展开任务")
	header.add_child(collapse_button)
	header.add_child(UIStyle.button("定位无人机", func(): map_canvas.center_world = Vector2(drone_point.x, drone_point.z); map_canvas.queue_redraw()))
	header.add_child(UIStyle.button("全部已解锁", func(): map_canvas.fit_all()))
	layers = OptionButton.new()
	for title: String in ["全部高度层", "地表群系", "浮岛群", "地下迷宫"]:
		layers.add_item(title)
	header.add_child(layers)
	layers.item_selected.connect(func(index: int):
		map_canvas.visible_layer = ["", "surface", "sky", "maze"][index]
		task_page = 0
		_rebuild_list()
		map_canvas.fit_all())
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	task_sidebar = UIStyle.column(body, 7)
	task_sidebar.custom_minimum_size.x = 265
	task_sidebar.add_child(UIStyle.label("探索委托 · 按实际距离排序", 16))
	task_filter = OptionButton.new()
	for title: String in ["附近未完成 / 1.5 km", "进行中", "全部已发现", "已完成（含重玩）", "全部未完成"]:
		task_filter.add_item(title)
	task_sidebar.add_child(task_filter)
	task_filter.item_selected.connect(func(_index: int): task_page = 0; _rebuild_list())
	task_count = UIStyle.label("", 14)
	task_sidebar.add_child(task_count)
	task_scroll = ScrollContainer.new()
	task_scroll.custom_minimum_size = Vector2(265, 420)
	task_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_sidebar.add_child(task_scroll)
	task_list = UIStyle.column(task_scroll, 6)
	task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pages := HBoxContainer.new()
	task_sidebar.add_child(pages)
	pages.add_child(UIStyle.button("上一页", func(): task_page = maxi(0, task_page - 1); _rebuild_list()))
	pages.add_child(UIStyle.button("下一页", func(): task_page = mini(maxi(0, (ordered.size() - 1) / PAGE_SIZE), task_page + 1); _rebuild_list()))
	var map_stack := Control.new()
	map_stack.custom_minimum_size = Vector2(680, 530)
	map_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(map_stack)
	map_canvas = MapCanvas.new()
	map_canvas.auto_fit = false
	map_canvas.navigation = navigation
	map_canvas.biomes = biomes
	map_canvas.drone_point = drone_point
	map_canvas.heading = heading
	map_stack.add_child(map_canvas)
	map_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_canvas.location_clicked.connect(_select)
	map_canvas.blank_clicked.connect(_place_waypoint)
	info_panel = PanelContainer.new()
	map_stack.add_child(info_panel)
	info_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -282
	info_panel.offset_right = -12
	info_panel.offset_top = 12
	info_panel.offset_bottom = 420
	var info := UIStyle.column(info_panel, 10)
	info.add_child(UIStyle.label("选中地点", 19, Color("f0c485")))
	details = UIStyle.label("", 16)
	details.custom_minimum_size = Vector2(220, 0)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(220, 255)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.add_child(detail_scroll)
	detail_scroll.add_child(details)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail = details
	accept_button = UIStyle.button("领取并追踪", func(): accept_requested.emit(selected_id))
	track_button = UIStyle.button("追踪", _track_viewed)
	teleport_button = UIStyle.button("传送到此平台", func():
		if navigation.teleport_location(viewed_id) != null:
			teleport_requested.emit(viewed_id))
	info.add_child(accept_button)
	info.add_child(track_button)
	info.add_child(teleport_button)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	footer.add_child(UIStyle.button("＋", func(): map_canvas.zoom_at(map_canvas.size * 0.5, 1.4)))
	footer.add_child(UIStyle.button("－", func(): map_canvas.zoom_at(map_canvas.size * 0.5, 1.0 / 1.4)))
	footer.add_child(UIStyle.button("清除指引", navigation.clear))
	footer.add_child(UIStyle.button("停止追踪", func(): track_requested.emit("")))
	footer.add_child(UIStyle.button("返回飞行", func(): closed.emit()))
	message = UIStyle.label("△ 金色未完成 / 绿色进行中 / 蓝灰已完成 · ◇ 平台（灰色未登记） · 落稳按 E 登记传送", 14, Color("9eb6bd"))
	column.add_child(message)
	navigation.changed.connect(_refresh)
	viewed_id = navigation.selected_id
	_rebuild_list()
	if open_tasks:
		if not ordered.is_empty():
			_select(ordered[0].location_id)
	_refresh()
	call_deferred("_initial_view")

func _initial_view() -> void:
	# Opening always uses the same physical scale, independent of exploration size.
	map_canvas.map_scale = 0.7
	map_canvas.center_world = Vector2(drone_point.x, drone_point.z)
	map_canvas.queue_redraw()

func _mission(id: String) -> MissionDefinition:
	if controller == null:
		return null
	for mission: MissionDefinition in controller.definitions():
		if mission.location_id == id:
			return mission
	return null

func _rebuild_list() -> void:
	for child in task_list.get_children():
		task_list.remove_child(child)
		child.queue_free()
	rows.clear()
	location_buttons.clear()
	ordered.clear()
	if controller == null:
		return
	map_canvas.mission_states.clear()
	for mission: MissionDefinition in controller.definitions():
		var completed := controller.store.mission_completed_once(mission.id)
		map_canvas.mission_states[mission.location_id] = {"completed": completed, "status": controller.store.mission_status(mission.id)}
		var location := navigation.find_location(mission.location_id)
		if location == null or (not map_canvas.visible_layer.is_empty() and location.layer != map_canvas.visible_layer):
			continue
		var status := controller.store.mission_status(mission.id)
		var distance := drone_point.distance_to(controller.objective_point(mission))
		if task_filter.selected == 0 and (completed or distance > 1500):
			continue
		if task_filter.selected == 1 and status != "active":
			continue
		if task_filter.selected == 3 and not completed:
			continue
		if task_filter.selected == 4 and completed:
			continue
		ordered.append(mission)
	ordered.sort_custom(func(a: MissionDefinition, b: MissionDefinition) -> bool:
		var da := drone_point.distance_squared_to(controller.objective_point(a))
		var db := drone_point.distance_squared_to(controller.objective_point(b))
		return da < db if not is_equal_approx(da, db) else a.id < b.id)
	task_page = clampi(task_page, 0, maxi(0, (ordered.size() - 1) / PAGE_SIZE))
	task_count.text = "%d 项 · 每页最多8项 · %d / %d页" % [ordered.size(), task_page + 1, maxi(1, ceili(ordered.size() / 8.0))]
	map_canvas.mission_filter.clear()
	map_canvas.filter_missions = true
	for index in range(task_page * PAGE_SIZE, mini(ordered.size(), (task_page + 1) * PAGE_SIZE)):
		var mission := ordered[index]
		var id := mission.id
		var button := UIStyle.button("", func(): _select(mission.location_id))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(260, 0)
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 14)
		task_list.add_child(button)
		rows[id] = button
		location_buttons[mission.location_id] = button
		map_canvas.mission_filter[mission.location_id] = true
	if ordered.is_empty():
		task_list.add_child(UIStyle.label("此筛选下暂无任务\n继续探索，或切换任务筛选。", 15))
	_refresh()

func _select(id: String) -> void:
	var mission := _mission(id)
	if mission != null:
		# A map click always reveals the corresponding row, even outside current filter/page.
		var found := false
		for candidate in ordered:
			found = found or candidate.id == mission.id
		if not found:
			task_filter.select(2)
			_rebuild_list()
		for index in ordered.size():
			if ordered[index].id == mission.id:
				task_page = index / PAGE_SIZE
				break
		_rebuild_list()
	viewed_id = id
	_refresh()
	var location := navigation.find_location(viewed_id)
	if location != null:
		var projected := map_canvas.project(location.point)
		if not Rect2(Vector2(15, 35), map_canvas.size - Vector2(315, 50)).has_point(projected):
			map_canvas.center_world = Vector2(location.point.x, location.point.z) + Vector2(130 / map_canvas.map_scale, 0)
	if mission != null and rows.has(mission.id):
		task_scroll.ensure_control_visible(rows[mission.id])

func _refresh() -> void:
	if map_canvas == null:
		return
	var location := navigation.find_location(viewed_id)
	var mission := _mission(viewed_id)
	map_canvas.viewed_id = viewed_id
	selected_id = mission.id if mission != null else ""
	info_panel.visible = location != null
	map_canvas.fit_right_margin = 300 if info_panel.visible else 0
	teleport_button.visible = location != null and location.kind == "teleport"
	teleport_button.disabled = navigation.teleport_location(viewed_id) == null
	accept_button.visible = mission != null
	track_button.visible = location != null
	accept_button.disabled = mission == null or controller.store.mission_status(mission.id) == "active"
	accept_button.text = "再次接取并追踪" if mission != null and controller.store.mission_status(mission.id) == "completed" else "重试并追踪" if mission != null and controller.store.mission_status(mission.id) == "failed" else "领取并追踪"
	track_button.disabled = location == null
	track_button.text = "正在追踪" if navigation.selected_id == viewed_id and location != null else "追踪"
	for id: String in rows:
		var item := controller.store.mission_definition(id)
		var target := controller.objective_point(item)
		var status: String = {"available": "可领取", "active": "进行中", "completed": "已完成", "failed": "超高失败 · 可重试"}[controller.store.mission_status(id)]
		if controller.store.mission_completed_once(id) and controller.store.mission_status(id) != "completed":
			status = "已完成 · 重玩中" if controller.store.mission_status(id) == "active" else "已完成 · 可重玩"
		var layer: String = {"surface": "地表", "sky": "浮岛", "maze": "地下"}.get(navigation.find_location(item.location_id).layer, "")
		rows[id].text = ("▶ " if id == selected_id else "") + item.display_name.get_slice(" · ", 0) + " · " + status + "\n%.0f m · %s · 高度差 %+.0f m" % [drone_point.distance_to(target), layer, target.y - drone_point.y]
		rows[id].tooltip_text = item.display_name
		var color := map_canvas.mission_color(item.location_id)
		for name_text: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			rows[id].add_theme_color_override(name_text, color)
	if location == null:
		details.text = "选中后查看地点信息。"
	else:
		details.text = "%s\n%.0f m · 高度差 %+.0f m\n坐标 %.0f, %.0f, %.0f\n\n%s" % [location.display_name, drone_point.distance_to(location.point), location.point.y - drone_point.y, location.point.x, location.point.y, location.point.z, location.description]
		if mission != null:
			var status: String = {"available": "可领取", "active": "进行中", "completed": "已完成 · 奖励已发放", "failed": "气球超过限高 · 可重新挑战"}[controller.store.mission_status(mission.id)]
			var target := controller.objective_point(mission)
			details.text = "%s\n%s · 距离 %.0f m\n高度差 %+.0f m\n坐标 %.0f, %.0f, %.0f\n\n%s\n\n%s" % [mission.display_name, status, drone_point.distance_to(target), target.y - drone_point.y, target.x, target.y, target.z, mission.description, controller.store.mission_reward_text(mission.id)]
			if controller.exploration != null and controller.store.regions is BiomeWorld:
				var p: Dictionary = controller.store.regions.instance(location.structure_id)
				if controller.store.regions.map_task(p) == mission.id:
					details.text += "\n\n地图已解锁。" if controller.store.data.exploration.mapped.has(location.structure_id) else "\n\n测绘任务：完成后解锁本地区地图。"
		elif location.kind == "teleport":
			var repair := controller.store.portal_repair_status(location.id)
			if repair.remaining > 0:
				details.text += "\n\n传送网络离线 · 线路修复 %d/%d\n完成全部修复线路后，恢复传送并开放此平台的服务页面。" % [repair.total - repair.remaining, repair.total]
			else:
				details.text += "\n\n已登记 · 可以传送" if not teleport_button.disabled else "\n\n尚未登记 · 飞抵平台，落稳后按 E 解锁传送。"
	map_canvas.queue_redraw()

func _track_viewed() -> void:
	var mission := _mission(viewed_id)
	if mission != null and controller.store.mission_status(mission.id) == "active":
		track_requested.emit(mission.id)
	elif navigation.find_location(viewed_id) != null:
		navigation.select(viewed_id, drone_point)
		message.text = "已追踪所选地点"

func refresh() -> void:
	_rebuild_list()

func _exit_tree() -> void:
	if navigation != null and navigation.changed.is_connected(_refresh):
		navigation.changed.disconnect(_refresh)

func _place_waypoint(point: Vector2) -> void:
	var target := Vector3(point.x, drone_point.y, point.y)
	navigation.place_temporary(target, drone_point, false)
	viewed_id = "temporary"
	_refresh()
	message.text = "已选中临时路标 · 点击追踪后开始指引 · 使用当前高度"
