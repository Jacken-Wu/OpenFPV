class_name PhotoObjective
extends RefCounted
## Rules shared by live framing hints and the saved frame's assessment.

static func evaluate(mission: MissionDefinition, camera_world: Transform3D, unobstructed: bool, collision_ready: bool = true) -> Dictionary:
	var result := {"ok": false, "message": "", "distance": 0.0, "angle": 180.0}
	if mission.kind != "photo" or not camera_world.origin.is_finite() or not camera_world.basis.is_finite() or camera_world.basis.z.length_squared() < 0.001:
		result.message = "相机或拍摄目标无效"
		return result
	var offset := mission.target_point - camera_world.origin
	result.distance = offset.length()
	result.angle = rad_to_deg(acos(clampf((-camera_world.basis.z).normalized().dot(offset.normalized()), -1.0, 1.0)))
	if not collision_ready:
		result.message = "等待目标周围地图与碰撞就绪"
	elif result.distance < mission.min_distance:
		result.message = "距离太近 · 请后退至 %.0f～%.0f m" % [mission.min_distance, mission.max_distance]
	elif result.distance > mission.max_distance:
		result.message = "距离太远 · 请靠近至 %.0f～%.0f m" % [mission.min_distance, mission.max_distance]
	elif result.angle > mission.max_angle_deg:
		result.message = "请将观测目标对准画面中心"
	elif not unobstructed:
		result.message = "目标被遮挡 · 请调整机位"
	else:
		result.ok = true
		result.message = "取景合格 · 按 F12 拍照"
	return result
