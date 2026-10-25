class_name WorldGeometry
extends RefCounted
static var prototypes: Dictionary = {}
static var terrain_materials: Dictionary = {}

static func material_for(color: Color, surface: String = "paint") -> StandardMaterial3D:
	return WorldMaterials.material_for(color, surface)

## Worker preparation uses unique physics resources, never scene nodes or shared materials.
static func prepare_chunk(descriptor: Dictionary) -> Dictionary:
	var origin := WorldGenerator.origin_of(descriptor.key)
	var buckets := {}
	var terrain: Array[Dictionary] = []
	var collisions: Array[Dictionary] = []
	for object: Dictionary in descriptor.objects:
		if object.get("primitive", "") == "terrain":
			terrain.append(_prepare_terrain(object, origin))
			continue
		var primitive: String = object.get("primitive", "box")
		var surface: String = object.get("surface", "paint")
		var rotation := Basis.from_euler(object.get("rotation", Vector3.ZERO))
		var transform := Transform3D(rotation.scaled_local(object.size), object.center - origin)
		var no_shadow: bool = object.id.ends_with("/ground")
		var subdivided: bool = primitive == "box" and object.size[object.size.max_axis_index()] > 32 and not no_shadow
		var sector := Vector3i((object.center - origin) / 32)
		var style: String = surface + "|" + primitive + "|" + object.color.to_html() + ("|detail" if subdivided else "")
		var key: String = style + str(sector) + str(no_shadow)
		var bounds: AABB = transform * AABB(Vector3.ONE * -0.5, Vector3.ONE)
		if not buckets.has(key):
			buckets[key] = {"style": style, "color": object.color, "surface": surface, "primitive": primitive, "transforms": [], "bounds": bounds, "no_shadow": no_shadow, "subdivided": subdivided}
		buckets[key].transforms.append(transform)
		buckets[key].bounds = buckets[key].bounds.merge(bounds)
		if not object.solid: continue
		var shape: Shape3D
		if primitive == "cylinder":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = object.size.x * 0.5
			cylinder.height = object.size.y
			shape = cylinder
		elif primitive == "cone":
			var cone := ConvexPolygonShape3D.new()
			var points := PackedVector3Array([Vector3(0, object.size.y * 0.5, 0)])
			for index in 10:
				var angle := index * TAU / 10
				points.append(Vector3(cos(angle) * object.size.x * 0.5, -object.size.y * 0.5, sin(angle) * object.size.z * 0.5))
			cone.points = points
			shape = cone
		else:
			var box := BoxShape3D.new()
			box.size = object.size
			shape = box
		collisions.append({"shape": shape, "transform": Transform3D(rotation, object.center - origin)})
	return {"terrain": terrain, "collisions": collisions, "buckets": buckets.values()}

static func _prepare_terrain(object: Dictionary, origin: Vector3) -> Dictionary:
	var vertices: PackedVector3Array = object.vertices.duplicate()
	for index in vertices.size(): vertices[index] -= origin
	var surfaces: Array[Dictionary] = []
	var indices_by_surface: Array[PackedInt32Array] = []
	indices_by_surface.resize(object.surface_names.size())
	for triangle in object.surfaces.size():
		var slot: int = object.surfaces[triangle]
		for corner in 3: indices_by_surface[slot].append(object.indices[triangle * 3 + corner])
	for index in object.surface_names.size():
		if indices_by_surface[index].is_empty(): continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = object.normals
		arrays[Mesh.ARRAY_COLOR] = object.colors
		arrays[Mesh.ARRAY_INDEX] = indices_by_surface[index]
		surfaces.append({"arrays": arrays, "surface": object.surface_names[index]})
	var faces := PackedVector3Array()
	faces.resize(object.indices.size())
	for index in object.indices.size(): faces[index] = vertices[object.indices[index]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return {"surfaces": surfaces, "shape": shape}

static func begin_chunk(descriptor: Dictionary, origin_offset: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "Chunk_" + str(descriptor.key)
	root.position = WorldGenerator.origin_of(descriptor.key) - origin_offset
	var body := StaticBody3D.new()
	root.add_child(body)
	return {"key": descriptor.key, "root": root, "body": body, "data": descriptor.prepared if descriptor.has("prepared") else prepare_chunk(descriptor), "stage": 0, "index": 0}

static func advance_chunk(job: Dictionary, budget_us: int) -> bool:
	var began := Time.get_ticks_usec()
	while Time.get_ticks_usec() - began < maxi(200, budget_us):
		var collection: Array = job.data.collisions if job.stage == 0 else job.data.terrain if job.stage == 1 else job.data.buckets if job.stage == 2 else []
		if job.index >= collection.size():
			job.stage += 1
			job.index = 0
			if job.stage >= 3: return true
			continue
		var item: Dictionary = collection[job.index]
		job.index += 1
		if job.stage == 0:
			var collision := CollisionShape3D.new()
			collision.shape = item.shape
			collision.transform = item.transform
			job.body.add_child(collision)
		elif job.stage == 1:
			job.index -= 1
			if not job.has("terrain_mesh"):
				job.terrain_mesh = ArrayMesh.new()
				job.surface_index = 0
			var mesh: ArrayMesh = job.terrain_mesh
			if job.surface_index < item.surfaces.size():
				var surface: Dictionary = item.surfaces[job.surface_index]
				job.surface_index += 1
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.arrays)
				if not terrain_materials.has(surface.surface):
					var material := material_for(Color.WHITE, surface.surface).duplicate() as StandardMaterial3D
					material.vertex_color_use_as_albedo = true
					material.cull_mode = BaseMaterial3D.CULL_DISABLED
					terrain_materials[surface.surface] = material
				var material: StandardMaterial3D = terrain_materials[surface.surface]
				mesh.surface_set_material(mesh.get_surface_count() - 1, material)
				continue
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			job.root.add_child(instance)
			var collision := CollisionShape3D.new()
			collision.shape = item.shape
			job.body.add_child(collision)
			job.erase("terrain_mesh")
			job.erase("surface_index")
			job.index += 1
		else:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = _prototype(item)
			multimesh.instance_count = item.transforms.size()
			multimesh.custom_aabb = item.bounds.grow(0.05)
			for index in item.transforms.size(): multimesh.set_instance_transform(index, item.transforms[index])
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			if item.no_shadow: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			job.root.add_child(instance)
	return false

static func _prototype(bucket: Dictionary) -> PrimitiveMesh:
	if prototypes.has(bucket.style): return prototypes[bucket.style]
	var mesh: PrimitiveMesh
	if bucket.primitive in ["cylinder", "cone"]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.0 if bucket.primitive == "cone" else 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1
		cylinder.radial_segments = 10
		cylinder.rings = 1
		mesh = cylinder
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		if bucket.subdivided:
			box.subdivide_width = 2
			box.subdivide_height = 2
			box.subdivide_depth = 2
		mesh = box
	mesh.material = material_for(bucket.color, bucket.surface)
	prototypes[bucket.style] = mesh
	return mesh

static func create_chunk(descriptor: Dictionary, origin_offset: Vector3) -> Node3D:
	var job := begin_chunk(descriptor, origin_offset)
	while not advance_chunk(job, 1000000): pass
	return job.root

static func create_box(at: Vector3, size: Vector3, color: Color, solid: bool = true, surface: String = "paint") -> Node3D:
	return create_chunk({"key": Vector3i.ZERO, "objects": [WorldProvider.box("object", at, size, color, solid, surface)]}, Vector3.ZERO)
