class_name MissionPopEffects
extends Node3D
## Bounded, cosmetic confetti; positions stay in world space across origin shifts.
var bursts: Array[Dictionary] = []
const COLORS := [Color("ff779a"), Color("ffd863"), Color("6fe2bd"), Color("75bbff"), Color("c195ff"), Color("ffad65")]

func spawn(point: Vector3, index: int) -> void:
	if bursts.size() >= 4:
		bursts.pop_front().root.queue_free()
	var container := Node3D.new()
	add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = index * 787 + Time.get_ticks_usec()
	var shards: Array[Dictionary] = []
	var materials: Array[StandardMaterial3D] = []
	for color: Color in COLORS:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		materials.append(material)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.035, 0.24)
	for number in 36:
		var shard := MeshInstance3D.new()
		shard.mesh = mesh
		shard.material_override = materials[number % materials.size()]
		container.add_child(shard)
		shards.append({"node": shard, "point": point, "velocity": Vector3(rng.randf_range(-3.8, 3.8), rng.randf_range(1, 5), rng.randf_range(-3.8, 3.8)), "spin": Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))})
	bursts.append({"root": container, "shards": shards, "age": 0.0, "materials": materials})

func update_at(origin: Vector3, delta: float, paused: bool) -> void:
	for burst: Dictionary in bursts.duplicate():
		var step := 0.0 if paused else minf(delta, 0.1)
		burst.age += step
		if burst.age >= 1.8:
			burst.root.queue_free()
			bursts.erase(burst)
			continue
		for shard: Dictionary in burst.shards:
			shard.velocity.y -= step * 4
			shard.point += shard.velocity * step
			shard.node.position = shard.point - origin
			shard.node.rotation += shard.spin * step
		for material: StandardMaterial3D in burst.materials:
			material.albedo_color.a = minf(1, (1.8 - float(burst.age)) / 0.5)
