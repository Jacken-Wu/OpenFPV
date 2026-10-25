class_name MissionController
extends RefCounted
signal balloon_popped(point: Vector3, index: int)
signal race_gate_passed(stage: int)
signal race_finished

var catalog: ContentCatalog
var store: ProgressStore
var navigation: MapNavigation
var exploration: WorldExploration
var dwell := 0.0
var dwell_id := ""
var challenge_id := ""
var runtime_state: Dictionary = {}
var previous_point := Vector3.ZERO
var motion_valid := false
var checkpoint_time := 0.0
var nearby_key := Vector3i(999999, 999999, 999999)
var nearby: Array[MissionDefinition] = []
var balloon_states: Dictionary = {}
var balloon_saves: Dictionary = {}
var balloon_previous := Vector3.ZERO
var balloon_motion_valid := false

func _init(content: ContentCatalog, progress: ProgressStore, map_navigation: MapNavigation) -> void:
	catalog = content
	store = progress
	navigation = map_navigation

func tracked() -> MissionDefinition:
	return store.mission_definition(store.data.tracked_mission)

func definitions() -> Array[MissionDefinition]:
	var result: Array[MissionDefinition] = []
	if exploration != null:
		result.append_array(exploration.definitions)
	else:
		result.assign(catalog.manifest.missions)
	return result

func photo_candidate() -> MissionDefinition:
	var current := tracked()
	if current != null and current.kind == "photo":
		return current
	for mission: MissionDefinition in definitions():
		if mission.kind == "photo" and store.mission_status(mission.id) == "active":
			return mission
	return null

func accept(id: String, point: Vector3) -> Dictionary:
	var pending := flush_challenge()
	if not pending.get("ok", true):
		return pending
	var result := store.accept_mission(id)
	if result.ok:
		invalidate_motion()
		balloon_states.erase(id)
		balloon_saves.erase(id)
		challenge_id = ""
		runtime_state.clear()
		dwell = 0
		dwell_id = ""
		if exploration != null:
			exploration.refresh(RegionalWorld.key_at(point))
		sync_navigation(point)
	return result

func track(id: String, point: Vector3) -> Dictionary:
	var pending := flush_challenge()
	if not pending.get("ok", true):
		return pending
	var previous := tracked()
	var result := store.track_mission(id)
	if result.ok:
		invalidate_motion()
		if id.is_empty() and previous != null and navigation.selected_id == previous.location_id:
			navigation.clear()
		else:
			sync_navigation(point)
	return result

func sync_navigation(point: Vector3) -> void:
	var mission := tracked()
	if mission != null:
		var location := navigation.find_location(mission.location_id)
		if location != null:
			location.point = objective_point(mission)
		navigation.select(mission.location_id, point)

func objective_point(mission: MissionDefinition) -> Vector3:
	if store.mission_status(mission.id) != "active":
		return mission.acceptance_point()
	if mission.kind in ["circuit", "courier", "race"]:
		var stage := mini(int(store.data.assignments.get(mission.id, {}).get("stage", 0)), mission.checkpoints.size() - 1)
		return mission.checkpoints[stage]
	if mission.kind == "regional":
		return mission.checkpoints[mini(int(challenge_state(mission).get("stage", 0)), mission.checkpoints.size() - 1)]
	if mission.kind == "balloons":
		var state := challenge_state(mission)
		if not state.get("started", false):
			return mission.acceptance_point()
		for index in mission.checkpoints.size():
			if not state.get("hits", []).has(index):
				return FlightChallengeRules.balloon_point(mission, index, float(state.get("elapsed", 0)))
	if mission.kind == "follow":
		return FlightChallengeRules.follow_point(mission, float(challenge_state(mission).get("elapsed", 0)))
	return mission.target_point

func objective_hint(mission: MissionDefinition) -> String:
	match mission.kind:
		"regional":
			var state := challenge_state(mission)
			var stage := mini(int(state.get("stage", 0)) + 1, mission.checkpoints.size())
			if mission.challenge.mode == "clean":
				return "无碰撞穿行 %d / %d · %s" % [stage, mission.checkpoints.size(), "途中触碰即回到起点" if state.get("started", false) else "飞入蓝色起点开始 · 无时限"]
			return "%s %d / %d · 靠近并按住 E %.1f秒 · %.0f%%" % ["修复终端" if mission.challenge.mode == "repair" else "按赤日→蓝月→金星→青门顺序", stage, mission.checkpoints.size(), mission.challenge.hold, float(state.get("hold", 0)) / float(mission.challenge.hold) * 100]
		"race": return "正向穿过第 %d / %d 门 · 无倒计时" % [mini(int(store.data.assignments[mission.id].get("stage", 0)) + 1, mission.checkpoints.size()), mission.checkpoints.size()]
		"balloons":
			if not challenge_state(mission).get("started", false):
				return "已接取 · 到任务平台停稳按 E 开始放球"
			return "撞破气球 %d / %d · 每%.1f秒放出 · 限高 %.1fm" % [challenge_state(mission).get("hits", []).size(), mission.checkpoints.size(), mission.challenge.get("release_interval", 3), mission.challenge.get("height_limit", 300)]
		"orbit": return "环绕 %.0f° / 360° · 半径 %.0f～%.0fm / 高差±%.0fm · 偏离只暂停进度" % [rad_to_deg(float(challenge_state(mission).get("orbit", 0))), mission.challenge.radius_min, mission.challenge.radius_max, mission.challenge.height_tolerance]
		"follow":
			var state := challenge_state(mission)
			var seconds := float(state.get("elapsed", 0))
			return "靠近观测机50米内开始跟拍" if seconds <= 0 else "跟拍 %.0f / ≥30秒 · 视野 %.0f%% / 80%% · 50米内 %.0f%% / 80%%" % [seconds, float(state.get("visible_time", 0)) / seconds * 100, float(state.get("near_time", 0)) / seconds * 100]
		"survey": return "在信标范围低速停留 %.0f 秒 · %.0f%%" % [mission.hold_seconds, dwell / mission.hold_seconds * 100]
		"circuit": return "依次通过巡检点 %d / %d · 无倒计时" % [mini(int(store.data.assignments[mission.id].get("stage", 0)) + 1, mission.checkpoints.size()), mission.checkpoints.size()]
		"courier": return "低速按 E 取件" if int(store.data.assignments[mission.id].get("stage", 0)) == 0 else "返回服务平台 · 低速按 E 提交"
	return "飞抵信标 · 按住 E %.0f 秒" % mission.hold_seconds

func update_objective(point: Vector3, speed: float, delta: float, interacting: bool, paused: bool, view: Dictionary = {}, contacts: int = -1) -> Dictionary:
	var balloon_result := _tick_balloons(point, delta, paused)
	var mission := tracked()
	if mission != null and mission.kind == "balloons":
		return balloon_result
	if not balloon_result.is_empty():
		return balloon_result
	if mission != null and mission.kind in FlightChallengeRules.KINDS:
		view = view.duplicate()
		view.merge({"speed": speed, "interacting": interacting, "contacts": contacts}, true)
		return _update_challenge(mission, point, delta, paused, view)
	motion_valid = false
	if mission == null or mission.kind not in ["survey", "circuit", "courier"]:
		dwell = 0
		return {}
	if dwell_id != mission.id:
		dwell = 0
		dwell_id = mission.id
	var near := point.distance_to(objective_point(mission)) <= mission.interaction_radius and speed <= mission.max_speed
	if mission.kind == "survey":
		dwell = dwell + delta if near and not paused else 0.0
		if dwell >= mission.hold_seconds:
			return finish(mission.id, {"point": point, "speed": speed, "seconds": dwell})
	elif near and ((mission.kind == "circuit" and not paused) or (mission.kind == "courier" and interacting)):
		var result := store.advance_mission(mission.id, point, speed, interacting)
		if result.ok:
			if int(store.data.assignments[mission.id].get("stage", 0)) >= mission.checkpoints.size():
				return finish(mission.id)
			sync_navigation(point)
			result.message = "航点已保存 · " + objective_hint(mission)
		return result
	return {}

func local_definitions(point: Vector3) -> Array[MissionDefinition]:
	var key := WorldGenerator.key_at(point)
	if key != nearby_key:
		nearby_key = key
		nearby.clear()
		if store.regions is BiomeWorld:
			var page := RegionalWorld.key_at(point)
			var xs: Array[int] = [page.x]
			var zs: Array[int] = [page.y]
			var offset := Vector2(point.x, point.z) - Vector2(page) * RegionalWorld.SIZE
			if offset.x < 128 or offset.x > RegionalWorld.SIZE - 128:
				xs.append(page.x + (-1 if offset.x < 128 else 1))
			if offset.y < 128 or offset.y > RegionalWorld.SIZE - 128:
				zs.append(page.y + (-1 if offset.y < 128 else 1))
			var seen := {}
			for x in xs:
				for z in zs:
					for mission: MissionDefinition in store.regions.region(Vector2i(x, z)).missions:
						if not seen.has(mission.id) and mission.pickup_distance(point) <= 200:
							nearby.append(mission)
							seen[mission.id] = true
			for id: String in store.data.assignments:
				if seen.has(id):
					continue
				var mission := store.mission_definition(id)
				if mission != null and (id == store.data.tracked_mission or mission.pickup_distance(point) <= 200):
					nearby.append(mission)
					seen[id] = true
		else:
			nearby.assign(definitions())
		# Replaced legacy objectives share a reception slot. Show its current task,
		# or an explicitly active historical task, instead of stacking two signs.
		var by_pad := {}
		var unique: Array[MissionDefinition] = []
		for mission: MissionDefinition in nearby:
			if mission.pickup_platform.is_empty():
				unique.append(mission)
				continue
			var pad: Vector3 = mission.pickup_platform.point
			if not by_pad.has(pad):
				by_pad[pad] = mission
			elif store.data.tracked_mission == mission.id or (store.mission_status(mission.id) == "active" and store.mission_status(by_pad[pad].id) != "active"):
				by_pad[pad] = mission
		for mission: MissionDefinition in by_pad.values():
			unique.append(mission)
		nearby = unique
	return nearby

func available_at(point: Vector3) -> MissionDefinition:
	var best: MissionDefinition
	for mission: MissionDefinition in local_definitions(point):
		if store.mission_status(mission.id) != "active" and mission.pickup_distance(point) <= mission.interaction_radius:
			if best == null or mission.pickup_distance(point) < best.pickup_distance(point):
				best = mission
	return best

func accept_nearby(point: Vector3, speed: float, docked_id: String = "") -> Dictionary:
	var mission := platform_task_at(point)
	if mission == null:
		return {}
	if not is_finite(speed) or speed > 0.6 or docked_id != mission.id:
		return {"ok": false, "message": "请降落在任务小平台中央，停稳后按 E 接取"}
	if store.mission_status(mission.id) != "active":
		var accepted := accept(mission.id, point)
		if not accepted.ok or mission.kind != "balloons":
			return accepted
	return start_balloons(mission.id)

func platform_task_at(point: Vector3) -> MissionDefinition:
	for mission: MissionDefinition in local_definitions(point):
		if mission.kind == "balloons" and store.mission_status(mission.id) == "active" and not challenge_state(mission).get("started", false) and mission.pickup_distance(point) <= mission.interaction_radius:
			return mission
	return available_at(point)

func start_balloons(id: String) -> Dictionary:
	var mission := store.mission_definition(id)
	if mission == null or mission.kind != "balloons" or store.mission_status(id) != "active":
		return {"ok": false, "message": "请先接取气球任务"}
	var state: Dictionary = store.data.assignments[id].duplicate(true)
	if state.get("started", false):
		return {"ok": true, "message": "气球挑战已经开始"}
	state.started = true
	var saved := store.save_challenge_state(id, state, true)
	if saved.ok:
		balloon_states.erase(id)
		balloon_saves.erase(id)
		invalidate_motion()
		sync_navigation(mission.acceptance_point())
		saved.message = "气球挑战开始 · 3秒后开始放球，升空后尽快撞破"
	return saved

func invalidate_motion() -> void:
	motion_valid = false
	balloon_motion_valid = false
	nearby_key = Vector3i(999999, 999999, 999999)

func challenge_state(mission: MissionDefinition) -> Dictionary:
	if mission.kind == "balloons":
		return balloon_states.get(mission.id, store.data.assignments.get(mission.id, {}))
	return runtime_state if challenge_id == mission.id else store.data.assignments.get(mission.id, {})

func flush_challenge() -> Dictionary:
	for id: String in balloon_states:
		if store.mission_status(id) == "active" and balloon_states[id] != store.data.assignments[id]:
			var saved := store.save_challenge_state(id, balloon_states[id])
			if not saved.ok:
				return saved
	if challenge_id.is_empty() or store.mission_status(challenge_id) != "active":
		return {}
	if runtime_state == store.data.assignments.get(challenge_id, {}):
		return {}
	var result := store.save_challenge_state(challenge_id, runtime_state)
	if result.ok:
		checkpoint_time = 0
	return result

func _tick_balloons(point: Vector3, delta: float, paused: bool) -> Dictionary:
	if paused or delta <= 0:
		balloon_motion_valid = false if paused else balloon_motion_valid
		return {}
	var result: Dictionary = {}
	var can_hit := balloon_motion_valid and delta <= 0.5 and point.distance_to(balloon_previous) <= maxf(3, delta * 120)
	for id: String in store.data.assignments.keys():
		if store.mission_status(id) != "active":
			balloon_states.erase(id)
			balloon_saves.erase(id)
			continue
		var mission := store.mission_definition(id)
		if mission == null or mission.kind != "balloons":
			continue
		var committed: Dictionary = store.data.assignments[id]
		if not committed.get("started", false):
			continue
		if FlightChallengeRules.finished(mission, committed):
			result = finish(id)
			continue
		var state := FlightChallengeRules.balloon_step(mission, balloon_states.get(id, committed), balloon_previous, point, delta, can_hit)
		balloon_states[id] = state
		balloon_saves[id] = float(balloon_saves.get(id, 0)) + delta
		var discrete: bool = state.get("hits", []) != committed.get("hits", [])
		if discrete or state.get("failed", false) or float(balloon_saves[id]) >= 1 or FlightChallengeRules.finished(mission, state):
			var saved := store.save_challenge_state(id, state)
			if not saved.ok:
				balloon_states[id] = committed.duplicate(true)
				result = saved
				continue
			balloon_saves[id] = 0
			for index: int in state.get("hits", []):
				if not committed.get("hits", []).has(index):
					balloon_popped.emit(FlightChallengeRules.balloon_point(mission, index, state.elapsed), index)
			if state.get("failed", false):
				store.feedback.emit("failure")
				if navigation.selected_id == mission.location_id:
					navigation.clear()
				result = {"ok": false, "message": "气球已超过任务限高，本轮失败。回任务平台重新接取。"}
			elif FlightChallengeRules.finished(mission, state):
				result = finish(id)
	balloon_previous = point
	balloon_motion_valid = true
	return result

func _update_challenge(mission: MissionDefinition, point: Vector3, delta: float, paused: bool, view: Dictionary) -> Dictionary:
	if delta <= 0:
		return {}
	if challenge_id != mission.id:
		challenge_id = mission.id
		runtime_state = store.data.assignments[mission.id].duplicate(true)
		checkpoint_time = 0
		motion_valid = false
	if paused:
		motion_valid = false
		return {}
	if FlightChallengeRules.finished(mission, store.data.assignments[mission.id]):
		return finish(mission.id)
	var before := runtime_state.duplicate(true)
	if motion_valid:
		runtime_state = FlightChallengeRules.step(mission, runtime_state, previous_point, point, delta, view)
	previous_point = point
	motion_valid = true
	checkpoint_time += delta
	var discrete: bool = before.get("stage", 0) != runtime_state.get("stage", 0) or before.get("hits", []) != runtime_state.get("hits", []) or before.get("attempts", 0) != runtime_state.get("attempts", 0)
	var progress: bool = before.get("orbit", 0) != runtime_state.get("orbit", 0) or before.get("distance", 0) != runtime_state.get("distance", 0) or before.get("hold", 0) != runtime_state.get("hold", 0) or (mission.kind == "follow" and before.get("elapsed", 0) != runtime_state.get("elapsed", 0))
	if discrete or (progress and checkpoint_time >= 1) or FlightChallengeRules.finished(mission, runtime_state):
		var result := flush_challenge()
		if not result.get("ok", true):
			runtime_state = store.data.assignments[mission.id].duplicate(true)
			motion_valid = false
			return result
		if FlightChallengeRules.finished(mission, runtime_state):
			return finish(mission.id)
		if discrete:
			if mission.kind == "regional":
				store.feedback.emit("failure" if before.get("attempts", 0) != runtime_state.get("attempts", 0) else "accept")
			if mission.kind == "race":
				race_gate_passed.emit(int(runtime_state.stage))
			sync_navigation(point)
			return {"ok": true, "message": "目标进度已保存 · " + objective_hint(mission)}
	return {}

func interaction_at(point: Vector3) -> MissionDefinition:
	var closest: MissionDefinition
	for mission: MissionDefinition in definitions():
		if mission.kind == "hold_interact" and store.mission_status(mission.id) == "active" and point.distance_to(mission.target_point) < mission.interaction_radius:
			if closest == null or point.distance_squared_to(mission.target_point) < point.distance_squared_to(closest.target_point):
				closest = mission
	return closest

func finish(id: String, evidence: Dictionary = {}) -> Dictionary:
	var mission := store.mission_definition(id)
	var was_active := store.mission_status(id) == "active"
	var result := store.complete_mission(id, evidence)
	if result.ok:
		invalidate_motion()
	if result.ok and exploration != null:
		exploration.refresh(RegionalWorld.key_at(navigation.previous_point))
	if result.ok and mission != null and navigation.selected_id == mission.location_id:
		navigation.clear()
	if result.ok and was_active and mission != null and mission.kind == "race" and not result.get("duplicate", false):
		race_finished.emit()
	return result
