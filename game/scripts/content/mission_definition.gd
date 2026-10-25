class_name MissionDefinition
extends Resource
## Immutable objective and reward references. Player state lives in ProgressStore.

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export_enum("hold_interact", "photo", "survey", "circuit", "courier", "race", "balloons", "orbit", "follow", "regional") var kind := "hold_interact"
@export var location_id := ""
@export var reward_id := ""
@export var mission_tag := ""
@export var city_tag := ""
@export var facility_id := ""
@export var interaction_radius := 6.5
@export var hold_seconds := 2.0
@export var max_speed := 1.5
@export var target_point := Vector3.ZERO
@export var target_bounds := AABB()
@export var min_distance := 15.0
@export var max_distance := 65.0
@export var max_angle_deg := 18.0
@export var generated := false
@export var station_id := ""
@export var source_point := Vector3.ZERO
@export var checkpoints := PackedVector3Array()
@export var gate_normals := PackedVector3Array()
@export var challenge: Dictionary = {}
@export var pickup_points := PackedVector3Array()
@export var pickup_platform: Dictionary = {}
@export var legacy_objects: Array[Dictionary] = []
@export var history_id := ""

func pickup_distance(point: Vector3) -> float:
	var distance := point.distance_to(acceptance_point())
	for pickup: Vector3 in pickup_points:
		distance = minf(distance, point.distance_to(pickup))
	return distance

func acceptance_point() -> Vector3:
	if not pickup_platform.is_empty():
		return pickup_platform.point
	return target_point - gate_normals[0] * 7 if kind == "race" and not gate_normals.is_empty() else target_point

func transaction_id() -> String:
	return "mission:" + (facility_id if not facility_id.is_empty() else history_id if not history_id.is_empty() else id)
