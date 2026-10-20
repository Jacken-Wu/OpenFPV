class_name WorldGeometry
extends RefCounted

static var materials: Dictionary = {}

static func material_for(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if materials.has(key):
		return materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.35
	var pixels := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for x in 8:
		for y in 8:
			var shade := 0.89 + WorldProvider.noise_at(x, y, 17) * 0.11
			pixels.set_pixel(x, y, Color(shade, shade, shade))
	mat.albedo_texture = ImageTexture.create_from_image(pixels)
	materials[key] = mat
	return mat

static func create_chunk(descriptor: Dictionary, origin_offset: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Chunk_" + str(descriptor.key)
	var chunk_origin := WorldGenerator.origin_of(descriptor.key)
	root.position = chunk_origin - origin_offset
	var body := StaticBody3D.new()
	root.add_child(body)
	var buckets: Dictionary = {}
	for object: Dictionary in descriptor.objects:
		var color: Color = object.color
		var bucket := color.to_html()
		if not buckets.has(bucket):
			buckets[bucket] = {"color": color, "transforms": []}
		buckets[bucket].transforms.append(Transform3D(Basis.from_scale(object.size), object.center - chunk_origin))
		if object.solid:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = object.size
			shape.shape = box
			shape.position = object.center - chunk_origin
			body.add_child(shape)
	for bucket: Dictionary in buckets.values():
		var instance := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = material_for(bucket.color)
		multimesh.mesh = mesh
		multimesh.instance_count = bucket.transforms.size()
		for index in bucket.transforms.size():
			multimesh.set_instance_transform(index, bucket.transforms[index])
		instance.multimesh = multimesh
		root.add_child(instance)
	return root

static func create_box(at: Vector3, size: Vector3, color: Color, solid: bool = true) -> Node3D:
	return create_chunk({"key": Vector3i.ZERO, "objects": [WorldProvider.box("object", at, size, color, solid)]}, Vector3.ZERO)
