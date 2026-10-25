class_name FollowCourses
extends RefCounted
## Smooth closed pursuit paths; all samples stay above the local terrain skyline.
static func populate(plan: Dictionary, field: BiomeField, entrances: Array[Dictionary]) -> void:
	for slot in plan.missions.size():
		var mission: MissionDefinition = plan.missions[slot]
		if mission.kind != "follow":
			continue
		var rng := field.rng_for(plan.key, 43001 + slot * 997)
		var radius := rng.randf_range(48, 68)
		var center := mission.target_point
		for object: Dictionary in plan.objects:
			if Vector2(object.center.x - center.x, object.center.z - center.z).length() < 110:
				center.y = maxf(center.y, float(object.center.y) + float(object.size.y) * 0.5 + 22)
		if plan.kind == "surface":
			var sampler := BiomeTerrain.new(field, Vector2(center.x, center.z), entrances)
			for x in range(-100, 101, 10):
				for z in range(-100, 101, 10):
					center.y = maxf(center.y, sampler.sample(center.x + x, center.z + z) + 28)
			if plan.biomes[0].provider_id == "base.generator.modular_city":
				center.y = maxf(center.y, 115)
		center.y = minf(center.y, 277)
		var phase := rng.randf_range(0, TAU)
		mission.checkpoints = PackedVector3Array()
		for index in 12:
			var angle := phase + index * TAU / 12
			var r := radius * (1 + 0.22 * sin(angle * 3 + phase))
			mission.checkpoints.append(center + Vector3(cos(angle) * r, sin(angle * 2 + phase) * 7, sin(angle) * radius * 0.8))
		var length := 0.0
		for index in 12:
			length += mission.checkpoints[index].distance_to(mission.checkpoints[(index + 1) % 12])
		mission.target_point = center
		mission.target_bounds = AABB(center - Vector3.ONE * 1.3, Vector3.ONE * 2.6)
		mission.challenge = {"follow_revision": 2, "duration": 30.0, "coverage": 0.8, "range": 50.0, "path_speed": rng.randf_range(8, 11), "path_length": length, "view_angle": 60.0}
		mission.description = "接近观测机50米内开始拍摄。累计至少30秒，目标在视野内、目标距机体50米内的时间分别达到80%即完成；两项独立统计，失误后可继续追回比例，无截止时间。观测机沿起伏、变向的平滑环线飞行。"
		for location: MapLocation in plan.locations:
			if location.id == mission.location_id:
				location.description = mission.description
		if plan.kind == "sky":
			var bounds: AABB = plan.biomes[0].region_bounds
			for point in mission.checkpoints:
				bounds = bounds.expand(point - Vector3.ONE * 55)
				bounds = bounds.expand(point + Vector3.ONE * 55)
			plan.biomes[0].region_bounds = bounds
