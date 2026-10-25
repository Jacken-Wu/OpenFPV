class_name ContentCatalog
extends RefCounted

const MANIFEST_PATH := "res://content/base/manifest.tres"
var manifest: ContentManifest
var entries: Dictionary = {}
var parts: Dictionary = {}
var presets: Dictionary = {}
var biomes: Array[BiomeDefinition] = []
var maps: Dictionary = {}
var missions: Dictionary = {}
var errors: Array[String] = []

func _init(source: ContentManifest = null) -> void:
	manifest = load(MANIFEST_PATH) as ContentManifest if source == null else source
	if manifest == null:
		errors.append("内容清单无法加载")
		return
	for collection: Array in [manifest.parts, manifest.presets, manifest.propulsion_maps, manifest.biomes, manifest.rewards, manifest.offers, manifest.missions, manifest.mission_templates, manifest.challenge_templates, manifest.achievements]:
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
			if item.music != null and (not item.music is AudioStreamWAV or item.music.loop_mode != AudioStreamWAV.LOOP_FORWARD or item.music_title.is_empty()):
				errors.append(item.id + ": 群系音乐需要标题和可循环 WAV")
			_validate_architecture(item)
			_validate_region_features(item)
			if item.palette.size() < 3 or item.region_bounds.size.x <= 0 or item.region_bounds.size.y <= 0 or item.region_bounds.size.z <= 0:
				errors.append(item.id + ": 群系需要三个颜色和有效的三维包围盒")
			if item.provider_id not in ["base.generator.modular_city", "base.generator.canyon", "base.generator.sky_island", "base.generator.underground", "base.generator.pine_valley"] or item.parameters.get("layer", "") not in ["surface", "volume"] or not item.region_bounds.position.is_finite() or not item.region_bounds.size.is_finite():
				errors.append(item.id + ": 提供者、层或三维范围无效")
			if item.provider_id == "base.generator.modular_city":
				var minimum := float(item.parameters.get("building_min", -1))
				var maximum := float(item.parameters.get("building_max", -1))
				if not is_finite(minimum) or not is_finite(maximum) or minimum < 4 or maximum < minimum or maximum > 48 or item.parameters.get("architecture", "industrial") not in ["industrial", "garden", "oldtown"]:
					errors.append(item.id + ": 建筑高度或风格无效")
		elif item is MissionDefinition:
			if manifest.missions.has(item):
				missions[id] = item
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
		elif parts[mapping.motor_id].kind != "motor_set" or parts[mapping.propeller_id].kind != "propeller_set" or float(parts[mapping.motor_id].stats.get("shaft_mm", -1)) != float(parts[mapping.propeller_id].stats.get("shaft_mm", -2)):
			errors.append(mapping.id + ": 动力映射的配件类型或桨轴不兼容")
	for reward: RewardDefinition in manifest.rewards:
		if reward.credits < 0:
			errors.append(reward.id + ": 信用点无效")
		for target: String in reward.grants:
			if not entries.has(target):
				errors.append(reward.id + ": 未知奖励 " + target)
	for offer: OfferDefinition in manifest.offers:
		if (not parts.has(offer.part_id) and not presets.has(offer.preset_id)) or (not offer.part_id.is_empty() and not offer.preset_id.is_empty()) or offer.price < 0:
			errors.append(offer.id + ": 商店内容无效")
	for achievement: AchievementDefinition in manifest.achievements:
		if achievement.display_name.is_empty() or achievement.metric not in ["missions", "portals", "biomes", "mission_types", "presets"] or achievement.target < 0 or (achievement.target == 0 and achievement.metric not in ["biomes", "mission_types"]):
			errors.append(achievement.id + ": 成就条件无效")
	for template: MissionDefinition in manifest.mission_templates + manifest.challenge_templates:
		var reward: Resource = entries.get(template.reward_id)
		if template.kind not in ["hold_interact", "photo", "survey", "circuit", "courier", "race", "balloons", "orbit", "follow"] or template.display_name.is_empty() or not reward is RewardDefinition or reward.mission_tag != template.mission_tag or reward.city_tag != template.city_tag or not is_finite(template.interaction_radius) or template.interaction_radius <= 0 or not is_finite(template.hold_seconds) or template.hold_seconds <= 0 or not is_finite(template.max_speed) or template.max_speed < 0:
			errors.append(template.id + ": 生成任务模板无效")
		if template.kind == "photo" and (not is_finite(template.min_distance) or not is_finite(template.max_distance) or not is_finite(template.max_angle_deg) or template.min_distance <= 0 or template.max_distance < template.min_distance or template.max_angle_deg <= 0 or template.max_angle_deg > 60):
			errors.append(template.id + ": 摄影模板参数无效")
	if manifest.world_version >= 3 and manifest.mission_templates.is_empty():
		errors.append("种子世界需要任务模板池")
	if manifest.world_version >= 4:
		for field: String in ["surface_spacing", "warp", "sky_spacing", "sky_chance", "maze_spacing", "maze_chance"]:
			var value: Variant = manifest.generation_rules.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0 or (field.ends_with("_spacing") and float(value) < 512) or (field.ends_with("_chance") and float(value) > 1):
				errors.append("生成规则无效: " + field)
		for biome in biomes:
			if biome.parameters.get("map_unlock", "visit") not in ["visit", "mission"]:
				errors.append(biome.id + ": 地图解锁规则无效")
			if biome.parameters.layer == "surface":
				var climate: Variant = biome.parameters.get("climate")
				if not climate is Vector3 or not climate.is_finite():
					errors.append(biome.id + ": 气候参数无效")
	if not presets.has(manifest.initial_preset_id):
		errors.append("初始套机不存在")
	var navigation := MapNavigation.new()
	var transactions: Array[String] = []
	for mission: MissionDefinition in missions.values():
		if not mission.kind in ["hold_interact", "photo"] or mission.display_name.is_empty() or navigation.find_location(mission.location_id) == null:
			errors.append(mission.id + ": 任务类型、标题或地图地点无效")
		var reward: Resource = entries.get(mission.reward_id)
		if not reward is RewardDefinition or reward.mission_tag != mission.mission_tag or reward.city_tag != mission.city_tag:
			errors.append(mission.id + ": 奖励引用或任务/城市条件不匹配")
		if transactions.has(mission.transaction_id()):
			errors.append(mission.id + ": 重复任务事务")
		transactions.append(mission.transaction_id())
		if not mission.target_point.is_finite():
			errors.append(mission.id + ": 三维目标无效")
		if mission.kind == "hold_interact":
			if mission.facility_id.is_empty() or not is_finite(mission.hold_seconds) or mission.hold_seconds <= 0 or not is_finite(mission.interaction_radius) or mission.interaction_radius <= 0 or not is_finite(mission.max_speed) or mission.max_speed < 0:
				errors.append(mission.id + ": 交互参数无效")
		elif not is_finite(mission.min_distance) or not is_finite(mission.max_distance) or mission.min_distance <= 0 or mission.max_distance < mission.min_distance or not is_finite(mission.max_angle_deg) or mission.max_angle_deg <= 0 or mission.max_angle_deg > 60 or not mission.target_bounds.position.is_finite() or not mission.target_bounds.size.is_finite() or not mission.target_bounds.has_volume() or not mission.target_bounds.has_point(mission.target_point):
			errors.append(mission.id + ": 拍摄范围、角度或目标体积无效")

func sorted_ids() -> Array:
	var result := entries.keys()
	result.sort()
	return result

func _validate_architecture(biome: BiomeDefinition) -> void:
	for key: String in ["lot_pool", "landmark_pool"]:
		if not biome.parameters.get(key, []) is Array:
			errors.append(biome.id + ": 建筑池必须为数组")
			return
	for kind: Variant in biome.parameters.get("lot_pool", []):
		if not kind is String or not Architecture.TYPES.has(kind):
			errors.append(biome.id + ": 未知城市建筑")
	for rule: Variant in biome.parameters.get("landmark_pool", []):
		if not rule is Dictionary or not Architecture.TYPES.has(rule.get("kind", "")) or not (rule.get("chance") is float or rule.get("chance") is int):
			errors.append(biome.id + ": 特色建筑规则无效")
		elif not is_finite(float(rule.chance)) or float(rule.chance) < 0 or float(rule.chance) > 1:
			errors.append(biome.id + ": 特色建筑概率超出0～1")
		elif not FlightInput.valid_index(rule.get("count", 1), 7) or int(rule.get("count", 1)) < 1:
			errors.append(biome.id + ": 特色建筑数量应为1～6")

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

func _validate_region_features(biome: BiomeDefinition) -> void:
	if biome.parameters.get("feature_profile", "") not in ["", "ruined_grid", "honeycomb_rocks", "megastructure", "volcanic_causeway"] or not biome.parameters.get("caves", false) is bool:
		errors.append(biome.id + ": 区域结构参数无效")
	var rules: Variant = biome.parameters.get("regional_tasks", [])
	if not rules is Array or rules.size() > 3:
		errors.append(biome.id + ": 区域任务需要不超过三条定义")
		return
	var titles := {}
	for rule: Variant in rules:
		if not rule is Dictionary or rule.get("mode", "") not in ["repair", "sequence", "clean"] or not rule.get("title", "") is String or String(rule.get("title", "")).is_empty() or not rule.get("description", "") is String or not rule.get("portal_required", false) is bool:
			errors.append(biome.id + ": 区域任务定义无效")
			continue
		if titles.has(rule.title): errors.append(biome.id + ": 区域任务名称重复")
		titles[rule.title] = true

func fingerprint() -> String:
	var records := PackedStringArray([manifest.content_version, str(manifest.world_version)])
	records.append("generation_rules:" + var_to_str(manifest.generation_rules))
	for id: String in sorted_ids():
		var item: Resource = entries[id]
		records.append(id)
		var fields: Array[String] = []
		for property: Dictionary in item.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and property.name != "script":
				fields.append(property.name)
		fields.sort()
		for field: String in fields:
			if field == "music" and item is BiomeDefinition:
				var stream: AudioStreamWAV = item.music as AudioStreamWAV
				if stream != null:
					var digest := HashingContext.new()
					digest.start(HashingContext.HASH_SHA256)
					digest.update(stream.data)
					records.append("music:" + stream.resource_path + ":" + digest.finish().hex_encode() + ":%d:%d:%d" % [stream.mix_rate, stream.loop_begin, stream.loop_end])
				else:
					records.append("music:null")
			else:
				records.append(field + ":" + var_to_str(item.get(field)))
	return "\n".join(records).sha256_text()
