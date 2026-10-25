class_name RateCurve
extends Control

const COLORS: Array[Color] = [Color("70d7cb"), Color("edb86b"), Color("b6a1ef")]
var profile := FlightTuning.defaults()
var hover_input := 0.0
var hovering := false

func _ready() -> void:
	custom_minimum_size = Vector2(540, 350)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_exited.connect(func(): hovering = false; queue_redraw())

func set_profile(value: Dictionary) -> void:
	profile = value.duplicate(true)
	queue_redraw()

func sample(input: float) -> Vector3:
	return Vector3(FlightTuning.response(input, profile.axes.roll), FlightTuning.response(input, profile.axes.pitch), FlightTuning.response(input, profile.axes.yaw))

func plot_rect() -> Rect2:
	return Rect2(62, 24, maxf(1, size.x - 86), maxf(1, size.y - 78))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var plot := plot_rect()
		hovering = plot.has_point(event.position)
		hover_input = clampf((event.position.x - plot.position.x) / plot.size.x * 2.0 - 1.0, -1, 1)
		var values := sample(hover_input)
		tooltip_text = "摇杆 %+.0f%%\n横滚 %+.1f °/s\n俯仰 %+.1f °/s\n偏航 %+.1f °/s" % [hover_input * 100, values.x, values.y, values.z]
		queue_redraw()

func _draw() -> void:
	var plot := plot_rect()
	var font := ThemeDB.fallback_font
	var y_limit := 100.0
	for axis in FlightTuning.AXES:
		y_limit = maxf(y_limit, ceilf(float(profile.axes[axis].max_rate_dps) / 100.0) * 100.0)
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for index in 5:
		var fraction := index / 4.0
		var y := plot.position.y + plot.size.y * fraction
		var x := plot.position.x + plot.size.x * fraction
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color("38505d"), 1)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("38505d"), 1)
		draw_string(font, Vector2(4, y + 5), "%+.0f" % (y_limit * (1.0 - fraction * 2.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("afc6ce"))
		draw_string(font, Vector2(x - 18, plot.end.y + 22), "%+.0f" % (fraction * 200 - 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("afc6ce"))
	draw_string(font, Vector2(8, 16), "deg/s", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("afc6ce"))
	draw_string(font, Vector2(plot.end.x - 62, size.y - 6), "stick %", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("afc6ce"))
	for index in 3:
		var points := PackedVector2Array()
		for step in 201:
			var x := step / 100.0 - 1.0
			var y := FlightTuning.response(x, profile.axes[FlightTuning.AXES[index]])
			points.append(Vector2(plot.position.x + (x + 1) * 0.5 * plot.size.x, plot.get_center().y - y / y_limit * plot.size.y * 0.5))
		draw_polyline(points, COLORS[index], 2.5, true)
	if hovering:
		var x := plot.position.x + (hover_input + 1) * 0.5 * plot.size.x
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color("ffffff80"), 1)
		var values := sample(hover_input)
		for index in 3:
			draw_circle(Vector2(x, plot.get_center().y - values[index] / y_limit * plot.size.y * 0.5), 4, COLORS[index])

func _background() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("101b27")
	box.set_corner_radius_all(8)
	return box
