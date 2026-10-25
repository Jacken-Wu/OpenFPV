class_name AchievementDefinition
extends Resource
@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_enum("missions", "portals", "biomes", "mission_types", "presets") var metric := "missions"
@export var target := 1
