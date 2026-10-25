class_name BiomeStructures
extends RefCounted
## Geometry and traversal data share the same deterministic plans.
const CELL := 16.0
const NAV_HEIGHT := 9.0
const DIRECTIONS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func sky(site: Dictionary, field: BiomeField) -> Dictionary:
	var rng := field.rng_for(site.key, 4013)
	var anchor := Vector3(site.pos.x, rng.randf_range(155, 240), site.pos.y)
	var expanded := field.expanded_at(site.pos)
	var sampler: BiomeTerrain
	if expanded:
		sampler = BiomeTerrain.new(field, site.pos)
		var skyline := -INF
		for x: float in [-90, 0, 90]:
			for z: float in [-90, 0, 90]:
				skyline = maxf(skyline, sampler.sample(site.pos.x + x, site.pos.y + z))
		anchor.y = maxf(anchor.y, skyline + 63)
	var islands: Array[Dictionary] = [{"point": anchor, "radius": rng.randf_range(62, 84), "depth": rng.randf_range(30, 48)}]
	var wanted := rng.randi_range(5, 10)
	for attempt in 160:
		if islands.size() >= wanted:
			break
		var angle := rng.randf_range(0, TAU)
		var distance := rng.randf_range(105, 245)
		var radius := rng.randf_range(23, 48)
		var point := anchor + Vector3(cos(angle) * distance, rng.randf_range(-38, 48), sin(angle) * distance)
		var clear := true
		if expanded:
			var skyline := -INF
			for x: float in [-radius, 0, radius]:
				for z: float in [-radius, 0, radius]:
					skyline = maxf(skyline, sampler.sample(point.x + x, point.z + z))
			point.y = maxf(point.y, skyline + 49)
			clear = point.y <= 282
		for island in islands:
			if Vector2(point.x, point.z).distance_to(Vector2(island.point.x, island.point.z)) < radius + float(island.radius) + 14:
				clear = false
		if clear:
			islands.append({"point": point, "radius": radius, "depth": rng.randf_range(16, 36)})
	var objects: Array[Dictionary] = []
	var nodes: Array[Vector3] = []
	var bounds := AABB(anchor, Vector3.ONE)
	for index in islands.size():
		var island := islands[index]
		var point: Vector3 = island.point
		var radius: float = island.radius
		nodes.append(point + Vector3(0, 1.5, 0))
		for angle: float in [PI * 0.5, PI, PI * 1.5]:
			nodes.append(point + Vector3(cos(angle) * radius * 0.45, 0.8, sin(angle) * radius * 0.45))
		bounds = bounds.merge(AABB(point - Vector3(radius * 1.1, island.depth, radius * 1.1), Vector3(radius * 2.2, island.depth + 12, radius * 2.2)))
		var segments := 28
		for segment in segments:
			var vertices := PackedVector3Array([point + Vector3(0, 1.5, 0)])
			for ring in 3:
				for edge in 2:
					var angle := float(segment + edge) / segments * TAU
					var shape := 0.88 + field.roll(Vector2i(index * 97 + (segment + edge) % segments, site.key.x * 13 + site.key.y), 5011) * 0.2
					var r: float = radius * [1.0, 0.83, 0.28][ring] * shape
					var y: float = [0.0, -float(island.depth) * 0.38, -float(island.depth)][ring]
					vertices.append(point + Vector3(cos(angle) * r, y, sin(angle) * r))
			var indices := PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4, 4, 5, 6])
			# Bottom fan closes the underside of the entire cluster island.
			vertices.append(point - Vector3.UP * (float(island.depth) + 3))
			indices.append_array(PackedInt32Array([5, 7, 6]))
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			var mesh_bounds := AABB(vertices[0], Vector3.ZERO)
			for vertex in vertices:
				normals.append(Vector3.UP if vertex.y >= point.y else (vertex - point).normalized())
				colors.append(Color("88aa72") if vertex.y >= point.y else Color("8d998e"))
				mesh_bounds = mesh_bounds.expand(vertex)
			objects.append({"id": site.id + "/island%d/sector%d" % [index, segment], "primitive": "terrain", "center": mesh_bounds.get_center(), "size": mesh_bounds.size, "solid": true, "color": Color.WHITE, "vertices": vertices, "normals": normals, "colors": colors, "indices": indices, "surfaces": PackedInt32Array([0, 1, 1, 1, 1, 1]), "surface_names": ["grass", "sandstone"]})
		# Some islands hold a ruin or observatory, leaving the centre free for services.
		if rng.randf() < 0.55:
			var p := point + Vector3(radius * 0.55, 0, 0)
			if rng.randf() < 0.5:
				for side: float in [-1, 1]:
					objects.append(WorldProvider.box(site.id + "/ruin%d/%s" % [index, side], p + Vector3(side * 4, 5, 0), Vector3(2, 10, 3), Color("a6ada0"), true, "concrete"))
				objects.append(WorldProvider.box(site.id + "/arch%d" % index, p + Vector3(0, 10, 0), Vector3(10, 2, 3), Color("a6ada0"), true, "concrete"))
			else:
				var tower := WorldProvider.box(site.id + "/tower%d" % index, p + Vector3(0, 7, 0), Vector3(8, 14, 8), Color("8ea8a7"), true, "metal")
				tower.primitive = "cylinder"
				objects.append(tower)
	return {"islands": islands, "nodes": nodes, "objects": objects, "bounds": bounds, "entries": []}

static func maze(site: Dictionary, field: BiomeField) -> Dictionary:
	var rng := field.rng_for(site.key, 6011)
	var width := rng.randi_range(6, 10) * 2 + 1
	var depth := rng.randi_range(6, 9) * 2 + 1
	var floor_y := -rng.randf_range(75, 118)
	var height := rng.randf_range(14, 21)
	var origin := Vector3(snappedf(site.pos.x, CELL) - width * CELL * 0.5, floor_y, snappedf(site.pos.y, CELL) - depth * CELL * 0.5)
	var doors := PackedInt32Array()
	doors.resize(width * depth)
	var visited: Dictionary = {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var current: int = stack.back()
		var next: Array[int] = []
		for direction in 4:
			var p: Vector2i = Vector2i(current % width, current / width) + DIRECTIONS[direction]
			var target := p.y * width + p.x
			if p.x >= 0 and p.x < width and p.y >= 0 and p.y < depth and not visited.has(target):
				next.append(direction)
		if next.is_empty():
			stack.pop_back()
			continue
		var direction := next[rng.randi_range(0, next.size() - 1)]
		var target: int = current + DIRECTIONS[direction].x + DIRECTIONS[direction].y * width
		carve(doors, current, target, direction)
		visited[target] = true
		stack.append(target)
	var rooms: Array[int] = []
	for room in rng.randi_range(3, 6):
		var rx := rng.randi_range(1, width - 4)
		var rz := rng.randi_range(1, depth - 4)
		var rw := rng.randi_range(2, 3)
		var rd := rng.randi_range(2, 3)
		rooms.append((rz + rd / 2) * width + rx + rw / 2)
		for z in range(rz, rz + rd):
			for x in range(rx, rx + rw):
				var cell := z * width + x
				if x + 1 < rx + rw:
					carve(doors, cell, cell + 1, 1)
				if z + 1 < rz + rd:
					carve(doors, cell, cell + width, 2)
	# A few loops avoid making every journey a single long dead-end corridor.
	for cell in doors.size():
		if cell % width < width - 1 and rng.randf() < 0.12:
			carve(doors, cell, cell + 1, 1)
		if cell / width < depth - 1 and rng.randf() < 0.12:
			carve(doors, cell, cell + width, 2)
	var entry_cells: Array[int] = []
	for entry in rng.randi_range(1, 3):
		var cell := rng.randi_range(0, width * depth - 1)
		if not entry_cells.has(cell):
			entry_cells.append(cell)
	var data := {"width": width, "depth": depth, "origin": origin, "floor": floor_y, "height": height, "doors": doors, "rooms": rooms, "entry_cells": entry_cells}
	var objects: Array[Dictionary] = []
	var nodes: Array[Vector3] = []
	var entries: Array[Dictionary] = []
	for cell in doors.size():
		var p := cell_point(data, cell)
		nodes.append(p)
		objects.append(WorldProvider.box(site.id + "/floor%d" % cell, p - Vector3.UP * 0.5, Vector3(CELL, 1, CELL), Color("52626a"), true, "concrete"))
		if not entry_cells.has(cell):
			objects.append(WorldProvider.box(site.id + "/roof%d" % cell, p + Vector3.UP * (height + 0.5), Vector3(CELL, 1, CELL), Color("65736e"), true, "concrete"))
		for direction in 4:
			if (doors[cell] & (1 << direction)) != 0:
				continue
			if direction == 1 and cell % width != width - 1:
				continue
			if direction == 2 and cell / width != depth - 1:
				continue
			var d: Vector2i = DIRECTIONS[direction]
			objects.append(WorldProvider.box(site.id + "/wall%d/%d" % [cell, direction], p + Vector3(d.x * 8, height * 0.5, d.y * 8), Vector3(1.2, height, CELL + 1.2) if d.x != 0 else Vector3(CELL + 1.2, height, 1.2), Color("657b78"), true, "concrete"))
		if cell % 7 == 0:
			objects.append(WorldProvider.box(site.id + "/light%d" % cell, p + Vector3(0, height - 0.15, 0), Vector3(5, 0.25, 1), Color("8ce2c9"), true, "screen"))
	for cell in entry_cells:
		var bottom := cell_point(data, cell) + Vector3.UP * 6
		var sampler := BiomeTerrain.new(field, Vector2(bottom.x, bottom.z))
		var top_y := -INF
		for dx: float in [-12, 0, 12]:
			for dz: float in [-12, 0, 12]:
				top_y = maxf(top_y, sampler.base_height(bottom.x + dx, bottom.z + dz))
		var top := Vector3(bottom.x, top_y + 0.2, bottom.z)
		entries.append({"cell": cell, "top": top, "bottom": bottom, "hole": Rect2(Vector2(top.x - 8, top.z - 8), Vector2(16, 16))})
		var y := floor_y + height
		var segment := 0
		while y < top.y:
			var h := minf(16, top.y - y)
			for direction in 4:
				var d: Vector2i = DIRECTIONS[direction]
				objects.append(WorldProvider.box(site.id + "/shaft%d/%d/%d" % [cell, segment, direction], Vector3(top.x + d.x * 8, y + h * 0.5, top.z + d.y * 8), Vector3(1.2, h, 17.2) if d.x else Vector3(17.2, h, 1.2), Color("7d8e85"), true, "concrete"))
			y += h
			segment += 1
		for side: float in [-1, 1]:
			objects.append(WorldProvider.box(site.id + "/rim_x%d/%s" % [cell, side], top + Vector3(side * 9, -0.3, 0), Vector3(2, 0.6, 20), Color("bda976"), true, "metal"))
			objects.append(WorldProvider.box(site.id + "/rim_z%d/%s" % [cell, side], top + Vector3(0, -0.3, side * 9), Vector3(16, 0.6, 2), Color("bda976"), true, "metal"))
	return {"maze": data, "nodes": nodes, "entries": entries, "objects": objects, "bounds": AABB(origin - Vector3(1, 1, 1), Vector3(width * CELL + 2, height + 2, depth * CELL + 2))}

static func carve(doors: PackedInt32Array, a: int, b: int, direction: int) -> void:
	doors[a] |= 1 << direction
	doors[b] |= 1 << ((direction + 2) % 4)

static func cell_point(data: Dictionary, cell: int) -> Vector3:
	return data.origin + Vector3((cell % int(data.width) + 0.5) * CELL, 0, (cell / int(data.width) + 0.5) * CELL)

static func cell_at(data: Dictionary, point: Vector3) -> int:
	var local: Vector3 = point - data.origin
	return clampi(floori(local.z / CELL), 0, data.depth - 1) * int(data.width) + clampi(floori(local.x / CELL), 0, data.width - 1)

static func maze_path(data: Dictionary, start: int, goal: int) -> PackedVector3Array:
	var parents: Dictionary = {start: -1}
	var queue: Array[int] = [start]
	var index := 0
	while index < queue.size() and not parents.has(goal):
		var current := queue[index]
		index += 1
		for direction in 4:
			if (data.doors[current] & (1 << direction)) == 0:
				continue
			var next: int = current + DIRECTIONS[direction].x + DIRECTIONS[direction].y * int(data.width)
			if not parents.has(next):
				parents[next] = current
				queue.append(next)
	if not parents.has(goal):
		return PackedVector3Array()
	var result: Array[Vector3] = []
	var current := goal
	while current != -1:
		result.push_front(cell_point(data, current) + Vector3.UP * NAV_HEIGHT)
		current = parents[current]
	return PackedVector3Array(result)
