extends SceneTree
var failed := 0
var checked := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func run() -> void:
	var routes := 0
	var tight_vertical := 0
	var sharp_frames := 0
	var active_turns := 0
	var total_turns := 0
	for seed_value in [271828, 42, 314159]:
		var world := BiomeWorld.new(ContentCatalog.new(), seed_value)
		var valid := true
		var local_routes := 0
		for x in range(-3, 1):
			for z in range(-3, 1):
				for kind: String in ["surface", "sky"]:
					var plan := world.plan(kind, Vector2i(x, z))
					for task: MissionDefinition in plan.get("legacy_missions", []):
						if task.kind != "race" or task.challenge.get("acro_revision", 0) != 1: continue
						routes += 1
						local_routes += 1
						var old := world.mission(task.id.trim_suffix(":acro"))
						valid = valid and old != null and old.transaction_id() == task.transaction_id() and task.checkpoints.size() > old.checkpoints.size() and task.checkpoints.size() <= AcroCourses.MAX_GATES
						for index in range(1, task.checkpoints.size()):
							var delta := task.checkpoints[index] - task.checkpoints[index - 1]
							valid = valid and delta.length() >= 8
							if Vector2(delta.x, delta.z).length() <= 12 and absf(delta.y) >= 7.5: tight_vertical += 1
							if task.gate_normals[index].dot(task.gate_normals[index - 1]) < cos(deg_to_rad(50)): sharp_frames += 1
							if index < task.checkpoints.size() - 1:
								var next := task.checkpoints[index + 1] - task.checkpoints[index]
								var turn := rad_to_deg(acos(clampf(delta.normalized().dot(next.normalized()), -1, 1)))
								valid = valid and turn <= 132.1
								total_turns += 1
								active_turns += int(turn >= 35)
		check(valid and local_routes >= 3, "bounded technical routes and stable reward identity seed=" + str(seed_value))
	check(tight_vertical >= routes, "routes include many close horizontal / meaningful vertical gate pairs")
	check(sharp_frames >= routes, "adjacent gate planes repeatedly differ by at least50degrees")
	check(active_turns > total_turns * 0.4, "at least40percent of intermediate nodes ask for a substantial turn")
	print("ACRO_ROUTES_RESULT failures=%d checks=%d routes=%d vertical=%d frame_changes=%d turns=%d/%d" % [failed, checked, routes, tight_vertical, sharp_frames, active_turns, total_turns])
	quit(1 if failed else 0)
