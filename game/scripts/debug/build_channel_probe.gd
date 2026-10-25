class_name BuildChannelProbe
extends RefCounted
## Export templates have no --script tool entry. Probe only a namespaced test profile.
static func run() -> Dictionary:
	var nonce := ""
	var expected := "absent"
	var mark := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--nonce="): nonce = arg.trim_prefix("--nonce=")
		if arg.begins_with("--expect="): expected = arg.trim_prefix("--expect=")
		if arg.begins_with("--mark="): mark = arg.trim_prefix("--mark=")
	if not nonce.begins_with("distribution_") or not nonce.is_valid_identifier() or nonce.length() > 80:
		return {"ok": false, "reason": "Invalid test namespace"}
	var directory := "user://tests/" + nonce
	var catalog := ContentCatalog.new()
	var library := SaveLibrary.new(catalog, directory.path_join("profile"))
	var path := library.active_path()
	var photo := directory.path_join("captures/marker.txt")
	var existed := FileAccess.file_exists(path)
	var photo_mark := FileAccess.get_file_as_string(photo).strip_edges() if FileAccess.file_exists(photo) else "absent"
	var store := ProgressStore.new(catalog, path)
	var ok := not existed and photo_mark == "absent" if expected == "absent" else existed and int(store.data.credits) == int(expected) and photo_mark == expected
	if ok and not mark.is_empty():
		var next := store.data.duplicate(true)
		next.credits = int(mark)
		ok = store._commit(next).ok
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(photo.get_base_dir()))
		var file := FileAccess.open(photo, FileAccess.WRITE)
		if file == null: ok = false
		else: file.store_string(mark); file.close()
	return {"ok": ok, "debug": OS.is_debug_build(), "directory": OS.get_user_data_dir(), "existing": existed, "credits": store.data.credits, "photo": photo_mark}
