class_name RegionalChallengeRules
extends RefCounted
static func step(task: MissionDefinition, saved: Dictionary, from: Vector3, point: Vector3, delta: float, view: Dictionary) -> Dictionary:
	var state := saved.duplicate(true)
	var stage := int(state.get("stage", 0))
	if stage >= task.checkpoints.size():
		return state
	var mode: String = task.challenge.mode
	var radius := float(task.challenge.radius)
	var contacts := int(view.get("contacts", -1))
	if mode == "clean":
		if state.get("started", false) and contacts >= 0 and contacts != int(state.get("contact_base", contacts)):
			state.stage = 0
			state.started = false
			state.attempts = int(state.get("attempts", 0)) + 1
			return state
		var close := Geometry3D.get_closest_point_to_segment(task.checkpoints[stage], from, point).distance_to(task.checkpoints[stage]) <= radius
		if close:
			state.started = true
			state.contact_base = contacts
			state.stage = stage + 1
		return state
	if mode == "sequence":
		for index in range(stage + 1, task.checkpoints.size()):
			if point.distance_to(task.checkpoints[index]) < radius:
				state.stage = 0
				state.hold = 0.0
				state.attempts = int(state.get("attempts", 0)) + 1
				return state
	var near := point.distance_to(task.checkpoints[stage]) <= radius and float(view.get("speed", INF)) <= float(task.challenge.max_speed)
	state.hold = float(state.get("hold", 0)) + delta if near and view.get("interacting", false) else 0.0
	if state.hold >= float(task.challenge.hold):
		state.stage = stage + 1
		state.hold = 0.0
	return state

static func valid(task: MissionDefinition, state: Dictionary) -> bool:
	if not FlightInput.valid_index(state.get("stage", 0), task.checkpoints.size() + 1) or not FlightInput.valid_index(state.get("attempts", 0), 1000000000):
		return false
	if not FlightInput.finite_number(state.get("hold", 0)) or float(state.get("hold", 0)) < 0 or float(state.get("hold", 0)) > float(task.challenge.hold) + 0.5:
		return false
	if state.has("started") and not state.started is bool:
		return false
	return FlightInput.finite_number(state.get("contact_base", -1))
