extends SceneTree

func _initialize() -> void:
	var target := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			target = argument.trim_prefix("--output=")
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\nThird-party components\n\n")
	file.store_string(JSON.stringify(Engine.get_copyright_info(), "\t") + "\n\n")
	var licenses := Engine.get_license_info()
	var names := licenses.keys()
	names.sort()
	for name_value: String in names:
		file.store_string(name_value + "\n" + String(licenses[name_value]) + "\n\n")
	file.close()
	print("ENGINE_NOTICES_OK")
	quit()
