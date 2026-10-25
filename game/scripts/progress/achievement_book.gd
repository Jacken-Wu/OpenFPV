class_name AchievementBook
extends RefCounted
const TYPES := {"hold_interact": "信标交互", "photo": "摄影", "survey": "勘测", "courier": "快递", "race": "航线挑战", "balloons": "扎气球", "orbit": "环绕运镜", "follow": "移动跟拍", "regional": "区域解密"}

static func prepare(data: Dictionary) -> void:
	if not data.has("achievements"):
		data.achievements = {"unlocked": {}, "biomes": {}, "types": {}}

static func biome(data: Dictionary, id: String, catalog: ContentCatalog) -> void:
	prepare(data)
	for definition in catalog.biomes:
		if id == definition.id or id.begins_with(definition.id + ":"):
			data.achievements.biomes[definition.id] = true

static func completed(data: Dictionary, kind: String) -> void:
	prepare(data)
	data.achievements.types["race" if kind == "circuit" else kind] = true

static func counts(data: Dictionary, catalog: ContentCatalog) -> Dictionary:
	prepare(data)
	var completed_ids := {}
	for id: String in data.get("assignments", {}):
		var assignment: Dictionary = data.assignments[id]
		if assignment.get("status") == "completed" or int(assignment.get("completion_count", 0)) > 0:
			completed_ids[assignment.get("history_id", id)] = true
	var missions := completed_ids.size()
	var presets := 0
	for preset: DronePresetDefinition in catalog.presets.values():
		presets += int(data.owned.has(preset.id) and data.owned.has(preset.frame_id) and data.owned.has(preset.motor_set_id) and data.owned.has(preset.propeller_set_id))
	var biomes := 0
	for definition in catalog.biomes:
		biomes += int(data.achievements.biomes.has(definition.id))
	var types := 0
	for kind: String in TYPES:
		types += int(data.achievements.types.has(kind))
	return {"missions": missions, "portals": data.exploration.portals.size(), "biomes": biomes, "mission_types": types, "presets": presets}

static func target(definition: AchievementDefinition, catalog: ContentCatalog) -> int:
	return definition.target if definition.target > 0 else catalog.biomes.size() if definition.metric == "biomes" else TYPES.size()

static func award(data: Dictionary, catalog: ContentCatalog) -> Array[String]:
	var progress := counts(data, catalog)
	var unlocked: Array[String] = []
	for definition: AchievementDefinition in catalog.manifest.achievements:
		if progress[definition.metric] >= target(definition, catalog) and not data.achievements.unlocked.has(definition.id):
			data.achievements.unlocked[definition.id] = Time.get_datetime_string_from_system()
			unlocked.append(definition.display_name)
	return unlocked
