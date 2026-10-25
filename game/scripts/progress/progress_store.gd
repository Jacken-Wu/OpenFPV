class_name ProgressStore
extends RefCounted
signal unlocked(category: String, title: String)
signal feedback(event: String)
## Commit a complete snapshot before exposing rewards or spending credits.

var catalog: ContentCatalog
var path: String
var data: Dictionary = {}
var warning := ""
var writable := true
var regions: RegionalWorld
var generated_definitions: Dictionary = {}

func _init(content: ContentCatalog, save_path: String = "user://profile/progress.json", load_existing: bool = true) -> void:
	catalog = content
	path = save_path
	if not load_existing:
		return
	data = _new_profile()
	if FileAccess.file_exists(path):
		var loaded := _read(path)
		if loaded.is_empty():
			loaded = _read(path + ".backup")
			warning = "主存档损坏，已读取备份。" if not loaded.is_empty() else "存档无法读取，已进入临时档；原文件保留。"
			writable = not loaded.is_empty()
		if not loaded.is_empty():
			data = loaded
			_restore_controls()
			for initial_id: String in _new_profile().owned:
				if not data.owned.has(initial_id):
					data.owned.append(initial_id)
			if int(data.world_version) in [1, 2, 3] and catalog.manifest.world_version == 4:
				var controls: Dictionary = loaded.settings.duplicate(true)
				data = _new_profile()
				data.settings = controls
				writable = true
				var reset_result := _commit(data)
				warning = "已按种子重新生成整个世界与初始进度。" if reset_result.ok else reset_result.message
			elif int(data.world_version) != catalog.manifest.world_version:
				writable = false
				warning = "世界版本不匹配，暂不覆盖原存档。"
			elif String(data.content_fingerprint) != catalog.fingerprint():
				warning = "内容已更新；旧取得记录保留，失效装配会回退初始套机。"
	prepare_geography()
	if int(data.world_version) >= 3:
		regions = BiomeWorld.new(catalog, int(data.seed), int(data.get("extension_radius", 4))) if int(data.world_version) >= 4 else RegionalWorld.new(catalog, int(data.seed))
	_restore_controls()
	if not data.has("exploration"):
		data.exploration = {"visited": {}, "mapped": {}, "portals": {}}
	_restore_missions()
	_restore_achievements()

func _restore_achievements() -> void:
	AchievementBook.prepare(data)
	for id: String in data.exploration.mapped:
		if regions is BiomeWorld:
			var p: Dictionary = regions.instance(id)
			if not p.is_empty():
				AchievementBook.biome(data, p.biomes[0].id, catalog)
	for id: String in data.assignments:
		if not mission_completed_once(id):
			continue
		var kind: String = data.assignments[id].get("kind", "")
		if kind.is_empty():
			var mission := mission_definition(id)
			if mission != null:
				kind = mission.kind
		if not kind.is_empty():
			AchievementBook.completed(data, kind)
	AchievementBook.award(data, catalog)

func prepare_geography() -> void:
	if data.has("extension_radius"):
		return
	var radius := 4
	var pattern := RegEx.new()
	pattern.compile("(surface|sky|maze):(-?[0-9]+):(-?[0-9]+)")
	for found: RegExMatch in pattern.search_all(JSON.stringify(data)):
		var scale := 1.0 if found.get_string(1) == "surface" else 2.0 if found.get_string(1) == "sky" else 1280.0 / 768.0
		radius = maxi(radius, ceili(maxi(absi(int(found.get_string(2))), absi(int(found.get_string(3)))) * scale) + 3)
	var deployment: Array = data.get("deployment", [0, 0, 0])
	if deployment.size() == 3:
		radius = maxi(radius, ceili(maxf(absf(float(deployment[0])), absf(float(deployment[2]))) / 768) + 3)
	data.extension_radius = radius

func _restore_missions() -> void:
	if not data.has("assignments"):
		data.assignments = {}
	if not data.has("tracked_mission"):
		data.tracked_mission = ""
	for mission: MissionDefinition in catalog.missions.values():
		if mission_status(mission.id) != "active" and (data.transactions.has(mission.transaction_id()) or (not mission.facility_id.is_empty() and (data.facilities.get(mission.facility_id, false) == true or data.missions.get(mission.facility_id, false) == true))):
			var completed: Dictionary = data.assignments.get(mission.id, {}).duplicate(true)
			completed.status = "completed"
			data.assignments[mission.id] = completed
	if mission_definition(data.tracked_mission) == null or mission_status(data.tracked_mission) != "active":
		data.tracked_mission = ""
	for id: String in data.assignments:
		if mission_status(id) != "active":
			continue
		var definition := mission_definition(id)
		if definition != null and definition.kind == "balloons" and (data.assignments[id].get("balloon_revision", 0) != 2 or not data.assignments[id].has("started")):
			data.assignments[id] = {"status": "active", "kind": "balloons", "balloon_revision": 2, "started": false, "completion_count": int(data.assignments[id].get("completion_count", 0))}
			warning = "气球任务已改为现场启动，请到任务平台停稳按 E 开始；已得奖励和其他任务进度保留。"
		if definition != null and definition.kind == "follow" and not data.assignments[id].has("visible_time"):
			var previous: Dictionary = data.assignments[id]
			data.assignments[id] = {"status": "active", "kind": "follow", "elapsed": 0.0, "visible_time": 0.0, "near_time": 0.0, "completion_count": int(previous.get("completion_count", 0)), "history_id": previous.get("history_id", id)}
			warning = "跟拍已更新为视野与距离占比挑战，本次拍摄从零开始；其他任务及奖励保留。"
		if definition != null and definition.kind in FlightChallengeRules.KINDS and not FlightChallengeRules.valid_state(definition, data.assignments[id]):
			data.assignments[id] = {"status": "active", "kind": definition.kind, "completion_count": int(data.assignments[id].get("completion_count", 0)), "history_id": definition.history_id if not definition.history_id.is_empty() else id}
			warning = "挑战进度字段失效，已保留任务并从起点恢复；原存档文件保留。"

func _new_profile(seed_value: int = 271828) -> Dictionary:
	var initial: DronePresetDefinition = catalog.presets[catalog.manifest.initial_preset_id]
	var start: Vector3 = BiomeWorld.new(catalog, seed_value).spawn_point() if catalog.manifest.world_version >= 4 else RegionalWorld.new(catalog, seed_value).region(Vector2i.ZERO).stations[0].point if catalog.manifest.world_version >= 3 else Vector3(0, 1.2, 16)
	return {"schema": 1, "seed": seed_value, "extension_radius": 4, "world_version": catalog.manifest.world_version,
		"content_fingerprint": catalog.fingerprint(), "credits": 0,
		"owned": [initial.id, initial.frame_id, initial.motor_set_id, initial.propeller_set_id],
		"transactions": [], "facilities": {}, "missions": {}, "settings": {}, "assignments": {}, "tracked_mission": "", "exploration": {"visited": {}, "mapped": {}, "portals": {}},
		"build": DroneAssembler.new(catalog).from_preset(initial.id), "deployment": [start.x, start.y, start.z], "dimension": "world.main"}

func reset_world(seed_value: int) -> Dictionary:
	if seed_value < -2147483648 or seed_value > 2147483647:
		return {"ok": false, "message": "种子超出有效整数范围"}
	var next := _new_profile(seed_value)
	next.settings = data.settings.duplicate(true)
	var result := _commit(next)
	if result.ok:
		regions = BiomeWorld.new(catalog, seed_value) if catalog.manifest.world_version >= 4 else RegionalWorld.new(catalog, seed_value)
		generated_definitions.clear()
		result.message = "已按新种子重建世界，操控设置保留。"
	return result

func _read(source: String) -> Dictionary:
	return read_snapshot(source)

static func read_snapshot(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(source)) != OK:
		return {}
	var value: Variant = parser.data
	if not value is Dictionary:
		return {}
	var record: Dictionary = value
	for field: String in ["save_name", "save_created", "save_updated"]:
		if record.has(field) and not record[field] is String:
			return {}
	if not record.has_all(["schema", "seed", "world_version", "content_fingerprint", "credits", "owned", "transactions", "facilities", "missions", "settings", "build"]):
		return {}
	for field: String in ["schema", "seed", "world_version"]:
		if not (record[field] is int or record[field] is float) or not is_finite(float(record[field])) or float(record[field]) != floorf(float(record[field])):
			return {}
	if float(record.seed) < -2147483648 or float(record.seed) > 2147483647 or float(record.world_version) < 1:
		return {}
	if int(record.world_version) >= 3 and not record.has("deployment"):
		return {}
	if record.has("deployment"):
		if not record.deployment is Array or record.deployment.size() != 3:
			return {}
		for coordinate: Variant in record.deployment:
			if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
				return {}
	if int(record.schema) != 1 or not record.owned is Array or not record.transactions is Array:
		return {}
	if record.has("extension_radius") and (not FlightInput.finite_number(record.extension_radius) or float(record.extension_radius) != floorf(float(record.extension_radius)) or float(record.extension_radius) < 4 or float(record.extension_radius) > 10000000):
		return {}
	for key: String in ["facilities", "missions", "settings", "build"]:
		if not record[key] is Dictionary:
			return {}
	if not (record.credits is float or record.credits is int) or not is_finite(float(record.credits)) or float(record.credits) < 0:
		return {}
	if record.has("tracked_mission") and not record.tracked_mission is String:
		return {}
	if record.has("assignments"):
		if not record.assignments is Dictionary:
			return {}
		for assignment: Variant in record.assignments.values():
			if not assignment is Dictionary or not assignment.get("status", "") in ["active", "completed", "failed"]:
				return {}
			if assignment.has("photo_path") and not assignment.photo_path is String:
				return {}
			if assignment.has("kind") and not assignment.kind is String:
				return {}
			if assignment.has("failed") and not assignment.failed is bool:
				return {}
			if assignment.has("completion_count") and not FlightInput.valid_index(assignment.completion_count, 1000000000):
				return {}
			for key: String in ["elapsed", "lost", "orbit", "distance"]:
				if assignment.has(key) and (not FlightInput.finite_number(assignment[key]) or float(assignment[key]) < 0 or float(assignment[key]) > 1e9):
					return {}
			if assignment.has("hits"):
				if not assignment.hits is Array:
					return {}
				var seen := {}
				for index: Variant in assignment.hits:
					if not FlightInput.valid_index(index, 10000) or seen.has(int(index)):
						return {}
					seen[int(index)] = true
			if assignment.has("stage") and (not (assignment.stage is int or assignment.stage is float) or not is_finite(float(assignment.stage)) or float(assignment.stage) < 0 or float(assignment.stage) != floorf(float(assignment.stage))):
				return {}
	if record.has("exploration"):
		if not record.exploration is Dictionary:
			return {}
		for group: String in ["visited", "mapped", "portals"]:
			if not record.exploration.get(group) is Dictionary:
				return {}
			for id: Variant in record.exploration[group]:
				if not id is String or record.exploration[group][id] != true:
					return {}
	if record.has("achievements"):
		if not record.achievements is Dictionary:
			return {}
		for group: String in ["unlocked", "biomes", "types"]:
			if not record.achievements.get(group) is Dictionary:
				return {}
			for id: Variant in record.achievements[group]:
				if not id is String or (not record.achievements[group][id] is String if group == "unlocked" else record.achievements[group][id] != true):
					return {}
	return record

func _commit(next: Dictionary, mirror_controls: bool = true) -> Dictionary:
	if not writable:
		return {"ok": false, "message": "存档受保护，操作未提交。"}
	var earned := AchievementBook.award(next, catalog)
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK:
		return {"ok": false, "message": "无法创建存档目录，操作未提交。"}
	var file := FileAccess.open(path + ".pending", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法写入存档，操作未提交。"}
	file.store_string(JSON.stringify(next, "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK or _read(path + ".pending").is_empty():
		return {"ok": false, "message": "存档校验失败，操作未提交。"}
	# Keep the last valid main file. A recovered profile must not replace it with corrupt bytes.
	if not _read(path).is_empty():
		error = DirAccess.copy_absolute(absolute, absolute + ".backup")
		if error != OK:
			return {"ok": false, "message": "无法备份存档，操作未提交。"}
	error = DirAccess.rename_absolute(absolute + ".pending", absolute)
	if error != OK:
		return {"ok": false, "message": "无法替换存档，操作未提交。"}
	data = next
	for title: String in earned:
		unlocked.emit("achievement", title)
	if mirror_controls:
		_mirror_controls()
	return {"ok": true, "message": "已保存"}

func use_snapshot(snapshot: Dictionary) -> void:
	data = snapshot.duplicate(true)
	if not data.has("exploration"):
		data.exploration = {"visited": {}, "mapped": {}, "portals": {}}
	prepare_geography()
	regions = BiomeWorld.new(catalog, int(data.seed), int(data.get("extension_radius", 4))) if int(data.world_version) >= 4 else RegionalWorld.new(catalog, int(data.seed))
	generated_definitions.clear()
	_restore_missions()
	_restore_achievements()

func complete_relay(instance_id: String, mission_tag: String, city_tag: String) -> Dictionary:
	# Legacy API retained for old integrations; production interactions use mission IDs.
	for mission: MissionDefinition in catalog.missions.values():
		if mission.kind == "hold_interact" and mission.mission_tag == mission_tag and mission.city_tag == city_tag:
			return _complete_mission(mission, instance_id, {})
	return {"ok": false, "message": "任务和城市条件不匹配"}

func mission_status(id: String) -> String:
	if data.get("assignments", {}).has(id):
		return String(data.assignments[id].get("status", "available"))
	var definition := mission_definition(id)
	return "completed" if definition != null and not definition.history_id.is_empty() and mission_completed_once(id) else "available"

func mission_completed_once(id: String) -> bool:
	var assignment: Dictionary = data.get("assignments", {}).get(id, {})
	if assignment.get("status") == "completed" or int(assignment.get("completion_count", 0)) > 0:
		return true
	var mission := mission_definition(id)
	if mission != null and not mission.history_id.is_empty():
		var historical: Dictionary = data.get("assignments", {}).get(mission.history_id, {})
		if historical.get("status") == "completed" or int(historical.get("completion_count", 0)) > 0:
			return true
	return mission != null and (data.transactions.has(mission.transaction_id()) or (not mission.facility_id.is_empty() and data.facilities.get(mission.facility_id, false)))

func mission_reward_text(id: String) -> String:
	if mission_completed_once(id):
		return "首次奖励已发放 · 可重复挑战，不再发放奖励"
	var mission := mission_definition(id)
	var reward: RewardDefinition = catalog.entries[mission.reward_id]
	return "首次完成奖励 %d 信用点%s" % [reward.credits, " + 装备永久使用权" if not reward.grants.is_empty() else ""]

func mission_definition(id: String) -> MissionDefinition:
	if catalog.missions.has(id):
		return catalog.missions[id]
	if regions == null or not (id.begins_with("proc:3:") or id.begins_with("proc:4:")):
		return null
	if not generated_definitions.has(id):
		var definition := regions.mission(id)
		if definition == null:
			return null
		if generated_definitions.size() >= 256:
			generated_definitions.clear()
		generated_definitions[id] = definition
	return generated_definitions[id]

func accept_mission(id: String) -> Dictionary:
	if mission_definition(id) == null:
		return {"ok": false, "message": "任务不存在"}
	if mission_status(id) == "active":
		return track_mission(id)
	var mission := mission_definition(id)
	if not mission.pickup_platform.is_empty():
		for other_id: String in data.assignments:
			if other_id == id or mission_status(other_id) != "active":
				continue
			var other := mission_definition(other_id)
			if other != null and not other.pickup_platform.is_empty() and other.acceptance_point().is_equal_approx(mission.acceptance_point()):
				return {"ok": false, "message": "此平台还有已接取的旧任务，请先完成该任务，再领取新任务。"}
	var next := data.duplicate(true)
	var count := int(data.assignments.get(id, {}).get("completion_count", 0))
	if mission_completed_once(id):
		count = maxi(count, 1)
	next.assignments[id] = {"status": "active", "kind": mission_definition(id).kind, "completion_count": count, "history_id": mission.history_id if not mission.history_id.is_empty() else id}
	if mission_definition(id).kind == "balloons":
		next.assignments[id].balloon_revision = 2
		next.assignments[id].started = false
	if mission.kind == "follow":
		next.assignments[id].visible_time = 0.0
		next.assignments[id].near_time = 0.0
	next.tracked_mission = id
	var result := _commit(next)
	if result.ok:
		result.message = ("已重新接取并追踪（不再发奖）：" if count > 0 else "已领取并追踪：") + mission_definition(id).display_name
		feedback.emit("accept")
	return result

func track_mission(id: String) -> Dictionary:
	if not id.is_empty() and (mission_definition(id) == null or mission_status(id) != "active"):
		return {"ok": false, "message": "请先领取尚未完成的任务"}
	var next := data.duplicate(true)
	next.tracked_mission = id
	return _commit(next)

func complete_mission(id: String, evidence: Dictionary = {}) -> Dictionary:
	if mission_definition(id) == null:
		return {"ok": false, "message": "任务不存在"}
	var mission := mission_definition(id)
	if mission_status(id) != "active" and mission_status(id) != "completed":
		return {"ok": false, "message": "请先领取任务"}
	if mission_status(id) != "completed" and mission.kind == "photo":
		var photo_path: String = evidence.get("photo_path", "")
		if not FileAccess.file_exists(photo_path) or photo_path.get_extension().to_lower() != "png" or Image.load_from_file(photo_path).is_empty():
			return {"ok": false, "message": "有效照片尚未保存，任务未完成"}
		var parser := JSON.new()
		var metadata_path := photo_path.get_basename() + ".json"
		if not FileAccess.file_exists(metadata_path) or parser.parse(FileAccess.get_file_as_string(metadata_path)) != OK or not parser.data is Dictionary:
			return {"ok": false, "message": "照片记录无法读取，任务未完成"}
		var metadata: Dictionary = parser.data
		var assessment: Variant = metadata.get("photo_check", {})
		if not assessment is Dictionary:
			return {"ok": false, "message": "照片条件记录无效"}
		var distance: Variant = assessment.get("distance", -1)
		var angle: Variant = assessment.get("angle", -1)
		if metadata.get("mission_id", "") != id or assessment.get("ok", false) != true or not (distance is float or distance is int) or not is_finite(float(distance)) or float(distance) < mission.min_distance or float(distance) > mission.max_distance or not (angle is float or angle is int) or not is_finite(float(angle)) or float(angle) < 0 or float(angle) > mission.max_angle_deg:
			return {"ok": false, "message": "照片不符合当前委托"}
	if mission.generated and mission_status(id) != "completed":
		if mission.kind in FlightChallengeRules.KINDS and not FlightChallengeRules.finished(mission, data.assignments[id]):
			return {"ok": false, "message": "请完成实际挑战目标"}
		if mission.kind in ["courier", "circuit"] and int(data.assignments[id].get("stage", 0)) < mission.checkpoints.size():
			return {"ok": false, "message": "请按顺序完成所有航点"}
		var seconds := float(evidence.get("seconds", 0))
		if mission.kind in ["survey", "hold_interact"] and (not is_finite(seconds) or seconds < mission.hold_seconds or not _near_evidence(evidence, mission.target_point, mission.interaction_radius, mission.max_speed)):
			return {"ok": false, "message": "尚未完成现场目标"}
	return _complete_mission(mission, mission.facility_id, evidence)

func _near_evidence(evidence: Dictionary, target: Vector3, radius: float, max_speed: float) -> bool:
	var point: Variant = evidence.get("point")
	var speed := float(evidence.get("speed", INF))
	return point is Vector3 and point.is_finite() and point.distance_to(target) <= radius and is_finite(speed) and speed <= max_speed

func advance_mission(id: String, point: Vector3, speed: float, interacting: bool) -> Dictionary:
	var mission := mission_definition(id)
	if mission == null or not mission.generated or mission.kind not in ["courier", "circuit"] or mission_status(id) != "active":
		return {"ok": false, "message": "没有进行中的分段目标"}
	var stage := int(data.assignments[id].get("stage", 0))
	if stage >= mission.checkpoints.size():
		return {"ok": true, "message": "航点已完成"}
	if not _near_evidence({"point": point, "speed": speed}, mission.checkpoints[stage], mission.interaction_radius, mission.max_speed) or (mission.kind == "courier" and not interacting):
		return {"ok": false, "message": "请到当前目标低速交互"}
	var next := data.duplicate(true)
	next.assignments[id].stage = stage + 1
	return _commit(next)

func _complete_mission(mission: MissionDefinition, instance_id: String, evidence: Dictionary) -> Dictionary:
	var transaction := "mission:" + instance_id if not instance_id.is_empty() else mission.transaction_id()
	if mission_status(mission.id) == "completed" or (data.transactions.has(transaction) and mission_status(mission.id) != "active"):
		return {"ok": true, "message": "任务已经完成，奖励已领取", "duplicate": true}
	var reward: RewardDefinition = catalog.entries.get(mission.reward_id) as RewardDefinition
	if reward == null or reward.mission_tag != mission.mission_tag or reward.city_tag != mission.city_tag:
		return {"ok": false, "message": "任务和奖励条件不匹配"}
	var next := data.duplicate(true)
	var first_completion: bool = not mission_completed_once(mission.id) and not data.transactions.has(transaction)
	if first_completion:
		for id: String in reward.grants:
			if not next.owned.has(id):
				next.owned.append(id)
		next.credits += reward.credits
	if not instance_id.is_empty():
		next.facilities[instance_id] = true
		next.missions[instance_id] = true
	var count := int(data.assignments.get(mission.id, {}).get("completion_count", 0))
	next.assignments[mission.id] = {"status": "completed", "kind": mission.kind, "completion_count": mini(999999999, (count if first_completion else maxi(1, count)) + 1), "photo_path": evidence.get("photo_path", "")}
	next.assignments[mission.id].history_id = mission.history_id if not mission.history_id.is_empty() else mission.id
	AchievementBook.completed(next, mission.kind)
	if next.tracked_mission == mission.id:
		next.tracked_mission = ""
	if not next.transactions.has(transaction):
		next.transactions.append(transaction)
	var revealed_title := ""
	var restored_portals: Array[String] = []
	if regions is BiomeWorld and mission.generated:
		var fields := mission.id.split(":")
		var p: Dictionary = regions.instance(":".join([fields[2], fields[3], fields[4]]))
		var requirements: Array = p.get("portal_requirements", [])
		var repaired := not requirements.is_empty()
		for required: String in requirements:
			var definition := mission_definition(required)
			repaired = repaired and (next.assignments.get(required, {}).get("completion_count", 0) > 0 or (definition != null and next.transactions.has(definition.transaction_id())))
		if repaired:
			for station: Dictionary in p.stations:
				if not next.exploration.portals.has(station.id):
					restored_portals.append(station.name)
				next.exploration.portals[station.id] = true
		if not p.is_empty() and regions.map_task(p) == mission.id:
			if not next.exploration.mapped.has(p.id):
				revealed_title = p.biomes[0].display_name
			next.exploration.visited[p.id] = true
			next.exploration.mapped[p.id] = true
			AchievementBook.biome(next, p.biomes[0].id, catalog)
	var result := _commit(next)
	if result.ok:
		for title in restored_portals:
			unlocked.emit("portal", title + " · 三条修复线路已恢复")
		if not revealed_title.is_empty():
			unlocked.emit("region", revealed_title)
		if mission.kind != "race":
			feedback.emit("complete")
		result.message = ("%s已完成 · +%d 信用点%s" % [mission.display_name, reward.credits, " · 装备权限已解锁" if not reward.grants.is_empty() else ""]) if first_completion else mission.display_name + "再次完成 · 首次奖励已领取，本次不发放奖励"
	return result

func save_challenge_state(id: String, state: Dictionary, track: bool = false) -> Dictionary:
	var mission := mission_definition(id)
	if mission == null or mission_status(id) != "active" or not FlightChallengeRules.valid_state(mission, state):
		return {"ok": false, "message": "挑战进度无效"}
	var next := data.duplicate(true)
	next.assignments[id] = state.duplicate(true)
	next.assignments[id].completion_count = int(data.assignments[id].get("completion_count", 0))
	next.assignments[id].history_id = mission.history_id if not mission.history_id.is_empty() else id
	if track:
		next.tracked_mission = id
	if mission.kind == "balloons":
		next.assignments[id].balloon_revision = 2
		if state.get("failed", false):
			next.assignments[id].status = "failed"
			if next.tracked_mission == id:
				next.tracked_mission = ""
	return _commit(next)

func purchase(offer_id: String, city_tag: String) -> Dictionary:
	if not catalog.entries.has(offer_id) or not catalog.entries[offer_id] is OfferDefinition:
		return {"ok": false, "message": "商品不存在"}
	var offer: OfferDefinition = catalog.entries[offer_id]
	if offer.city_tag != city_tag:
		return {"ok": false, "message": "该商店不出售这件配件"}
	var target := offer.preset_id if not offer.preset_id.is_empty() else offer.part_id
	if data.owned.has(target):
		return {"ok": false, "message": "已经永久取得，无需再次购买"}
	if int(data.credits) < offer.price:
		return {"ok": false, "message": "信用点不足，完成探索委托可取得信用点"}
	var next := data.duplicate(true)
	next.credits -= offer.price
	var grants: Array[String] = [target]
	if not offer.preset_id.is_empty():
		var preset: DronePresetDefinition = catalog.presets[offer.preset_id]
		grants.append_array([preset.frame_id, preset.motor_set_id, preset.propeller_set_id])
	for id: String in grants:
		if not next.owned.has(id):
			next.owned.append(id)
	next.transactions.append("offer:" + offer.id)
	var result := _commit(next)
	if result.ok:
		result.message = "已取得 " + offer.display_name
		feedback.emit("purchase")
	return result

func save_build(build: Dictionary) -> Dictionary:
	return save_loadout(build, data.settings)

func save_loadout(build: Dictionary, settings: Dictionary) -> Dictionary:
	if settings.has("input_display") and not InputDisplay.valid(settings.input_display):
		return {"ok": false, "message": "操作预览参数无效，未保存。"}
	if settings.has("audio") and not GameAudioSettings.valid(settings.audio):
		return {"ok": false, "message": "声音参数无效，未保存。"}
	if settings.has("flight") and not FlightTuning.valid(settings.flight):
		return {"ok": false, "message": "飞行参数无效，未保存。"}
	var resolved := DroneAssembler.new(catalog).resolve(build, data.owned)
	if not resolved.ok:
		return {"ok": false, "message": " / ".join(resolved.errors)}
	var next := data.duplicate(true)
	next.build = resolved.build
	next.settings = settings.duplicate(true)
	return _commit(next)

func save_deployment(point: Vector3) -> Dictionary:
	var next := data.duplicate(true)
	next.deployment = [point.x, point.y, point.z]
	return _commit(next)

func save_settings(settings: Dictionary) -> Dictionary:
	if settings.has("input_display") and not InputDisplay.valid(settings.input_display):
		return {"ok": false, "message": "操作预览参数无效，未保存。"}
	if settings.has("audio") and not GameAudioSettings.valid(settings.audio):
		return {"ok": false, "message": "声音参数无效，未保存。"}
	if settings.has("flight") and not FlightTuning.valid(settings.flight):
		return {"ok": false, "message": "飞行参数无效，未保存。"}
	var next := data.duplicate(true)
	next.settings = settings.duplicate(true)
	return _commit(next)

# A world-independent safety copy. The profile remains the transactional source;
# the mirror is only updated after a successful profile commit.
func _mirror_controls() -> void:
	if data.settings.is_empty():
		return
	var target := path.get_base_dir().path_join("controls.json")
	var file := FileAccess.open(target + ".pending", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(data.settings, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(target + ".pending"), ProjectSettings.globalize_path(target))

func _restore_controls() -> void:
	var settings: Dictionary = data.settings.duplicate(true)
	# Recover radio profiles from the independent copy or an older valid snapshot.
	for source: String in [path.get_base_dir().path_join("controls.json"), path + ".backup", path + ".world-v1.backup"]:
		if not FileAccess.file_exists(source):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
		if not value is Dictionary:
			continue
		var saved: Variant = value.get("settings", value)
		if not saved is Dictionary:
			continue
		if settings.is_empty():
			settings = saved.duplicate(true)
		elif not settings.get("radio_profiles_managed", false) and settings.get("radio_profiles", {}).is_empty() and saved.get("radio_profiles", {}) is Dictionary and not saved.get("radio_profiles", {}).is_empty():
			for key: String in ["radio_profiles", "active_radio_profile", "radio_active"]:
				if saved.has(key):
					settings[key] = saved[key]
	data.settings = settings
	if writable:
		_mirror_controls()

func visit_region(id: String) -> Dictionary:
	if not regions is BiomeWorld:
		return {"ok": false, "message": "当前世界不支持探索记录"}
	var p: Dictionary = regions.instance(id)
	if p.is_empty():
		return {"ok": false, "message": "地区不存在"}
	var task: String = regions.map_task(p)
	var mapped := task.is_empty() or mission_completed_once(task)
	if data.exploration.visited.has(id) and (not mapped or data.exploration.mapped.has(id)):
		return {"ok": true, "changed": false}
	var next := data.duplicate(true)
	next.exploration.visited[id] = true
	if mapped:
		next.exploration.mapped[id] = true
		AchievementBook.biome(next, p.biomes[0].id, catalog)
	var result := _commit(next)
	result.changed = result.ok
	if result.ok:
		unlocked.emit("region" if mapped else "discovery", p.biomes[0].display_name)
	result.message = "地图已解锁：" + p.biomes[0].display_name if mapped else "进入未测绘地区 · 打开地图领取解锁任务"
	return result

func portal_unlocked(id: String) -> bool:
	if not data.get("exploration", {}).get("portals", {}).has(id):
		return false
	return portal_repair_status(id).remaining == 0

func portal_repair_status(id: String) -> Dictionary:
	var fields := id.split(":")
	var requirements: Array = []
	if fields.size() == 5 and fields[0] == "v4" and regions is BiomeWorld:
		requirements = regions.instance(":".join([fields[1], fields[2], fields[3]])).get("portal_requirements", [])
	var remaining := 0
	for required: String in requirements:
		remaining += int(not mission_completed_once(required))
	return {"remaining": remaining, "total": requirements.size()}

func unlock_portal(id: String) -> Dictionary:
	if portal_unlocked(id):
		return {"ok": true, "changed": false}
	var fields := id.split(":")
	if fields.size() != 5 or fields[0] != "v4" or not regions is BiomeWorld:
		return {"ok": false, "message": "平台不存在"}
	var p: Dictionary = regions.instance(":".join([fields[1], fields[2], fields[3]]))
	var found := false
	for station: Dictionary in p.get("stations", []):
		found = found or station.id == id
	if not found:
		return {"ok": false, "message": "平台不存在"}
	var repair := portal_repair_status(id)
	if repair.remaining > 0:
		return {"ok": false, "message": "当地传送网络离线 · 修复线路 %d/%d，完成全部线路后自动解锁" % [repair.total - repair.remaining, repair.total]}
	var next := data.duplicate(true)
	next.exploration.portals[id] = true
	var result := _commit(next)
	result.changed = result.ok
	if result.ok:
		for station: Dictionary in p.stations:
			if station.id == id:
				unlocked.emit("portal", station.name)
	return result
