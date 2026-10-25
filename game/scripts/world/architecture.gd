class_name Architecture
extends RefCounted
## Reusable, open structures. Content pools choose frequency; geometry never owns RNG.
const TYPES := {
	"park": {"name": "口袋公园", "size": Vector3(24, 7, 24)},
	"pavilion": {"name": "重檐亭", "size": Vector3(18, 11, 18)},
	"bus_stop": {"name": "城市候车站", "size": Vector3(24, 5, 10)},
	"courtyard": {"name": "回廊古院", "size": Vector3(26, 13, 26)},
	"twin_towers": {"name": "连桥双塔", "size": Vector3(26, 72, 26)},
	"radio_tower": {"name": "格构通信塔", "size": Vector3(24, 66, 24)},
	"pyramid": {"name": "风蚀金字塔", "size": Vector3(54, 32, 54)},
	"ruins": {"name": "残柱遗迹", "size": Vector3(30, 15, 30)},
	"base_station": {"name": "荒野基站", "size": Vector3(24, 20, 24)},
	"aqueduct": {"name": "古代渡槽", "size": Vector3(44, 23, 22)},
	"sky_colonnade": {"name": "云端环廊", "size": Vector3(20, 10, 20)},
	"hangar": {"name": "开放机库", "size": Vector3(26, 16, 26)},
	"turbines": {"name": "地下涡轮厅", "size": Vector3(12, 12, 12)},
	"construction": {"name": "中庭工地与塔吊", "size": Vector3(44, 48, 38)},
	"open_house": {"name": "天窗贯通住宅", "size": Vector3(24, 10, 22)},
	"playground": {"name": "彩虹儿童公园", "size": Vector3(24, 12, 24)},
	"pipe_stack": {"name": "中空管道堆", "size": Vector3(13, 12, 14)},
	"billboard": {"name": "路侧广告牌", "size": Vector3(18, 13, 4)},
	"tri_billboard": {"name": "三面中空广告架", "size": Vector3(20, 12, 20)},
	"mega_ruins": {"name": "巨石三重门遗迹", "size": Vector3(60, 40, 64)},
	"broken_blocks": {"name": "断壁残楼", "size": Vector3(56, 18, 26)},
	"rock_arch": {"name": "风蚀岩门", "size": Vector3(32, 30, 14)},
	"ice_arch": {"name": "冰川拱门", "size": Vector3(32, 30, 14)},
	"lava_arch": {"name": "玄武岩熔光门", "size": Vector3(32, 30, 14)}
}

static func build(kind: String, id: String, point: Vector3, variant: float = 0.5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stone := Color("baa98a")
	var steel := Color("719092")
	if kind in ["construction", "open_house", "playground", "pipe_stack", "billboard", "tri_billboard", "mega_ruins", "broken_blocks", "rock_arch", "ice_arch", "lava_arch"]:
		out = OpenStructures.build(kind, id, variant)
	match kind:
		"park":
			add(out, id, "lawn", Vector3(0, 0.12, 0), Vector3(24, 0.24, 24), Color("789562"), "grass")
			add(out, id, "path", Vector3(0, 0.28, 0), Vector3(6, 0.2, 24), stone, "concrete")
			for side: float in [-1, 1]:
				for row: float in [-1, 1]:
					var p := Vector3(side * 8, 0, row * 7)
					add(out, id, "planter%s%s" % [side, row], p + Vector3.UP * 0.5, Vector3(4, 1, 4), stone, "brick")
					add(out, id, "trunk%s%s" % [side, row], p + Vector3.UP * 2, Vector3(0.6, 4, 0.6), Color("675543"), "bark", "cylinder")
					add(out, id, "tree%s%s" % [side, row], p + Vector3.UP * 4.7, Vector3(4.8, 4.5, 4.8), Color("719455"), "foliage", "cone")
				add(out, id, "bench%s" % side, Vector3(side * 6, 0.7, 0), Vector3(1.5, 1.4, 5), Color("ad875c"), "bark")
		"pavilion", "sky_colonnade":
			var wide := 7.0 if kind == "pavilion" else 8.0
			for x: float in [-wide, wide]:
				for z: float in [-wide, wide]:
					add(out, id, "column%s%s" % [x, z], Vector3(x, 4.4, z), Vector3(1.1, 8.8, 1.1), stone, "concrete")
			for tier in 3:
				add(out, id, "eave%d" % tier, Vector3(0, 8.5 + tier * 0.6, 0), Vector3(18 - tier * 3, 0.6, 18 - tier * 3), Color("95634c") if kind == "pavilion" else steel, "tile" if kind == "pavilion" else "metal")
		"bus_stop":
			add(out, id, "canopy", Vector3(0, 4.6, 0), Vector3(24, 0.6, 10), steel, "metal")
			for x: float in [-10, 10]:
				add(out, id, "post%s" % x, Vector3(x, 2.3, -3.5), Vector3(0.55, 4.6, 0.55), steel, "metal")
			add(out, id, "glass", Vector3(0, 2.3, -4), Vector3(20, 4, 0.15), Color("66979e"), "glass")
			add(out, id, "seat", Vector3(-5, 0.7, -2), Vector3(8, 1.4, 1.6), Color("c3a16b"), "bark")
			add(out, id, "sign", Vector3(11, 3.5, 3), Vector3(1.3, 3, 0.4), Color("c5e6bc"), "screen")
		"courtyard":
			for x: float in [-10, 10]:
				add(out, id, "wing%s" % x, Vector3(x, 4, 0), Vector3(6, 8, 24), Color("b99272"), "brick")
				add(out, id, "roof%s" % x, Vector3(x, 8.5, 0), Vector3(8, 1, 26), Color("975b45"), "tile")
				for z: float in [-8, 0, 8]:
					add(out, id, "gallery%s%s" % [x, z], Vector3(x * 0.6, 3, z), Vector3(0.7, 6, 0.7), stone, "concrete")
			add(out, id, "rear", Vector3(0, 5, -10), Vector3(14, 10, 6), Color("b99272"), "brick")
			add(out, id, "rear_roof", Vector3(0, 10.5, -10), Vector3(17, 1.2, 9), Color("975b45"), "tile")
		"twin_towers":
			var height := 44.0 + variant * 28
			for x: float in [-8.5, 8.5]:
				add(out, id, "tower%s" % x, Vector3(x, height * 0.5, 0), Vector3(8, height, 21), Color("a9c3c1"), "plaster")
				for floor_index in range(1, int(height / 4)):
					add(out, id, "window%s_%d" % [x, floor_index], Vector3(x, floor_index * 4, 10.55), Vector3(7, 2, 0.08), Color("537e91"), "glass", "box", false)
			add(out, id, "skybridge", Vector3(0, height * 0.62, 0), Vector3(10, 2, 6), steel, "metal")
		"radio_tower":
			var height := 44.0 + variant * 20
			for x: float in [-1, 1]:
				for z: float in [-1, 1]:
					beam(out, id, "leg%s%s" % [x, z], Vector3(x * 9, 0, z * 9), Vector3(x * 2, height, z * 2), 0.85, steel)
			for tier in 5:
				var y := tier * height / 5
				var r := lerpf(9, 2, float(tier) / 5)
				for side: float in [-1, 1]:
					beam(out, id, "brace_x%d%s" % [tier, side], Vector3(-r, y, r * side), Vector3(r - 1.4, y + height / 5, (r - 1.4) * side), 0.45, steel)
					beam(out, id, "brace_z%d%s" % [tier, side], Vector3(r * side, y, -r), Vector3((r - 1.4) * side, y + height / 5, r - 1.4), 0.45, steel)
			add(out, id, "deck", Vector3(0, height - 3, 0), Vector3(9, 0.6, 9), steel, "metal")
		"pyramid":
			for tier in 8:
				var width := 54.0 - tier * 6
				var y := 2.0 + tier * 4
				if tier < 3:
					for side: float in [-1, 1]:
						add(out, id, "stair%d%s" % [tier, side], Vector3(side * (width + 10) / 4, y, 0), Vector3((width - 10) / 2, 4, width), Color("cbb082"), "sandstone")
				else:
					add(out, id, "cap%d" % tier, Vector3(0, y, 0), Vector3(width, 4, width), Color("cbb082"), "sandstone")
		"ruins":
			for index in 8:
				var x := (index % 4 - 1.5) * 7
				var z := -9.0 if index < 4 else 9.0
				var h := 5.0 + fmod(index * 3.17 + variant * 9, 9)
				add(out, id, "pillar%d" % index, Vector3(x, h / 2, z), Vector3(2, h, 2), stone, "sandstone")
			add(out, id, "lintel", Vector3(-6, 10, 9), Vector3(12, 1.5, 3), stone, "sandstone")
		"base_station":
			for side: float in [-1, 1]:
				add(out, id, "module%s" % side, Vector3(side * 8, 3, 0), Vector3(6, 6, 18), steel, "metal")
				add(out, id, "mast%s" % side, Vector3(side * 8, 12, -6), Vector3(0.7, 14, 0.7), steel, "metal")
				add(out, id, "antenna%s" % side, Vector3(side * 8, 17, -6), Vector3(2, 4, 0.6), Color("e0d7b3"), "paint")
			add(out, id, "walkway", Vector3(0, 5.5, -6), Vector3(12, 0.5, 3), steel, "metal")
		"aqueduct":
			for x: float in [-18, -6, 6, 18]:
				for z: float in [-8, 8]:
					add(out, id, "pier%s%s" % [x, z], Vector3(x, 9, z), Vector3(2, 18, 3), stone, "sandstone")
			for z: float in [-7, 7]:
				add(out, id, "channel%s" % z, Vector3(0, 19, z), Vector3(44, 4, 6), stone, "sandstone")
		"hangar":
			for x: float in [-11.5, 11.5]:
				add(out, id, "wall%s" % x, Vector3(x, 6, 0), Vector3(3, 12, 26), steel, "metal")
			add(out, id, "roof", Vector3(0, 13, 0), Vector3(26, 2, 26), steel, "metal")
			for z: float in [-8, 0, 8]:
				add(out, id, "roof_rib%s" % z, Vector3(0, 15, z), Vector3(25, 1, 0.6), Color("d9bb76"), "metal")
		"turbines":
			for x: float in [-4.5, 4.5]:
				for z: float in [-4.5, 4.5]:
					add(out, id, "turbine%s%s" % [x, z], Vector3(x, 3, z), Vector3(2, 6, 2), steel, "metal", "cylinder")
					add(out, id, "housing%s%s" % [x, z], Vector3(x, 0.4, z), Vector3(2.8, 0.8, 2.8), Color("557678"), "metal")
					add(out, id, "cap%s%s" % [x, z], Vector3(x, 6.3, z), Vector3(2.6, 0.5, 2.6), Color("b8c8b7"), "metal", "cylinder")
					for blade in 3:
						var fan := WorldProvider.box(id + "/fan%s%s_%d" % [x, z, blade], Vector3(x, 6.65, z), Vector3(2, 0.14, 0.35), Color("536c75"), true, "metal")
						fan.rotation = Vector3(0, blade * TAU / 3, 0)
						out.append(fan)
			for x: float in [-5, 5]:
				add(out, id, "duct%s" % x, Vector3(x, 10.5, 0), Vector3(1.5, 1.5, 12), Color("b49c72"), "metal")
	for object in out:
		object.center += point
	return out

static func add(out: Array[Dictionary], id: String, part: String, point: Vector3, size: Vector3, color: Color, surface: String, primitive: String = "box", solid: bool = true) -> void:
	var object := WorldProvider.box(id + "/" + part, point, size, color, solid, surface)
	object.primitive = primitive
	out.append(object)

static func beam(out: Array[Dictionary], id: String, part: String, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var up := (b - a).normalized()
	var right := (Vector3.UP if absf(up.dot(Vector3.FORWARD)) > 0.95 else Vector3.FORWARD).cross(up).normalized()
	var object := WorldProvider.box(id + "/" + part, (a + b) / 2, Vector3(width, a.distance_to(b), width), color, true, "metal")
	object.rotation = Basis(right, up, right.cross(up)).get_euler()
	out.append(object)
