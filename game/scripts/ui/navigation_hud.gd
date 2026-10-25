class_name NavigationHUD
extends Control
## Screen-space waypoint highlight, with an edge arrow when outside the view.

var navigation: MapNavigation
var camera: Camera3D
var origin_offset := Vector3.ZERO
var drone_point := Vector3.ZERO
var avoid_controls: Array[Control] = []
var bottom_panel: Control
var label_anchor := "below"
var label_target := ""

func marker_state(target: Vector3) -> Dictionary:
	if not target.is_finite() or not size.is_finite() or size.x <= 0 or size.y <= 0:
		return {"valid": false}
	var local := camera.global_basis.inverse() * (target - camera.global_position)
	if not local.is_finite(): return {"valid": false}
	var behind := camera.is_position_behind(target)
	var near_plane := absf(local.z) < 0.0001
	var screen := camera.unproject_position(target) if not behind and not near_plane else Vector2(-10000, -10000)
	var offscreen := behind or near_plane or not screen.is_finite() or not Rect2(Vector2.ZERO, size).has_point(screen)
	var direction := Vector2.ZERO
	if offscreen:
		# Edge direction must not divide by depth at the camera plane. A target
		# sweeping through z=0 must never send NaN/Inf vertices to the canvas.
		var projection := camera.get_camera_projection()
		direction = Vector2(local.x * projection.x.x * size.x, -local.y * projection.y.y * size.y)
		if not direction.is_finite(): return {"valid": false}
		if direction.length_squared() < 0.001: direction = Vector2.DOWN
		direction = direction.normalized()
		var half := (size * 0.5 - Vector2.ONE * 20).max(Vector2.ONE)
		var reach := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
		screen = size * 0.5 + direction * reach
	return {"valid": screen.is_finite(), "point": screen, "offscreen": offscreen, "direction": direction}

func label_rect(screen: Vector2, extent: Vector2) -> Rect2:
	var target := navigation.selected_id if navigation != null else ""
	if target != label_target:
		label_target = target
		label_anchor = "below"
	var blockers: Array[Rect2] = [Rect2(size * 0.5 - Vector2.ONE * 34, Vector2.ONE * 68), Rect2(screen - Vector2.ONE * 21, Vector2.ONE * 42)]
	var blocker_ids: Array[String] = ["reticle", "marker"]
	for control in avoid_controls:
		if is_instance_valid(control) and control.is_visible_in_tree():
			blockers.append(control.get_global_rect().grow(8))
			blocker_ids.append(str(control.get_instance_id()))
	# A bottom-edge arrow belongs just above the information bar, not beside it.
	if is_instance_valid(bottom_panel) and bottom_panel.is_visible_in_tree():
		var bottom := bottom_panel.get_global_rect()
		if screen.y >= bottom.position.y + 10:
			return Rect2(Vector2(clampf(screen.x - extent.x * 0.5, 14, size.x - extent.x - 14), bottom.position.y - extent.y - 12), extent)
	var candidates := {"below": screen + Vector2(-extent.x * 0.5, 28), "right": screen + Vector2(28, -20), "left": screen - Vector2(extent.x + 28, 20), "above": screen - Vector2(extent.x * 0.5, extent.y + 24)}
	for index in blockers.size():
		var blocker := blockers[index]
		candidates["under" + blocker_ids[index]] = Vector2(screen.x - extent.x * 0.5, blocker.end.y + 10)
		candidates["over" + blocker_ids[index]] = Vector2(screen.x - extent.x * 0.5, blocker.position.y - extent.y - 10)
		candidates["right" + blocker_ids[index]] = Vector2(blocker.end.x + 10, screen.y - extent.y * 0.5)
		candidates["left" + blocker_ids[index]] = Vector2(blocker.position.x - extent.x - 10, screen.y - extent.y * 0.5)
	var best := Rect2()
	var score := INF
	var best_anchor := label_anchor
	for anchor: String in candidates:
		var point: Vector2 = candidates[anchor]
		point = point.clamp(Vector2.ONE * 14, (size - extent - Vector2.ONE * 14).max(Vector2.ONE * 14))
		var candidate := Rect2(point, extent)
		var value := candidate.get_center().distance_squared_to(screen)
		var clear := true
		for blocker in blockers:
			if blocker.intersects(candidate):
				clear = false
				value += blocker.intersection(candidate).get_area() * 10000
		# Keep the established side while it remains clear. Small score changes
		# from camera motion or a changing distance digit must not flip the label.
		if anchor == label_anchor and clear: return candidate
		if value < score: best = candidate; score = value; best_anchor = anchor
	label_anchor = best_anchor
	return best

func next_turn() -> String:
	if not navigation.corridor_route or navigation.route_index + 1 >= navigation.route.size(): return ""
	var a := navigation.waypoint() - drone_point
	var b := navigation.route[navigation.route_index + 1] - navigation.waypoint()
	if absf(b.y) > 6 and Vector2(b.x, b.z).length() < 6: return "随后上升" if b.y > 0 else "随后下降"
	a.y = 0
	b.y = 0
	if a.length() < 1 or b.length() < 1: return ""
	if a.normalized().dot(b.normalized()) > 0.8: return "随后直行"
	if a.normalized().dot(b.normalized()) < -0.5: return "随后回转"
	return "随后左转" if a.cross(b).y > 0 else "随后右转"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if navigation == null or navigation.selected() == null or not is_instance_valid(camera):
		return
	var location := navigation.selected()
	var target := navigation.waypoint() - origin_offset
	var state := marker_state(target)
	if not state.valid: return
	var screen: Vector2 = state.point
	var offscreen: bool = state.offscreen
	if offscreen:
		var direction: Vector2 = state.direction
		var side := Vector2(-direction.y, direction.x)
		draw_colored_polygon(PackedVector2Array([screen + direction * 12, screen - direction * 8 + side * 8, screen - direction * 8 - side * 8]), Color("ffe095"))
	else:
		draw_arc(screen, 13, 0, TAU, 32, Color("102030"), 5.5, true)
		draw_arc(screen, 13, 0, TAU, 32, Color("ffe095"), 2.5, true)
		draw_circle(screen, 3, Color("ffe095"))
	var name := location.display_name.get_slice(" · ", 0).get_slice(" / ", 0)
	if name.length() > 12:
		name = name.left(11) + "…"
	var step := " %d/%d" % [navigation.route_index + 1, navigation.route.size()] if navigation.route.size() > 1 else ""
	var text := name + step + ((" · 目标附近" if location.kind == "mission" else " · 到达") if navigation.arrived else "")
	var info := "%.0fm  %+.0fm" % [navigation.remaining_distance(drone_point), navigation.waypoint().y - drone_point.y]
	var turn := next_turn()
	if not turn.is_empty(): info += " · " + turn
	var font := ThemeDB.fallback_font
	var width := maxf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, font.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	var box := label_rect(screen, Vector2(width + 12, 44))
	var pos := box.position + Vector2(6, 17)
	if box.get_center().distance_to(screen) > 60:
		draw_line(screen, screen.clamp(box.position, box.end), Color(1, 0.87, 0.55, 0.45), 1, true)
	draw_rect(box, Color(0.03, 0.07, 0.1, 0.65))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("ffe095"))
	draw_string(font, pos + Vector2(0, 18), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("d6e3e6"))
