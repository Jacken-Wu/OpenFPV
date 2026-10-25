extends SceneTree
var failed := 0
var checked := 0
var probes := 0
var height_cache := {}
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checked += 1
	failed += int(not value)
	print("PASS " if value else "FAIL ", message)
func terrain_height(p: Vector3, sampler: BiomeTerrain) -> float:
	var x := floori(p.x / 4)
	var z := floori(p.z / 4)
	var u := p.x / 4 - x
	var v := p.z / 4 - z
	var heights: Array[float] = []
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i(0, 1), Vector2i.ONE]:
		var key := Vector2i(x, z) + offset
		if not height_cache.has(key): height_cache[key] = sampler.sample(key.x * 4, key.y * 4)
		heights.append(height_cache[key])
	return heights[0] * (1 - u - v) + heights[1] * u + heights[2] * v if u + v <= 1 else heights[3] * (u + v - 1) + heights[1] * (1 - v) + heights[2] * (1 - u)
func inside(p: Vector3, volume: Dictionary) -> bool:
	var axis: Vector3 = (volume.b - volume.a).normalized()
	var offset: Vector3 = p - volume.a
	var length: float = volume.a.distance_to(volume.b)
	if offset.dot(axis) < -float(volume.get("extension_a", volume.extension)) - 0.001 or offset.dot(axis) > length + float(volume.get("extension_b", volume.extension)) + 0.001: return false
	var right := axis.cross(Vector3.UP).normalized()
	var up := right.cross(axis).normalized()
	for side in 16:
		var normal := right * cos((side + 0.5) * TAU / 16) + up * sin((side + 0.5) * TAU / 16)
		if normal.dot(offset) > float(volume.radius) * cos(PI / 16) + 0.001: return false
	return true
func seal(space: PhysicsDirectSpaceState3D, p: Vector3, normal: Vector3, origin: Vector3, sampler: BiomeTerrain, volumes: Array, own: Dictionary) -> bool:
	var a := p - normal * 0.45
	var b := p + normal * 0.45
	if a.y > terrain_height(a, sampler) - 0.06 or b.y > terrain_height(b, sampler) - 0.06: return true
	for other: Dictionary in volumes:
		if other.id != own.id and inside(b, other): return true
	probes += 1
	var query := PhysicsRayQueryParameters3D.create(a - origin, b - origin)
	query.hit_back_faces = true
	var hit := space.intersect_ray(query)
	if not hit.is_empty(): return true
	# Rays exactly along two triangle borders can miss a mathematically closed
	# edge. Confirm any apparent leak with a small real body before failing it.
	var sphere := SphereShape3D.new()
	sphere.radius = 0.08
	var body := PhysicsShapeQueryParameters3D.new()
	body.shape = sphere
	body.transform = Transform3D(Basis.IDENTITY, a - origin)
	if not space.intersect_shape(body, 1).is_empty(): return true
	body.motion = b - a
	if space.cast_motion(body)[0] < 1: return true
	if failed < 3: print("SEAM_LEAK ", own.id, " ", p, " normal=", normal)
	return false
func run() -> void:
	var world := BiomeWorld.new(ContentCatalog.new(), 271828)
	var examples := {}
	for x in range(-12, 13):
		for z in range(-12, 13):
			var site := world.field.surface_site(Vector2i(x, z))
			var style: String = site.biome.parameters.get("terrain_style", "")
			if style in ["alpine", "snow_peak", "ravine", "volcano"] and not examples.has(style): examples[style] = site
	for style: String in examples:
		var plan := world.plan("surface", examples[style].key)
		check(not plan.caves.is_empty(), style + " has entrances to inspect")
		if plan.caves.is_empty(): continue
		var cave: Dictionary = plan.caves[0]
		var sampler := BiomeTerrain.new(world.field, examples[style].anchor)
		height_cache.clear()
		var host := Node3D.new()
		root.add_child(host)
		var origin: Vector3 = cave.a
		var keys := {}
		for p: Vector3 in [cave.a, cave.b]:
			var key := WorldGenerator.key_at(p)
			for x in range(-1, 2):
				for y in range(-1, 2):
					for z in range(-1, 2): keys[key + Vector3i(x, y, z)] = true
		for key: Vector3i in keys: host.add_child(WorldGeometry.create_chunk(world.generate_chunk(key), origin))
		await physics_frame
		await physics_frame
		var space := host.get_world_3d().direct_space_state
		var before := probes
		for end in 2:
			var volume: Dictionary = cave.segments[0 if end == 0 else 7]
			var axis: Vector3 = (volume.b - volume.a).normalized()
			var right := axis.cross(Vector3.UP).normalized()
			var up := right.cross(axis).normalized()
			var extension_a: float = volume.get("extension_a", volume.extension)
			var extension_b: float = volume.get("extension_b", volume.extension)
			var start: Vector3 = volume.a - axis * extension_a
			var finish: Vector3 = volume.b + axis * extension_b
			var leaks := 0
			for step in 33:
				for side in 16:
					var normal := right * cos((side + 0.5) * TAU / 16) + up * sin((side + 0.5) * TAU / 16)
					var p := start.lerp(finish, step / 32.0) + normal * float(volume.radius) * cos(PI / 16)
					leaks += int(not seal(space, p, normal, origin, sampler, cave.segments, volume))
			check(leaks == 0, style + " entrance%d terrain/wall seam blocks every buried outward escape, leaks=%d" % [end, leaks])
			leaks = 0
			for x in range(-3, 4):
				for y in range(-3, 4):
					var p: Vector3 = (start if end == 0 else finish) + (right * x + up * y) * float(volume.radius) / 4
					if not inside(p, volume): continue
					leaks += int(not seal(space, p, -axis if end == 0 else axis, origin, sampler, cave.segments, volume))
			check(leaks == 0, style + " entrance%d buried end is sealed without closing the outdoor opening, leaks=%d" % [end, leaks])
		var body := BoxShape3D.new()
		body.size = Vector3(0.6, 0.2, 0.6)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body
		var passable := true
		for end in 2:
			var path: PackedVector3Array = cave.paths[0]
			var a: Vector3 = path[0] if end == 0 else path[-1]
			var b: Vector3 = path[1] if end == 0 else path[-2]
			query.transform = Transform3D(Basis.IDENTITY, a - origin)
			query.motion = b - a
			passable = passable and space.cast_motion(query)[0] == 1
		check(passable and probes > before, style + " real drone still enters and exits; buried boundary probes=" + str(probes - before))
		host.queue_free()
		await physics_frame
	print("CAVE_SEAMS_RESULT failures=%d checks=%d probes=%d" % [failed, checked, probes])
	quit(1 if failed else 0)
