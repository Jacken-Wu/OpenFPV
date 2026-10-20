class_name ProgressStore
extends RefCounted
## Commit a complete snapshot before exposing rewards or spending credits.

var catalog: ContentCatalog
var path: String
var data: Dictionary = {}
var warning := ""
var writable := true

func _init(content: ContentCatalog, save_path: String = "user://profile/progress.json") -> void:
	catalog = content
	path = save_path
	data = _new_profile()
	if FileAccess.file_exists(path):
		var loaded := _read(path)
		if loaded.is_empty():
			loaded = _read(path + ".backup")
			warning = "主存档损坏，已读取备份。" if not loaded.is_empty() else "存档无法读取，已进入临时档；原文件保留。"
			writable = not loaded.is_empty()
		if not loaded.is_empty():
			data = loaded
			for initial_id: String in _new_profile().owned:
				if not data.owned.has(initial_id):
					data.owned.append(initial_id)
			if int(data.world_version) != catalog.manifest.world_version:
				writable = false
				warning = "世界版本不匹配，暂不覆盖原存档。"
			elif String(data.content_fingerprint) != catalog.fingerprint():
				warning = "内容已更新；旧取得记录保留，失效装配会回退初始套机。"

func _new_profile() -> Dictionary:
	var initial: DronePresetDefinition = catalog.presets[catalog.manifest.initial_preset_id]
	return {"schema": 1, "seed": 271828, "world_version": catalog.manifest.world_version,
		"content_fingerprint": catalog.fingerprint(), "credits": 0,
		"owned": [initial.id, initial.frame_id, initial.motor_set_id, initial.propeller_set_id],
		"transactions": [], "facilities": {}, "missions": {}, "settings": {},
		"build": DroneAssembler.new(catalog).from_preset(initial.id), "deployment": [0.0, 1.2, 16.0], "dimension": "world.main"}

func _read(source: String) -> Dictionary:
	if not FileAccess.file_exists(source):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(source)) != OK:
		return {}
	var value: Variant = parser.data
	if not value is Dictionary:
		return {}
	var record: Dictionary = value
	if not record.has_all(["schema", "seed", "world_version", "content_fingerprint", "credits", "owned", "transactions", "facilities", "missions", "settings", "build"]):
		return {}
	if int(record.schema) != 1 or not record.owned is Array or not record.transactions is Array:
		return {}
	for key: String in ["facilities", "missions", "settings", "build"]:
		if not record[key] is Dictionary:
			return {}
	if not (record.credits is float or record.credits is int) or not is_finite(float(record.credits)) or float(record.credits) < 0:
		return {}
	return record

func _commit(next: Dictionary) -> Dictionary:
	if not writable:
		return {"ok": false, "message": "存档受保护，操作未提交。"}
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
	return {"ok": true, "message": "已保存"}

func complete_relay(instance_id: String, mission_tag: String, city_tag: String) -> Dictionary:
	var transaction := "mission:" + instance_id
	if data.transactions.has(transaction):
		return {"ok": true, "message": "中继已经修复", "duplicate": true}
	var next := data.duplicate(true)
	var matched := false
	for reward: RewardDefinition in catalog.manifest.rewards:
		if reward.mission_tag == mission_tag and reward.city_tag == city_tag:
			matched = true
			for id: String in reward.grants:
				if not next.owned.has(id):
					next.owned.append(id)
			next.credits += reward.credits
	if not matched:
		return {"ok": false, "message": "任务和城市条件不匹配"}
	next.facilities[instance_id] = true
	next.missions[instance_id] = true
	next.transactions.append(transaction)
	var result := _commit(next)
	if result.ok:
		result.message = "中继已修复 · 闸门开启 · 解锁轻型套机及组件 · +200 信用点"
	return result

func purchase(offer_id: String, city_tag: String) -> Dictionary:
	if not catalog.entries.has(offer_id) or not catalog.entries[offer_id] is OfferDefinition:
		return {"ok": false, "message": "商品不存在"}
	var offer: OfferDefinition = catalog.entries[offer_id]
	if offer.city_tag != city_tag:
		return {"ok": false, "message": "该商店不出售这件配件"}
	if data.owned.has(offer.part_id):
		return {"ok": false, "message": "已经永久取得，无需再次购买"}
	if int(data.credits) < offer.price:
		return {"ok": false, "message": "信用点不足，先完成中继任务"}
	var next := data.duplicate(true)
	next.credits -= offer.price
	next.owned.append(offer.part_id)
	next.transactions.append("offer:" + offer.id)
	var result := _commit(next)
	if result.ok:
		result.message = "已取得 " + offer.display_name
	return result

func save_build(build: Dictionary) -> Dictionary:
	return save_loadout(build, data.settings)

func save_loadout(build: Dictionary, settings: Dictionary) -> Dictionary:
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
	var next := data.duplicate(true)
	next.settings = settings.duplicate(true)
	return _commit(next)
