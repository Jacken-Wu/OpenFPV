class_name OpenStructures
extends RefCounted
## Local-space compound solids leave their openings empty in both mesh and physics.
static func build(kind: String, id: String, variant: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stone := Color("b3aaa0")
	var steel := Color("7b969e")
	match kind:
		"construction":
			for floor_index in 4:
				var y := floor_index * 10.0
				for x: float in [-12, 12]:
					Architecture.add(out, id, "deck%d%s" % [floor_index, x], Vector3(x, y + 0.3, 0), Vector3(12, 0.6, 36), stone, "concrete")
				for z: float in [-12, 12]:
					Architecture.add(out, id, "cross%d%s" % [floor_index, z], Vector3(0, y + 0.3, z), Vector3(12, 0.6, 12), stone, "concrete")
				for x: float in [-16, 16]:
					for z: float in [-16, 16]:
						Architecture.add(out, id, "post%d%s%s" % [floor_index, x, z], Vector3(x, y + 5, z), Vector3(1, 10, 1), stone, "concrete")
			Architecture.add(out, id, "crane", Vector3(19, 23, -17), Vector3(1.2, 46, 1.2), Color("e9bb4e"), "metal")
			Architecture.add(out, id, "jib", Vector3(1, 45, -17), Vector3(42, 0.8, 1.8), Color("e9bb4e"), "metal")
			Architecture.add(out, id, "cable", Vector3(-15, 35, -17), Vector3(0.15, 20, 0.15), steel, "metal")
		"open_house":
			Architecture.add(out, id, "floor", Vector3(0, 0.2, 0), Vector3(24, 0.4, 20), stone, "concrete")
			for z: float in [-10, 10]:
				for x: float in [-7.5, 7.5]:
					Architecture.add(out, id, "front%s%s" % [z, x], Vector3(x, 4, z), Vector3(9, 8, 0.5), Color("c8b49a"), "plaster")
				Architecture.add(out, id, "lintel%s" % z, Vector3(0, 6.7, z), Vector3(6, 2.6, 0.5), Color("c8b49a"), "plaster")
			for x: float in [-12, 12]:
				Architecture.add(out, id, "sill%s" % x, Vector3(x, 1.4, 0), Vector3(0.5, 2.8, 20), Color("c8b49a"), "brick")
				Architecture.add(out, id, "upper%s" % x, Vector3(x, 7, 0), Vector3(0.5, 2, 20), Color("c8b49a"), "plaster")
				for z: float in [-7, 0, 7]:
					Architecture.add(out, id, "mullion%s%s" % [x, z], Vector3(x, 4.4, z), Vector3(0.5, 3.2, 1.2), stone, "brick")
			for x: float in [-8, 8]:
				Architecture.add(out, id, "roof%s" % x, Vector3(x, 8.5, 0), Vector3(8, 0.7, 22), Color("966650"), "tile")
			for z: float in [-7, 7]:
				Architecture.add(out, id, "roofcap%s" % z, Vector3(0, 8.5, z), Vector3(8, 0.7, 8), Color("966650"), "tile")
		"playground":
			Architecture.add(out, id, "lawn", Vector3(0, 0.1, 0), Vector3(24, 0.2, 24), Color("91ad71"), "grass")
			for x: float in [-9, -1]:
				for z: float in [-7, -3]:
					Architecture.add(out, id, "swing%s%s" % [x, z], Vector3(x, 3, z), Vector3(0.4, 6, 0.4), Color("dc8e6c"), "metal")
			Architecture.add(out, id, "swingbar", Vector3(-5, 6, -5), Vector3(9, 0.4, 0.4), Color("dc8e6c"), "metal")
			for x: float in [-9, -1]:
				Architecture.add(out, id, "swingbrace%s" % x, Vector3(x, 6, -5), Vector3(0.4, 0.4, 4), Color("dc8e6c"), "metal")
			for x: float in [-7, -3]:
				Architecture.add(out, id, "rope%s" % x, Vector3(x, 3.7, -5), Vector3(0.12, 4.4, 0.12), steel, "metal")
				Architecture.add(out, id, "seat%s" % x, Vector3(x, 1.5, -5), Vector3(1.6, 0.2, 1.6), Color("e2ba56"), "paint")
			pipe(out, id + "/tunnel", Vector3(4, 2.8, 5), 2.2, 10, Color("e6bc57"))
			Architecture.beam(out, id, "slide", Vector3(10, 0.5, -4), Vector3(10, 6, 6), 1.5, Color("7ebdca"))
			for x: float in [-10, -6]:
				for z: float in [3, 9]:
					Architecture.add(out, id, "climb%s%s" % [x, z], Vector3(x, 4, z), Vector3(0.35, 8, 0.35), Color("7ebdca"), "metal")
			for y: float in [4, 8]:
				for x: float in [-10, -6]:
					Architecture.add(out, id, "rail%s%s" % [x, y], Vector3(x, y, 6), Vector3(0.35, 0.35, 6), Color("7ebdca"), "metal")
				for z: float in [3, 9]:
					Architecture.add(out, id, "rung%s%s" % [z, y], Vector3(-8, y, z), Vector3(4, 0.35, 0.35), Color("e7b95a"), "metal")
			Architecture.add(out, id, "slidepost", Vector3(10, 3, 6), Vector3(0.4, 6, 0.4), Color("7ebdca"), "metal")
		"pipe_stack":
			for x: float in [-3, 3]:
				pipe(out, id + "/lower%s" % x, Vector3(x, 3, 0), 2.6, 12, stone)
			pipe(out, id + "/upper", Vector3(0, 8.3, 0), 2.6, 12, stone)
		"billboard":
			for x: float in [-6, 6]:
				Architecture.add(out, id, "post%s" % x, Vector3(x, 5, 0), Vector3(0.6, 10, 0.6), steel, "metal")
			Architecture.add(out, id, "panel", Vector3(0, 10, 0), Vector3(17, 5, 0.5), Color("d88d65"), "screen")
			for x: float in [-5, 0, 5]:
				Architecture.add(out, id, "stripe%s" % x, Vector3(x, 10, 0.29), Vector3(2, 3, 0.1), Color("f1d9a6"), "paint")
		"tri_billboard":
			for index in 3:
				var angle := index * TAU / 3
				var a := Vector3(cos(angle) * 9, 0, sin(angle) * 9)
				var b := Vector3(cos(angle + TAU / 3) * 9, 0, sin(angle + TAU / 3) * 9)
				Architecture.add(out, id, "post%d" % index, a + Vector3.UP * 5.5, Vector3(0.65, 11, 0.65), steel, "metal")
				Architecture.beam(out, id, "edge%d" % index, a + Vector3.UP * 7.5, b + Vector3.UP * 7.5, 0.4, steel)
				var panel := WorldProvider.box(id + "/panel%d" % index, (a + b) / 2 + Vector3.UP * 10, Vector3(a.distance_to(b), 3, 0.4), [Color("70b9ba"), Color("d69770"), Color("a2ad6c")][index], true, "screen")
				panel.rotation = Vector3(0, -atan2((b - a).z, (b - a).x), 0)
				out.append(panel)
		"mega_ruins":
			for row in 3:
				for x: float in [-18, 18]:
					var height := 36.0 - row * 4
					Architecture.add(out, id, "monolith%d%s" % [row, x], Vector3(x, height * 0.5, row * 20 - 20), Vector3(6, height, 6), stone, "sandstone")
				Architecture.add(out, id, "lintel%d" % row, Vector3(0, 35 - row * 4, row * 20 - 20), Vector3(42, 3, 7), stone, "sandstone")
			for x: float in [-26, 26]:
				Architecture.add(out, id, "gallery%s" % x, Vector3(x, 14, 0), Vector3(7, 2, 58), Color("938a78"), "sandstone")
		"broken_blocks":
			for index in 5:
				var x := (index - 2) * 10.0
				Architecture.add(out, id, "stump%d" % index, Vector3(x, 4, -8), Vector3(4, 8 + fmod(index * 3 + variant * 9, 8), 5), Color("8c8c7f"), "concrete")
				Architecture.add(out, id, "beam%d" % index, Vector3(x + 3, 11, -8), Vector3(10, 1, 5), Color("8c8c7f"), "concrete")
		"rock_arch", "ice_arch", "lava_arch":
			var color := Color("c7e4eb") if kind == "ice_arch" else Color("504d4e") if kind == "lava_arch" else Color("bca07e")
			for x: float in [-12, 12]:
				Architecture.add(out, id, "pier%s" % x, Vector3(x, 12, 0), Vector3(7, 24, 12), color, "snow" if kind == "ice_arch" else "sandstone")
			Architecture.add(out, id, "span", Vector3(0, 25, 0), Vector3(31, 6, 12), color, "snow" if kind == "ice_arch" else "sandstone")
			if kind == "lava_arch":
				for x: float in [-12, 12]:
					Architecture.add(out, id, "glow%s" % x, Vector3(x, 7, 6.1), Vector3(0.3, 12, 0.1), Color("ec783c"), "lava", "box", false)
	return out

static func pipe(out: Array[Dictionary], id: String, center: Vector3, radius: float, length: float, color: Color) -> void:
	for index in 12:
		var angle := index * TAU / 12
		var object := WorldProvider.box(id + "/shell%d" % index, center + Vector3(cos(angle), sin(angle), 0) * radius, Vector3(0.45, radius * 2 * tan(PI / 12) + 0.12, length), color, true, "concrete")
		object.rotation = Vector3(0, 0, angle)
		out.append(object)
