class_name MapCanvas
extends Control

signal location_clicked(id: String)
signal blank_clicked(point: Vector2)
var auto_fit := true

var navigation: MapNavigation
var drone_point := Vector3.ZERO
var heading := Vector2.UP
var biomes: Array[BiomeDefinition] = []
var center_world := Vector2.ZERO
var map_scale := 1.5
var hovered_id := ""
var viewed_id := ""
var dragging := false
var drag_distance := 0.0
var visible_kind := ""
var visible_layer := ""
var fit_right_margin := 0.0
var filter_missions := false
var mission_filter: Dictionary = {}
var mission_states: Dictionary = {}

func mission_color(id: String) -> Color:
	var state: Dictionary = mission_states.get(id, {})
	if state.get("completed", false):
		return Color("91a6c5")
	if state.get("status", "available") == "active":
		return Color("79e2c4")
	return Color("f3c472")

func shows(location: MapLocation) -> bool:
	return (location.kind != "mission" or not filter_missions or mission_filter.has(location.id) or navigation.selected_id == location.id or viewed_id == location.id) and (visible_kind.is_empty() or location.kind == visible_kind) and (location.layer == "temporary" or visible_layer.is_empty() or location.layer == visible_layer)

func _ready() -> void:
	custom_minimum_size = Vector2(680, 440)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	mouse_exited.connect(func(): hovered_id = ""; queue_redraw())
	if auto_fit:
		call_deferred("fit_all")

func project(point: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(point.x, point.z) - center_world) * map_scale

func unproject(point: Vector2) -> Vector2:
	return center_world + (point - size * 0.5) / map_scale

func fit_all() -> void:
	var bounds := Rect2(Vector2(drone_point.x, drone_point.z), Vector2.ONE)
	if not biomes.is_empty():
		var first := true
		for biome in biomes:
			var layer: String = biome.parameters.get("world_layer", "surface")
			if (visible_layer.is_empty() and biome.parameters.layer != "surface") or (not visible_layer.is_empty() and visible_layer != layer):
				continue
			var area := Rect2(Vector2(biome.region_bounds.position.x, biome.region_bounds.position.z), Vector2(biome.region_bounds.size.x, biome.region_bounds.size.z))
			bounds = area if first else bounds.merge(area)
			first = false
	else:
		for location in navigation.locations:
			bounds = bounds.expand(Vector2(location.point.x, location.point.z))
	bounds = bounds.grow(40)
	center_world = bounds.get_center()
	map_scale = clampf(minf(maxf(100, size.x - fit_right_margin) / bounds.size.x, size.y / bounds.size.y), 0.002, 12.0)
	center_world.x += fit_right_margin * 0.5 / map_scale
	queue_redraw()

func zoom_at(cursor: Vector2, factor: float) -> void:
	var before := unproject(cursor)
	map_scale = clampf(map_scale * factor, 0.002, 12.0)
	center_world += before - unproject(cursor)
	queue_redraw()

func hit_test(cursor: Vector2) -> String:
	var nearest := 17.0
	var id := ""
	for location in navigation.locations:
		if not shows(location):
			continue
		var distance := project(location.point).distance_to(cursor)
		if distance < nearest:
			nearest = distance
			id = location.id
	return id

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom_at(event.position, 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom_at(event.position, 1.0 / 1.2)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				dragging = true
				drag_distance = 0.0
			else:
				if dragging and drag_distance < 5.0:
					var id := hit_test(event.position)
					if not id.is_empty():
						location_clicked.emit(id)
					else:
						blank_clicked.emit(unproject(event.position))
					dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			drag_distance += event.relative.length()
			if drag_distance >= 5.0:
				center_world -= event.relative / map_scale
		else:
			dragging = false
		hovered_id = hit_test(event.position)
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("162735"))
	if navigation == null:
		return
	for biome in biomes:
		if biome.parameters.get("layer", "") == "surface" and biome.region_bounds.size.x < 4096:
			if not visible_layer.is_empty() and visible_layer != "surface":
				continue
			var color := biome.palette[1]
			color.a = 0.45
			if biome.parameters.has("map_polygon"):
				var points := PackedVector2Array()
				for point: Vector2 in biome.parameters.map_polygon:
					points.append(project(Vector3(point.x, 0, point.y)))
				draw_colored_polygon(points, color)
				points.append(points[0])
				draw_polyline(points, Color("8da9a377"), 1.5)
			else:
				draw_rect(Rect2(project(biome.region_bounds.position), Vector2(biome.region_bounds.size.x, biome.region_bounds.size.z) * map_scale), color)
		elif biome.parameters.get("layer", "") == "volume":
			var layer: String = biome.parameters.get("world_layer", "")
			if not visible_layer.is_empty() and visible_layer != layer:
				continue
			if layer == "sky":
				for island: Dictionary in biome.parameters.get("map_islands", []):
					draw_arc(project(island.point), float(island.radius) * map_scale, 0, TAU, 28, Color("b8d5ecbb"), 1.5, true)
			elif layer == "maze":
				draw_rect(Rect2(project(biome.region_bounds.position), Vector2(biome.region_bounds.size.x, biome.region_bounds.size.z) * map_scale), Color("c9a5dfaa"), false, 2.0)
				if visible_layer == "maze":
					var walls: PackedVector2Array = biome.parameters.get("map_walls", PackedVector2Array())
					for index in range(0, walls.size(), 2):
						var a := walls[index]
						var b := walls[index + 1]
						draw_line(project(Vector3(a.x, 0, a.y)), project(Vector3(b.x, 0, b.y)), Color("90c0b8"), 1.5)
	var spacing := 64.0 if map_scale >= 0.4 else 512.0
	var start := unproject(Vector2.ZERO)
	var end := unproject(size)
	for x in range(floori(start.x / spacing), ceili(end.x / spacing) + 1):
		var screen_x := project(Vector3(x * spacing, 0, 0)).x
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, size.y), Color("51647250"))
	for z in range(floori(start.y / spacing), ceili(end.y / spacing) + 1):
		var screen_y := project(Vector3(0, 0, z * spacing)).y
		draw_line(Vector2(0, screen_y), Vector2(size.x, screen_y), Color("51647250"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(14, 24), "北 ↑  /  俯视图 · 高度见地点详情", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("c4d8df"))
	draw_line(Vector2(18, size.y - 18), Vector2(18 + 50 * map_scale, size.y - 18), Color.WHITE, 2)
	draw_string(font, Vector2(18, size.y - 26), "50 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var previous := project(drone_point)
	for index in range(navigation.route_index, navigation.route.size()):
		var next := project(navigation.route[index])
		draw_dashed_line(previous, next, Color("ffe095"), 2.0, 8.0)
		draw_arc(next, 5, 0, TAU, 16, Color("ffe095"), 1.5, true)
		previous = next
	var displayed := navigation.locations.duplicate()
	displayed.sort_custom(func(a: MapLocation, b: MapLocation) -> bool: return int(a.kind == "teleport") < int(b.kind == "teleport"))
	for location: MapLocation in displayed:
		if not shows(location):
			continue
		var point := project(location.point)
		var color := mission_color(location.id) if location.kind == "mission" else location.color()
		if location.kind == "teleport" and navigation.teleport_location(location.id) == null:
			color = Color("70818d")
		if location.id == viewed_id or location.id == hovered_id:
			draw_arc(point, 15, 0, TAU, 32, Color("ffe095"), 2.5, true)
		match location.kind:
			"teleport": draw_colored_polygon(PackedVector2Array([point + Vector2(0, -9), point + Vector2(9, 0), point + Vector2(0, 9), point + Vector2(-9, 0)]), color)
			"shop": draw_rect(Rect2(point - Vector2(7, 7), Vector2(14, 14)), color)
			"mission": draw_colored_polygon(PackedVector2Array([point + Vector2(0, -9), point + Vector2(9, 7), point + Vector2(-9, 7)]), color)
			_: draw_circle(point, 7, color)
	# Draw text last so neighbouring icons cannot cover the selected label.
	var label_id := hovered_id if not hovered_id.is_empty() else viewed_id
	var labelled := navigation.find_location(label_id)
	if labelled != null and shows(labelled):
		var text := labelled.display_name + " · %.0f m" % labelled.point.y
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		var pos := project(labelled.point) + Vector2(18, -18)
		pos.x = clampf(pos.x, 8, maxf(8, size.x - width - 12))
		pos.y = clampf(pos.y, 48, size.y - 48)
		draw_rect(Rect2(pos - Vector2(4, 18), Vector2(width + 8, 26)), Color("101c29ed"))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffe095"))
	var player := project(drone_point)
	var forward := heading.normalized() * 12
	var right := Vector2(-forward.y, forward.x) * 0.5
	draw_colored_polygon(PackedVector2Array([player + forward, player - forward * 0.6 + right, player - forward * 0.6 - right]), Color.WHITE)
