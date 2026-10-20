extends SceneTree

func _initialize() -> void:
	var source: BiomeDefinition = load("res://content/base/rustworks.tres")
	print("RESOURCE_TEXT palette=", source.palette.size())
	var error := ResourceSaver.save(source, "user://tests/roundtrip.res")
	print("RESOURCE_SAVE ", error)
	var restored: BiomeDefinition = ResourceLoader.load("user://tests/roundtrip.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	print("RESOURCE_BINARY palette=", restored.palette.size())
	quit(0 if restored.palette == source.palette else 1)
