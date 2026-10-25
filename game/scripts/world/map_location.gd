class_name MapLocation
extends Resource
## Immutable map content. Selection and route progress belong to MapNavigation.

@export var id: String
@export var display_name: String
@export_enum("teleport", "shop", "mission", "landmark") var kind := "landmark"
@export var point := Vector3.ZERO
@export_multiline var description: String
@export var approach: PackedVector3Array = []
@export var interior_bounds := AABB()
@export var structure_id := ""
@export var layer := "surface"

func kind_name() -> String:
	return {"teleport": "传送点", "shop": "商店", "mission": "任务", "landmark": "地点"}.get(kind, "地点")

func color() -> Color:
	return {"teleport": Color("79dfc9"), "shop": Color("9cd897"), "mission": Color("f4c47b"), "landmark": Color("a8b8f4")}.get(kind, Color.WHITE)
