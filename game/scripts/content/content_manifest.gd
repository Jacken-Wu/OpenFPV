class_name ContentManifest
extends Resource

@export var content_version: String = "0.1.0"
@export var world_version: int = 1
@export var parts: Array[Resource] = []
@export var presets: Array[Resource] = []
@export var propulsion_maps: Array[Resource] = []
@export var biomes: Array[Resource] = []
@export var rewards: Array[Resource] = []
@export var offers: Array[Resource] = []
@export var missions: Array[Resource] = []
@export var mission_templates: Array[Resource] = []
@export var challenge_templates: Array[Resource] = []
@export var achievements: Array[Resource] = []
@export var generation_rules: Dictionary = {}
@export var initial_preset_id: String = ""
