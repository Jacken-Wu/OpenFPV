class_name BiomeDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var provider_id: String = ""
@export var tags: PackedStringArray = []
@export var region_bounds: AABB = AABB()
@export var priority: int = 0
@export var palette: PackedColorArray = []
@export var parameters: Dictionary = {}
@export var music: AudioStream
@export var music_title: String = ""
