class_name MapNavigation
extends RefCounted

signal changed

var locations: Array[MapLocation] = []
var selected_id := ""
var route: PackedVector3Array = []
var route_index := 0
var arrived := false
var route_resolver: Callable
var teleport_resolver: Callable
var previous_point := Vector3.ZERO
var has_previous := false
var corridor_route := false
var route_start := Vector3.ZERO
var rescue_origin := Vector3.ZERO

func _init(world_version: int = 2) -> void:
	if world_version >= 3:
		return
	var file := FileAccess.open("res://content/base/map_locations.json", FileAccess.READ)
	var records: Variant = JSON.parse_string(file.get_as_text()) if file else null
	if not records is Array:
		push_error("Map locations must be an array")
		return
	for record: Dictionary in records:
		if int(record.get("min_world_version", 1)) > world_version:
			continue
		var location := MapLocation.new()
		location.id = record.id
		location.display_name = record.name
		location.kind = record.kind
		location.point = Vector3(record.point[0], record.point[1], record.point[2])
		location.description = record.description
		if record.has("interior_bounds"):
			var bounds: Array = record.interior_bounds
			location.interior_bounds = AABB(Vector3(bounds[0], bounds[1], bounds[2]), Vector3(bounds[3], bounds[4], bounds[5]))
		for point: Array in record.get("approach", []):
			location.approach.append(Vector3(point[0], point[1], point[2]))
		locations.append(location)

func find_location(id: String) -> MapLocation:
	for location in locations:
		if location.id == id:
			return location
	return null

func selected() -> MapLocation:
	return find_location(selected_id)

func teleport_location(id: String) -> MapLocation:
	var location := find_location(id)
	return location if location != null and location.kind == "teleport" and (not teleport_resolver.is_valid() or teleport_resolver.call(id)) else null

func nearest_teleport(point: Vector3) -> MapLocation:
	var nearest: MapLocation
	for location in locations:
		if location.kind == "teleport" and (nearest == null or point.distance_squared_to(location.point) < point.distance_squared_to(nearest.point)):
			nearest = location
	return nearest

func select(id: String, from: Vector3) -> bool:
	var location := find_location(id)
	if location == null:
		return false
	if location.layer == "temporary":
		locations = locations.filter(func(item: MapLocation): return item.layer != "temporary" or item.id == id)
	selected_id = id
	rebuild_route(from)
	changed.emit()
	return true

func rebuild_route(from: Vector3) -> void:
	route_start = from
	rescue_origin = from
	has_previous = false
	previous_point = from
	route.clear()
	route_index = 0
	arrived = false
	var location := selected()
	if location == null:
		return
	corridor_route = location.layer == "maze"
	if location.layer == "temporary":
		route.append(location.point)
		update(from)
		return
	if route_resolver.is_valid():
		route = route_resolver.call(from, location)
		corridor_route = corridor_route or (from.y < 0 and route.size() > 1)
		update(from)
		return
	# Underground approach points lead through the opening, in either direction.
	# Skip the entrance only when already in the same authored underground chamber.
	var source_interior: MapLocation
	for candidate in locations:
		if candidate.interior_bounds.has_volume() and candidate.interior_bounds.has_point(from):
			source_interior = candidate
			break
	var same_interior := source_interior != null and source_interior.interior_bounds.has_point(location.point)
	corridor_route = corridor_route or source_interior != null
	if source_interior != null and not same_interior:
		for index in range(source_interior.approach.size() - 1, -1, -1):
			route.append(source_interior.approach[index])
	if not same_interior:
		route.append_array(location.approach)
	route.append(location.point)
	update(from)

func clear() -> void:
	selected_id = ""
	locations = locations.filter(func(item: MapLocation): return item.layer != "temporary")
	has_previous = false
	route.clear()
	route_index = 0
	arrived = false
	changed.emit()

func update(from: Vector3) -> void:
	if route.is_empty():
		previous_point = from
		has_previous = true
		return
	# Use the swept motion segment so a frame can cross a waypoint without landing
	# inside its radius. Do not sweep teleport/redeploy jumps or bridge maze walls.
	var continuous := has_previous and previous_point.distance_to(from) <= 64
	var start := previous_point if continuous else from
	# Guidance points are not mandatory mission checkpoints. Once flying along a
	# following leg, show its destination instead of requiring a return to the corner.
	if continuous:
		_following_leg(from)
		if corridor_route and route_index < route.size() - 1 and route_resolver.is_valid() and selected() != null:
			var distance := from.distance_to(waypoint())
			var moving_away := (from - previous_point).dot(from - waypoint()) > 0.0001
			if distance > 12 and moving_away and from.distance_to(rescue_origin) >= 8:
				var replanned: PackedVector3Array = route_resolver.call(from, selected())
				rescue_origin = from
				if not replanned.is_empty():
					route = replanned
					route_index = 0
					route_start = from
					start = from
	var progress := 0.0
	while route_index < route.size() - 1:
		var target := route[route_index]
		var reach := _passed(start, from, target, progress, 7.2 if corridor_route else 24.0)
		if reach < 0:
			break
		progress = reach
		route_index += 1
	var final := route[route.size() - 1]
	var was_arrived := arrived
	arrived = from.distance_to(final) <= (14.0 if was_arrived else 8.0)
	if not arrived and not was_arrived and _passed(start, from, final, progress, 7.2 if corridor_route else 8.0) >= 0:
		arrived = true
	if arrived:
		route_index = route.size() - 1
	previous_point = from
	has_previous = true

func _following_leg(point: Vector3) -> void:
	var last := mini(route.size() - 1, route_index + (1 if corridor_route else 8))
	for index in range(route_index, last):
		var a := route[index]
		var b := route[index + 1]
		var leg := b - a
		if leg.length_squared() < 0.01:
			continue
		var t := (point - a).dot(leg) / leg.length_squared()
		if t < 0.08 or t > 1.0:
			continue
		var offset := point - a.lerp(b, t)
		var fits: bool = absf(offset.y) <= (9 if corridor_route else 24) and Vector2(offset.x, offset.z).length() <= (6.5 if corridor_route else 32)
		if fits:
			route_index = index + 1

func _passed(a: Vector3, b: Vector3, target: Vector3, minimum: float, radius: float) -> float:
	var movement := b - a
	var t := clampf((target - a).dot(movement) / movement.length_squared(), minimum, 1.0) if movement.length_squared() > 0.0001 else minimum
	var closest := a.lerp(b, t)
	if corridor_route:
		# Cell-shaped capture tolerates cutting a traversable corner and flying
		# below the reference height, while adjacent16m corridors stay separate.
		var offset := closest - target
		return t if absf(offset.x) <= radius and absf(offset.z) <= radius and absf(offset.y) <= 9.0 else -1.0
	return t if closest.distance_to(target) <= radius else -1.0

func waypoint() -> Vector3:
	return route[route_index] if not route.is_empty() else Vector3.ZERO

func remaining_distance(from: Vector3) -> float:
	if route.is_empty():
		return 0.0
	var total := from.distance_to(waypoint())
	for index in range(route_index, route.size() - 1):
		total += route[index].distance_to(route[index + 1])
	return total

func place_temporary(point: Vector3, from: Vector3, track_now: bool = true) -> void:
	if not track_now and selected_id == "temporary":
		var active := selected()
		if active != null:
			active.id = "temporary.active"
			selected_id = active.id
	locations = locations.filter(func(item: MapLocation): return item.layer != "temporary" or item.id == selected_id)
	locations = locations.filter(func(item: MapLocation): return item.id != "temporary")
	var location := MapLocation.new()
	location.id = "temporary"
	location.display_name = "临时路标"
	location.kind = "landmark"
	location.point = point
	location.layer = "temporary"
	location.description = "探索参考点；使用放置时的飞行高度，可重新点击空白处替换。"
	locations.append(location)
	if track_now:
		select(location.id, from)
	else:
		changed.emit()
