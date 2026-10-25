class_name FlightEffects
extends Control
## Transparent edge warning; the photograph is saved before starting the flash.
var severity := 0
var phase := 0.0
var flash := 0.0
var warning: Label
var shutter_count := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 300
	warning = UIStyle.label("", 22, Color("ffb2a8"))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	warning.offset_top = 96
	warning.add_theme_color_override("font_outline_color", Color("301010"))
	warning.add_theme_constant_override("outline_size", 5)
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(warning)

func update_warning(height: float, cutoff: bool, flying_view: bool) -> void:
	var previous := severity
	severity = (2 if cutoff else 1 if height > FPVDrone.SOFT_ALTITUDE else 0) if flying_view else 0
	if previous != severity: queue_redraw()
	warning.text = "高度保护 · 动力已关闭 · 下降至 280 m 恢复" if severity == 2 else "接近 300 m 限高 · 请降低高度" if severity == 1 else ""

func _process(delta: float) -> void:
	phase = fmod(phase + delta, 1.0)
	var was_active := flash > 0 or severity > 0
	flash = maxf(0, flash - delta / 0.18)
	if was_active or severity > 0: queue_redraw()

func shutter_flash() -> void:
	flash = 1.0
	shutter_count += 1
	queue_redraw()

func edge_opacity() -> float:
	return 0.65 if severity == 2 else (0.12 + 0.42 * (0.5 + 0.5 * sin(phase * TAU * 2))) if severity == 1 else 0.0

func _draw() -> void:
	var opacity := edge_opacity()
	# Idle flight must not submit eighty fully transparent overlay rectangles.
	if opacity <= 0 and flash <= 0: return
	var width := minf(size.x, size.y) * 0.065
	for step in 20:
		var outer := width * step / 20.0
		var inner := width * (step + 1) / 20.0
		var color := Color(1, 0.025, 0.015, opacity * pow(1.0 - step / 20.0, 1.8))
		draw_rect(Rect2(outer, outer, size.x - outer * 2, inner - outer), color)
		draw_rect(Rect2(outer, size.y - inner, size.x - outer * 2, inner - outer), color)
		draw_rect(Rect2(outer, inner, inner - outer, size.y - inner * 2), color)
		draw_rect(Rect2(size.x - inner, inner, inner - outer, size.y - inner * 2), color)
	if flash > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash * 0.8))
