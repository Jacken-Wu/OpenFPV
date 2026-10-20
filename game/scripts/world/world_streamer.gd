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
var discarded := 0
var last_commit_ms := 0.0
var radius := 3

func _process(_delta: float) -> void:
	var key := WorldGenerator.key_at(focus)
	if key != last_key:
		_refresh(key)
	_commit_results()
	_dispatch()

func _refresh(key: Vector3i) -> void:
	last_key = key
	desired.clear()
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				desired[key + Vector3i(x, y, z)] = true
	for old: Vector3i in active.keys():
		if not desired.has(old):
			if is_instance_valid(active[old]):
				active[old].queue_free()
			active.erase(old)

func _dispatch() -> void:
	if pending.size() >= 4:
		return
	var candidates: Array = []
	for key: Vector3i in desired:
		if not active.has(key) and not pending.has(key):
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
	descriptor.ticket = ticket
	mutex.lock()
	results.append(descriptor)
	mutex.unlock()

func _commit_results() -> void:
	var started := Time.get_ticks_usec()
	# Limit expensive scene and collision creation to one nonempty chunk per frame.
	var budget := 1
	while budget > 0:
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
		if not desired.has(key):
			discarded += 1
			continue
		var node: Node3D = null
		if not result.objects.is_empty():
			node = WorldGeometry.create_chunk(result, origin_offset)
			add_child(node)
			budget -= 1
		active[key] = node
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

func _exit_tree() -> void:
	for job: Dictionary in pending.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
