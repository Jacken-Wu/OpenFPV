class_name DroneAssembler
extends RefCounted

var catalog: ContentCatalog
const SLOTS := {"frame": "frame_id", "motor_set": "motor_set_id", "propeller_set": "propeller_set_id"}

func _init(content: ContentCatalog) -> void:
	catalog = content

func from_preset(id: String) -> Dictionary:
	if not catalog.presets.has(id):
		return {}
	var preset: DronePresetDefinition = catalog.presets[id]
	return {"frame_id": preset.frame_id, "motor_set_id": preset.motor_set_id, "propeller_set_id": preset.propeller_set_id, "tuning": {}}

func resolve(build: Dictionary, owned: Array, allow_locked: bool = false) -> Dictionary:
	var issues: Array[String] = []
	var selected: Dictionary = {}
	for slot: String in SLOTS:
		var id := String(build.get(SLOTS[slot], ""))
		if not catalog.parts.has(id):
			issues.append("未知配件: " + id)
			continue
		var part: PartDefinition = catalog.parts[id]
		if part.kind != slot:
			issues.append("配件安装位置错误: " + part.display_name)
		if not allow_locked and not owned.has(id):
			issues.append("尚未取得: " + part.display_name)
		selected[slot] = part
	if not issues.is_empty():
		return {"ok": false, "errors": issues}
	var tuning: Dictionary = build.get("tuning", {})
	var values: Dictionary = {}
	for slot: String in tuning:
		if not SLOTS.has(slot):
			issues.append("未知调参槽位: " + slot)
	for slot: String in SLOTS:
		var part: PartDefinition = selected[slot]
		var requested: Dictionary = tuning.get(slot, {})
		values[slot] = {}
		for key: String in requested:
			if not part.tuning.has(key):
				issues.append("未知参数: " + key)
		for key: String in part.tuning:
			var rule: Dictionary = part.tuning[key]
			var value := float(requested.get(key, rule.default))
			if not valid_tuning(value, rule):
				issues.append(part.display_name + "/" + key + ": 超出范围或步长无效")
			values[slot][key] = value
	var frame: PartDefinition = selected.frame
	var motor: PartDefinition = selected.motor_set
	var prop: PartDefinition = selected.propeller_set
	if frame.stats.mount != motor.stats.mount:
		issues.append("电机安装孔与机架不匹配")
	if float(motor.stats.shaft_mm) != float(prop.stats.shaft_mm):
		issues.append("桨叶轴孔不匹配")
	if float(prop.stats.diameter_inches) > float(frame.stats.max_prop_inches):
		issues.append("桨径超过机架净空")
	var pair := motor.id + "|" + prop.id
	if not catalog.maps.has(pair):
		issues.append("该电机与桨叶没有匹配动力数据")
	if not issues.is_empty():
		return {"ok": false, "errors": issues}
	var mapping: PropulsionMapDefinition = catalog.maps[pair]
	var weight := frame.mass_per_component_kg + motor.mass_per_component_kg * 4 + prop.mass_per_component_kg * 4 + float(frame.stats.system_mass)
	var arm := float(frame.stats.arm)
	var thrust := mapping.max_thrust_n * float(values.propeller_set.get("aero_trim", 1.0))
	if not is_finite(weight) or weight <= 0 or arm <= 0 or thrust * 4.0 / (weight * 9.81) < 2.0:
		return {"ok": false, "errors": ["整机质量或推力余量不符合要求"]}
	var inertia_x := maxf(0.0005, weight * arm * arm * 0.52)
	var specification := {"mass": weight, "arm": arm, "inertia": Vector3(inertia_x, inertia_x * 1.7, inertia_x), "max_thrust": thrust, "response": mapping.response_s * float(values.motor_set.get("response_trim", 1.0)), "torque_ratio": mapping.torque_ratio_m, "drag": float(frame.stats.drag), "camera_tilt": float(values.frame.get("camera_mount_tilt_deg", 20.0)), "name": frame.display_name, "thrust_weight": thrust * 4.0 / (weight * 9.81)}
	var normalized := build.duplicate(true)
	normalized.tuning = values
	return {"ok": true, "errors": [], "spec": specification, "build": normalized}

static func valid_tuning(value: float, rule: Dictionary) -> bool:
	if not is_finite(value) or value < float(rule.min) - 0.00001 or value > float(rule.max) + 0.00001:
		return false
	var steps := (value - float(rule.min)) / float(rule.step)
	return absf(steps - roundf(steps)) < 0.0001
