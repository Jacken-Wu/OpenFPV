class_name WorldStreamer
extends Node3D

var generator: WorldGenerator
var origin_offset := Vector3.ZERO
var focus := Vector3.ZERO
var active: Dictionary = {}
var desired: Dictionary = {}
var pending: Dictionary = {}
var results: Array[Dictionary] = []
var mutex := Mutex.new()
var serial := 0
var last_key := Vector3i(99999, 99999, 99999)
var has_focus := false
var discarded := 0
var last_commit_ms := 0.0
var radius := 4
var vertical_radius := 3
var warming: Dictionary = {}
var warmed: Dictionary = {}
var assembly: Dictionary = {}
var commit_budget_us := 1800
var retired: Array[Node3D] = []

func _process(_delta: float) -> void:
	var key := WorldGenerator.key_at(focus)
	if not has_focus or key != last_key:
		has_focus = true
		_refresh(key)
	_commit_results()
	_dispatch()
	_prefetch_regions()
	if not retired.is_empty(): retired.pop_front().queue_free()

func _prefetch_regions() -> void:
	if not generator.regions is BiomeWorld: return
	for page: Vector2i in warming.keys():
		if WorkerThreadPool.is_task_completed(warming[page]):
			WorkerThreadPool.wait_for_task_completion(warming[page])
			warming.erase(page)
			if warmed.size() >= 16: warmed.erase(warmed.keys()[0])
			warmed[page] = true
	if not warming.is_empty(): return
	var page := RegionalWorld.key_at(focus)
	var candidates: Array[Vector2i] = []
	for x in range(-1, 2):
		for z in range(-1, 2):
			var next := page + Vector2i(x, z)
			if not warmed.has(next): candidates.append(next)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return (Vector2(a) * 512 + Vector2.ONE * 256).distance_squared_to(Vector2(focus.x, focus.z)) < (Vector2(b) * 512 + Vector2.ONE * 256).distance_squared_to(Vector2(focus.x, focus.z)))
	if not candidates.is_empty():
		var next := candidates[0]
		warming[next] = WorkerThreadPool.add_task(_warm_page.bind(generator.regions, next), false, "OpenFPV nearby region")

func _warm_page(world: BiomeWorld, page: Vector2i) -> void:
	world.region(page)

func _refresh(key: Vector3i) -> void:
	last_key = key
	desired.clear()
	for x in range(-radius, radius + 1):
		for y in range(-vertical_radius, vertical_radius + 1):
			for z in range(-radius, radius + 1):
				desired[key + Vector3i(x, y, z)] = true
	# Keep a ground horizon while above the ordinary vertical streaming window.
	if key.y > 2:
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				for y: int in [-1, 0]:
					desired[Vector3i(key.x + x, y, key.z + z)] = true
	for extra: Vector3i in generator.extra_visible_chunks(focus):
		desired[extra] = true
	for old: Vector3i in active.keys():
		if not desired.has(old):
			if is_instance_valid(active[old]):
				var node: Node3D = active[old]
				node.hide()
				for child in node.get_children():
					if child is StaticBody3D: child.collision_layer = 0; child.collision_mask = 0
				retired.append(node)
			active.erase(old)

func _dispatch() -> void:
	if pending.size() >= 4:
		return
	var candidates: Array = []
	for key: Vector3i in desired:
		# A completed worker hands ownership to assembly until publication or
		# cancellation. It is still in flight even after pending is cleared.
		if not active.has(key) and not pending.has(key) and (assembly.is_empty() or assembly.key != key):
			candidates.append(key)
	candidates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return Vector3(a - last_key).length_squared() < Vector3(b - last_key).length_squared())
	for index in mini(4 - pending.size(), candidates.size()):
		var key: Vector3i = candidates[index]
		serial += 1
		var ticket := serial
		var task := WorkerThreadPool.add_task(_generate.bind(key, ticket), false, "OpenFPV chunk")
		pending[key] = {"task": task, "ticket": ticket}

func _generate(key: Vector3i, ticket: int) -> void:
	var descriptor := generator.generate(key)
	descriptor.prepared = WorldGeometry.prepare_chunk(descriptor)
	descriptor.ticket = ticket
	mutex.lock()
	results.append(descriptor)
	mutex.unlock()

func _commit_results() -> void:
	var started := Time.get_ticks_usec()
	# Pure arrays and unique collision resources are prepared by workers. Scene
	# nodes are assembled within a time budget and published only when complete.
	while Time.get_ticks_usec() - started < commit_budget_us:
		if not assembly.is_empty():
			if not desired.has(assembly.key):
				assembly.root.free()
				assembly.clear()
				discarded += 1
				continue
			if WorldGeometry.advance_chunk(assembly, commit_budget_us - int(Time.get_ticks_usec() - started)):
				var node: Node3D = assembly.root
				node.position = WorldGenerator.origin_of(assembly.key) - origin_offset
				add_child(node)
				active[assembly.key] = node
				assembly.clear()
			break
		mutex.lock()
		var result: Dictionary = results.pop_front() if not results.is_empty() else {}
		mutex.unlock()
		if result.is_empty():
			break
		var key: Vector3i = result.key
		if not pending.has(key) or pending[key].ticket != result.ticket:
			discarded += 1
			continue
		WorkerThreadPool.wait_for_task_completion(pending[key].task)
		pending.erase(key)
		# Never replace an owned root: overwriting active would orphan its
		# visuals/colliders, excluding them from origin shifts and retirement.
		if not desired.has(key) or active.has(key):
			discarded += 1
			continue
		if not result.objects.is_empty():
			assembly = WorldGeometry.begin_chunk(result, origin_offset)
		else:
			active[key] = null
	last_commit_ms = (Time.get_ticks_usec() - started) / 1000.0

func collision_ready(point: Vector3) -> bool:
	var key := WorldGenerator.key_at(point)
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if not active.has(key + Vector3i(x, y, z)):
					return false
	return true

func shift_origin(shift: Vector3) -> void:
	origin_offset += shift
	for node: Variant in active.values():
		if is_instance_valid(node):
			node.position -= shift

func replace_generator(next: WorldGenerator) -> void:
	# Drain old workers before swapping their immutable generator snapshot.
	for job: Dictionary in pending.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	pending.clear()
	for task: int in warming.values(): WorkerThreadPool.wait_for_task_completion(task)
	warming.clear()
	warmed.clear()
	if not assembly.is_empty(): assembly.root.free(); assembly.clear()
	mutex.lock()
	results.clear()
	mutex.unlock()
	for node: Variant in active.values():
		if is_instance_valid(node):
			node.queue_free()
	active.clear()
	desired.clear()
	last_key = Vector3i(99999, 99999, 99999)
	has_focus = false
	origin_offset = Vector3.ZERO
	generator = next

func _exit_tree() -> void:
	for job: Dictionary in pending.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	for task: int in warming.values(): WorkerThreadPool.wait_for_task_completion(task)
	if not assembly.is_empty(): assembly.root.free(); assembly.clear()
