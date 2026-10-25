class_name FlightChallengeRules
extends RefCounted
const KINDS := ["race", "balloons", "orbit", "follow", "regional"]
const GATE_EDGE_OFFSET := 0.3
const GATE_BAR_WIDTH := 0.45

static func gate_opening_half(mission: MissionDefinition) -> float:
	return float(mission.challenge.get("gate_half", 3.4)) + GATE_EDGE_OFFSET - GATE_BAR_WIDTH * 0.5

static func gate_basis(normal: Vector3, up_hint: Vector3 = Vector3.ZERO) -> Basis:
	if up_hint.is_finite() and not up_hint.is_zero_approx():
		var up := up_hint - normal * up_hint.dot(normal)
		if up.length_squared() > 0.0001: return Basis.looking_at(normal, up.normalized())
	return Basis.looking_at(normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP)

static func gate_basis_for(mission: MissionDefinition, index: int) -> Basis:
	var ups: PackedVector3Array = mission.challenge.get("gate_ups", PackedVector3Array())
	return gate_basis(mission.gate_normals[index], ups[index] if ups.size() == mission.gate_normals.size() else Vector3.ZERO)

static func passes_gate(mission: MissionDefinition, stage: int, from: Vector3, to: Vector3) -> bool:
	if stage >= mission.checkpoints.size() or stage >= mission.gate_normals.size() or not from.is_finite() or not to.is_finite():
		return false
	var center := mission.checkpoints[stage]
	var normal := mission.gate_normals[stage]
	var a := (from - center).dot(normal)
	var b := (to - center).dot(normal)
	if a >= 0 or b < 0 or b - a <= 0.00000001:
		return false
	var crossing := from.lerp(to, -a / (b - a)) - center
	var local := gate_basis_for(mission, stage).inverse() * crossing
	# The body already has physical collision. Shrinking the centre crossing
	# again excluded a 32.5cm strip inside the actual opening on every side.
	var half := gate_opening_half(mission) + 0.01
	return absf(local.x) <= half and absf(local.y) <= half

static func balloon_point(mission: MissionDefinition, index: int, elapsed: float) -> Vector3:
	if mission.challenge.get("balloon_revision", 0) == 2:
		var age := maxf(0, elapsed - balloon_release_time(mission, index))
		return mission.checkpoints[index] + Vector3(sin(age * 0.7 + index) * 0.35, age * float(mission.challenge.rise_speed), cos(age * 0.6 + index) * 0.35)
	var rise := -maxf(0, 2.0 - elapsed * 0.5)
	return mission.checkpoints[index] + Vector3(sin(elapsed * 0.7 + index) * 0.35, rise + sin(elapsed * 0.9 + index * 1.7) * 0.4, cos(elapsed * 0.6 + index) * 0.35)

static func balloon_release_time(mission: MissionDefinition, index: int) -> float:
	return float(mission.challenge.get("release_delay", 0)) + index * float(mission.challenge.get("release_interval", 0))

static func balloon_released(mission: MissionDefinition, index: int, elapsed: float) -> bool:
	return elapsed >= balloon_release_time(mission, index)

static func balloon_step(mission: MissionDefinition, saved: Dictionary, from: Vector3, point: Vector3, delta: float, can_hit: bool) -> Dictionary:
	var state := saved.duplicate(true)
	if not is_finite(delta) or delta <= 0 or state.get("failed", false) or (state.has("started") and not state.started):
		return state
	var before_time := float(state.get("elapsed", 0))
	state.elapsed = before_time + delta
	var hits: Array = state.get("hits", []).duplicate()
	for index in mission.checkpoints.size():
		if hits.has(index) or not balloon_released(mission, index, state.elapsed):
			continue
		var center := balloon_point(mission, index, state.elapsed)
		# Height is checked first: reaching the ceiling is already a missed balloon.
		if center.y >= float(mission.challenge.get("height_limit", INF)):
			state.failed = true
			return state
		if not can_hit or not from.is_finite() or not point.is_finite():
			continue
		var release := balloon_release_time(mission, index)
		var start := from.lerp(point, clampf((release - before_time) / delta, 0, 1))
		var previous := balloon_point(mission, index, maxf(before_time, release))
		var contact := Geometry3D.get_closest_point_to_segment(Vector3.ZERO, start - previous, point - center)
		if contact.length() <= float(mission.challenge.get("balloon_radius", 1.15)) + 0.22:
			hits.append(index)
	state.hits = hits
	return state

static func follow_point(mission: MissionDefinition, elapsed: float) -> Vector3:
	if mission.challenge.get("follow_revision", 0) == 2 and mission.checkpoints.size() >= 4:
		var count := mission.checkpoints.size()
		var phase := maxf(0, elapsed) * float(mission.challenge.path_speed) / float(mission.challenge.path_length) * count
		var index := floori(phase) % count
		return mission.checkpoints[index].cubic_interpolate(mission.checkpoints[(index + 1) % count], mission.checkpoints[posmod(index - 1, count)], mission.checkpoints[(index + 2) % count], fmod(phase, 1))
	var radius := float(mission.challenge.get("path_radius", 12))
	var angle := elapsed * 0.20
	return mission.target_point + Vector3(cos(angle) * radius, 0, sin(angle) * radius)

static func view_valid(mission: MissionDefinition, view: Dictionary, target: Vector3) -> bool:
	var camera: Variant = view.get("origin")
	var forward: Variant = view.get("forward")
	if not camera is Vector3 or not forward is Vector3 or not camera.is_finite() or not forward.is_finite() or not view.get("clear", false):
		return false
	var line: Vector3 = target - camera
	return line.length() > 0.1 and forward.normalized().dot(line.normalized()) >= cos(deg_to_rad(float(mission.challenge.get("view_angle", 22))))

static func in_flight_band(mission: MissionDefinition, point: Vector3, target: Vector3) -> bool:
	var offset := point - target
	var distance := Vector2(offset.x, offset.z).length()
	return distance >= float(mission.challenge.get("radius_min", 8)) and distance <= float(mission.challenge.get("radius_max", 22)) and absf(offset.y) <= float(mission.challenge.get("height_tolerance", 2.5))

static func step(mission: MissionDefinition, saved: Dictionary, from: Vector3, point: Vector3, delta: float, view: Dictionary) -> Dictionary:
	if mission.kind == "balloons" and mission.challenge.get("balloon_revision", 0) == 2:
		return balloon_step(mission, saved, from, point, delta, from.is_finite() and point.is_finite() and delta > 0 and delta <= 0.5 and point.distance_to(from) <= maxf(3, delta * 120))
	var state := saved.duplicate(true)
	if not from.is_finite() or not point.is_finite() or delta <= 0 or delta > 0.5 or point.distance_to(from) > maxf(3, delta * 120):
		return state
	if mission.kind == "regional":
		return RegionalChallengeRules.step(mission, saved, from, point, delta, view)
	if mission.kind == "follow" and mission.challenge.get("follow_revision", 0) == 2:
		var elapsed := float(state.get("elapsed", 0))
		var target := follow_point(mission, elapsed + delta)
		if elapsed == 0 and point.distance_to(target) > float(mission.challenge.range):
			return state
		state.elapsed = elapsed + delta
		var visible: bool = view.get("in_view", view_valid(mission, view, target)) and view.get("clear", false)
		state.visible_time = float(state.get("visible_time", 0)) + (delta if visible else 0.0)
		state.near_time = float(state.get("near_time", 0)) + (delta if point.distance_to(target) <= float(mission.challenge.range) else 0.0)
		return state
	if (mission.kind == "orbit" and delta > 0.25) or (mission.kind == "follow" and delta > 0.1):
		return state
	state.elapsed = float(state.get("elapsed", 0)) + delta
	match mission.kind:
		"race":
			var stage := int(state.get("stage", 0))
			if passes_gate(mission, stage, from, point):
				state.stage = stage + 1
		"balloons":
			var hits: Array = state.get("hits", []).duplicate()
			for index in mission.checkpoints.size():
				if hits.has(index):
					continue
				var center := balloon_point(mission, index, state.elapsed)
				var before := balloon_point(mission, index, state.elapsed - delta)
				var contact := Geometry3D.get_closest_point_to_segment(Vector3.ZERO, from - before, point - center)
				if contact.length() <= float(mission.challenge.get("balloon_radius", 1.15)) + 0.22:
					hits.append(index)
			state.hits = hits
		"orbit", "follow":
			var target := follow_point(mission, state.elapsed) if mission.kind == "follow" else mission.target_point
			var offset := point - target
			var valid := view_valid(mission, view, target) and in_flight_band(mission, point, target)
			if mission.kind == "orbit":
				if valid and in_flight_band(mission, from, target):
					var before := from - target
					var angle := wrapf(atan2(offset.z, offset.x) - atan2(before.z, before.x), -PI, PI)
					if absf(angle) <= deg_to_rad(45):
						var signed_arc := float(state.get("orbit", 0)) * int(state.get("direction", 0))
						signed_arc = clampf(signed_arc + angle, -TAU, TAU)
						state.direction = int(signf(signed_arc))
						state.orbit = absf(signed_arc)
			else:
				var velocity := Vector3(-sin(state.elapsed * 0.2), 0, cos(state.elapsed * 0.2))
				var travel := point - from
				valid = valid and offset.normalized().dot(velocity) < -0.15
				if valid and travel.length() > 0.0001 and travel.normalized().dot(velocity) > 0.3:
					state.distance = minf(float(mission.challenge.get("follow_distance", 60)), float(state.get("distance", 0)) + minf(travel.length(), float(mission.challenge.get("path_radius", 12)) * 0.2 * delta * 1.5))
			state.lost = 0.0 if valid else minf(2, float(state.get("lost", 0)) + delta)
			# Exploration orbit is cumulative: an imperfect shot pauses progress
			# instead of erasing a nearly completed lap. Follow retains its rule.
			if mission.kind == "follow" and state.lost > 1.0:
				state.distance = 0.0
	return state

static func finished(mission: MissionDefinition, state: Dictionary) -> bool:
	if state.get("failed", false):
		return false
	match mission.kind:
		"regional": return int(state.get("stage", 0)) >= mission.checkpoints.size() and not mission.checkpoints.is_empty()
		"race": return int(state.get("stage", 0)) >= mission.checkpoints.size() and not mission.checkpoints.is_empty()
		"balloons": return state.get("hits", []).size() == mission.checkpoints.size() and not mission.checkpoints.is_empty()
		"orbit": return float(state.get("orbit", 0)) >= TAU - 0.001
		"follow":
			if mission.challenge.get("follow_revision", 0) == 2:
				var elapsed := float(state.get("elapsed", 0))
				var required := elapsed * float(mission.challenge.coverage)
				return elapsed + 0.00001 >= float(mission.challenge.duration) and float(state.get("visible_time", 0)) + 0.00001 >= required and float(state.get("near_time", 0)) + 0.00001 >= required
			return float(state.get("distance", 0)) >= float(mission.challenge.get("follow_distance", 60))
	return false

static func valid_state(mission: MissionDefinition, state: Dictionary) -> bool:
	if mission.kind not in KINDS or state.get("status") != "active" or state.get("kind") != mission.kind:
		return false
	if mission.kind == "regional":
		return RegionalChallengeRules.valid(mission, state)
	if state.has("failed") and not state.failed is bool:
		return false
	if state.has("started") and not state.started is bool:
		return false
	for key: String in ["elapsed", "lost", "orbit", "distance", "visible_time", "near_time"]:
		var value: Variant = state.get(key, 0)
		if not FlightInput.finite_number(value) or float(value) < 0 or float(value) > 1e9:
			return false
	if float(state.get("visible_time", 0)) > float(state.get("elapsed", 0)) + 0.00001 or float(state.get("near_time", 0)) > float(state.get("elapsed", 0)) + 0.00001:
		return false
	if float(state.get("orbit", 0)) > TAU or float(state.get("distance", 0)) > float(mission.challenge.get("follow_distance", 60)):
		return false
	if not FlightInput.valid_index(state.get("stage", 0), mission.checkpoints.size() + 1):
		return false
	var hits: Variant = state.get("hits", [])
	if not hits is Array:
		return false
	if mission.kind == "balloons" and state.has("started") and not state.started and (float(state.get("elapsed", 0)) != 0 or not hits.is_empty() or state.get("failed", false)):
		return false
	var seen := {}
	for index: Variant in hits:
		if not FlightInput.valid_index(index, mission.checkpoints.size()) or seen.has(int(index)):
			return false
		if mission.kind == "balloons" and not balloon_released(mission, int(index), float(state.get("elapsed", 0))):
			return false
		seen[int(index)] = true
	return FlightInput.finite_number(state.get("direction", 0)) and float(state.get("direction", 0)) in [-1.0, 0.0, 1.0]
