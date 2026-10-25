class_name SaveLibrary
extends RefCounted
## Slot paths are generated IDs; user-visible names never become filesystem paths.
var catalog: ContentCatalog
var root: String
var writable := true
var warning := ""

func _init(content: ContentCatalog, directory: String = "user://profile") -> void:
	catalog = content
	root = directory

func _path(id: String) -> String:
	if id == "legacy":
		return root.path_join("progress.json")
	if not id.begins_with("slot_") or not id.is_valid_identifier():
		return ""
	return root.path_join("saves").path_join(id + ".json")

func id_for_path(path: String) -> String:
	if path == _path("legacy"):
		return "legacy"
	var id := path.get_file().get_basename()
	return id if not _path(id).is_empty() and ProjectSettings.globalize_path(path) == ProjectSettings.globalize_path(_path(id)) else ""

func _snapshot(id: String) -> Dictionary:
	var path := _path(id)
	if path.is_empty():
		return {}
	var record := ProgressStore.read_snapshot(path)
	return ProgressStore.read_snapshot(path + ".backup") if record.is_empty() else record

func active_path() -> String:
	for suffix: String in ["", ".backup"]:
		var marker := root.path_join("active.json") + suffix
		if not FileAccess.file_exists(marker):
			continue
		var id := _marker_id(marker)
		if not id.is_empty():
			return _path(id)
		warning = "存档选择记录无法读取，已尝试恢复上次选择；可在Esc菜单查看全部存档。"
	return _path("legacy")

func _marker_id(source: String) -> String:
	if not FileAccess.file_exists(source):
		return ""
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(source)) != OK:
		return ""
	var value: Variant = parser.data
	return String(value.id) if value is Dictionary and value.get("id") is String and not _snapshot(value.id).is_empty() else ""

func entries(current_path: String) -> Array[Dictionary]:
	var ids: Array[String] = []
	if FileAccess.file_exists(_path("legacy")) or FileAccess.file_exists(_path("legacy") + ".backup"):
		ids.append("legacy")
	var dir := DirAccess.open(root.path_join("saves"))
	if dir != null:
		for file: String in dir.get_files():
			var id := file.trim_suffix(".backup").trim_suffix(".json")
			if (file.ends_with(".json") or file.ends_with(".json.backup")) and not _path(id).is_empty() and not ids.has(id):
				ids.append(id)
	var result: Array[Dictionary] = []
	for id in ids:
		var data := _snapshot(id)
		result.append({"id": id, "name": data.get("save_name", "原有世界" if id == "legacy" else "未命名世界"), "seed": data.get("seed", 0), "updated": data.get("save_updated", ""), "credits": data.get("credits", 0), "valid": not data.is_empty(), "compatible": int(data.get("world_version", -1)) == catalog.manifest.world_version, "active": _path(id) == current_path, "backup": ProgressStore.read_snapshot(_path(id)).is_empty(), "path": _path(id)})
	result.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.updated) > String(b.updated) if a.updated != b.updated else String(a.id) < String(b.id))
	return result

func _name_valid(name: String) -> bool:
	return not name.strip_edges().is_empty() and name.length() <= 48 and not name.contains("\n") and not name.contains("\r") and not name.contains("\t")

func save(current: ProgressStore) -> Dictionary:
	if not writable:
		return {"ok": false, "message": "存档目录不可写。"}
	var next := current.data.duplicate(true)
	next.save_updated = Time.get_datetime_string_from_system()
	if not next.has("save_name"):
		next.save_name = "我的世界"
	return current._commit(next)

func _write(path: String, snapshot: Dictionary) -> Dictionary:
	if not writable:
		return {"ok": false, "message": "存档目录不可写。"}
	var writer := ProgressStore.new(catalog, path, false)
	return writer._commit(snapshot, false)

func _new_id() -> String:
	var id := "slot_%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	while FileAccess.file_exists(_path(id)):
		id += "_1"
	return id

func duplicate_current(current: ProgressStore, name: String) -> Dictionary:
	if not _name_valid(name):
		return {"ok": false, "message": "名称须为1～48个字符，不能换行。"}
	var next := current.data.duplicate(true)
	next.save_name = name.strip_edges()
	next.save_updated = Time.get_datetime_string_from_system()
	next.save_created = next.save_updated
	var id := _new_id()
	var result := _write(_path(id), next)
	result.id = id
	result.message = "已另存副本：" + next.save_name if result.ok else result.message
	return result

func new_world(current: ProgressStore, name: String, seed_value: int) -> Dictionary:
	if not _name_valid(name) or seed_value < -2147483648 or seed_value > 2147483647:
		return {"ok": false, "message": "请输入1～48字名称与有效整数种子。"}
	var saved := save(current)
	if not saved.ok:
		return saved
	var next := current._new_profile(seed_value)
	next.settings = current.data.settings.duplicate(true)
	next.save_name = name.strip_edges()
	next.save_updated = Time.get_datetime_string_from_system()
	next.save_created = next.save_updated
	var id := _new_id()
	var result := _write(_path(id), next)
	return load_slot(id, current) if result.ok else result

func load_slot(id: String, current: ProgressStore) -> Dictionary:
	if not writable or _path(id).is_empty():
		return {"ok": false, "message": "存档不可写或编号无效。"}
	var snapshot := current.data.duplicate(true) if _path(id) == current.path else _snapshot(id)
	if snapshot.is_empty() or int(snapshot.world_version) != catalog.manifest.world_version:
		return {"ok": false, "message": "存档损坏或世界版本不兼容，当前世界保持不变。"}
	var saved := save(current)
	if not saved.ok:
		return saved
	# Control preferences follow the player, not the age of the selected world.
	snapshot.settings = current.data.settings.duplicate(true)
	var written := _write(_path(id), snapshot)
	if not written.ok:
		return written
	var pointer := _activate(id)
	if not pointer.ok:
		return pointer
	var next := ProgressStore.new(catalog, _path(id), false)
	next.use_snapshot(snapshot)
	next._mirror_controls()
	return {"ok": true, "store": next, "message": "已读取：%s · 回到安全平台" % snapshot.get("save_name", "原有世界")}

func _activate(id: String) -> Dictionary:
	var path := root.path_join("active.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	var file := FileAccess.open(path + ".pending", FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法保存当前存档选择，原世界保持不变。"}
	file.store_string(JSON.stringify({"id": id}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK and not _marker_id(path).is_empty():
		error = DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".backup"))
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".pending"), ProjectSettings.globalize_path(path))
	return {"ok": error == OK, "message": "已选择存档" if error == OK else "无法保存存档选择，原世界保持不变。"}

func rename_slot(id: String, name: String, current: ProgressStore) -> Dictionary:
	if not writable or not _name_valid(name):
		return {"ok": false, "message": "名称须为1～48个字符，不能换行。"}
	var data := current.data.duplicate(true) if _path(id) == current.path else _snapshot(id)
	if data.is_empty():
		return {"ok": false, "message": "无法读取存档。"}
	data.save_name = name.strip_edges()
	data.save_updated = Time.get_datetime_string_from_system()
	return current._commit(data) if _path(id) == current.path else _write(_path(id), data)

func delete_slot(id: String, current: ProgressStore) -> Dictionary:
	var source := _path(id)
	if not writable or source.is_empty() or source == current.path:
		return {"ok": false, "message": "无法删除当前存档；请先切换世界。"}
	var trash := root.path_join("trash")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trash)) != OK:
		return {"ok": false, "message": "无法创建存档回收目录。"}
	var destination := trash.path_join(id + "_" + str(Time.get_ticks_usec()) + ".json")
	var moved: Array[String] = []
	for suffix: String in ["", ".backup"]:
		if not FileAccess.file_exists(source + suffix):
			continue
		var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(source + suffix), ProjectSettings.globalize_path(destination + suffix))
		if error != OK:
			for previous in moved:
				DirAccess.rename_absolute(ProjectSettings.globalize_path(destination + previous), ProjectSettings.globalize_path(source + previous))
			return {"ok": false, "message": "移入回收目录失败；请检查原目录和trash中保留的文件。"}
		moved.append(suffix)
	return {"ok": not moved.is_empty(), "message": "已移入存档回收目录，文件可手动恢复。" if not moved.is_empty() else "存档不存在。"}
