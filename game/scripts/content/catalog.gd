class_name ContentCatalog
extends RefCounted

const MANIFEST_PATH := "res://content/base/manifest.tres"
var manifest: ContentManifest
var entries: Dictionary = {}
var parts: Dictionary = {}
var presets: Dictionary = {}
var biomes: Array[BiomeDefinition] = []
var maps: Dictionary = {}
var errors: Array[String] = []

func _init(source: ContentManifest = null) -> void:
	manifest = load(MANIFEST_PATH) as ContentManifest if source == null else source
	if manifest == null:
		errors.append("内容清单无法加载")
		return
	for collection: Array in [manifest.parts, manifest.presets, manifest.propulsion_maps, manifest.biomes, manifest.rewards, manifest.offers]:
		for item: Resource in collection:
			if item == null or String(item.get("id")).is_empty():
				errors.append("内容 ID 不能为空")
				continue
			var id: String = item.id
			if entries.has(id):
				errors.append("重复内容 ID: " + id)
				continue
			entries[id] = item
	for id: String in sorted_ids():
		var item: Resource = entries[id]
		if item is PartDefinition:
			parts[id] = item
			_validate_part(item)
		elif item is DronePresetDefinition:
			presets[id] = item
		elif item is BiomeDefinition:
			biomes.append(item)
			if item.palette.size() < 3 or item.region_bounds.size.x <= 0 or item.region_bounds.size.y <= 0 or item.region_bounds.size.z <= 0:
				errors.append(item.id + ": 群系需要三个颜色和有效的三维包围盒")
		elif item is PropulsionMapDefinition:
			var pair: String = item.motor_id + "|" + item.propeller_id
			if maps.has(pair):
				errors.append("重复动力组合: " + pair)
			maps[pair] = item
			if not is_finite(item.max_thrust_n) or not is_finite(item.response_s) or not is_finite(item.torque_ratio_m) or item.max_thrust_n <= 0 or item.response_s <= 0 or item.torque_ratio_m <= 0:
				errors.append(id + ": 动力参数无效")
	for preset: DronePresetDefinition in presets.values():
		for part_id: String in [preset.frame_id, preset.motor_set_id, preset.propeller_set_id]:
			if not parts.has(part_id):
				errors.append(preset.id + ": 缺少配件 " + part_id)
	for mapping: PropulsionMapDefinition in maps.values():
		if not parts.has(mapping.motor_id) or not parts.has(mapping.propeller_id):
			errors.append(mapping.id + ": 动力映射引用不存在")
	for reward: RewardDefinition in manifest.rewards:
		if reward.credits < 0:
			errors.append(reward.id + ": 信用点无效")
		for target: String in reward.grants:
			if not entries.has(target):
				errors.append(reward.id + ": 未知奖励 " + target)
	for offer: OfferDefinition in manifest.offers:
		if not parts.has(offer.part_id) or offer.price < 0:
			errors.append(offer.id + ": 商店内容无效")
	if not presets.has(manifest.initial_preset_id):
		errors.append("初始套机不存在")

func sorted_ids() -> Array:
	var result := entries.keys()
	result.sort()
	return result

func _validate_part(part: PartDefinition) -> void:
	if not ["frame", "motor_set", "propeller_set"].has(part.kind) or not is_finite(part.mass_per_component_kg) or part.mass_per_component_kg <= 0:
		errors.append(part.id + ": 配件类型或质量无效")
	if part.component_count != (1 if part.kind == "frame" else 4):
		errors.append(part.id + ": 组件数量不符合四旋翼")
	var fields: Array = {"frame": ["arm", "max_prop_inches", "system_mass", "drag", "mount"], "motor_set": ["mount", "shaft_mm"], "propeller_set": ["diameter_inches", "shaft_mm"]}.get(part.kind, [])
	for field: String in fields:
		if not part.stats.has(field):
			errors.append(part.id + ": 缺少规格 " + field)
		elif field == "mount":
			if not part.stats[field] is String or String(part.stats[field]).is_empty():
				errors.append(part.id + ": 安装孔规格无效")
		elif not is_finite(float(part.stats[field])) or float(part.stats[field]) <= 0:
			errors.append(part.id + ": 规格无效 " + field)
	for key: String in part.tuning:
		var rule: Dictionary = part.tuning[key]
		for field: String in ["min", "max", "default", "step"]:
			if not rule.has(field) or not is_finite(float(rule[field])):
				errors.append(part.id + "/" + key + ": 缺少有效参数范围")
		if rule.has_all(["min", "max", "default", "step"]):
			if float(rule.min) > float(rule.default) or float(rule.default) > float(rule.max) or float(rule.step) <= 0:
				errors.append(part.id + "/" + key + ": 参数范围无效")

func fingerprint() -> String:
	var records := PackedStringArray([manifest.content_version, str(manifest.world_version)])
	for id: String in sorted_ids():
		var item: Resource = entries[id]
		records.append(id)
		var fields: Array[String] = []
		for property: Dictionary in item.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":
				fields.append(property.name)
		fields.sort()
		for field: String in fields:
			records.append(field + ":" + var_to_str(item.get(field)))
	return "\n".join(records).sha256_text()
