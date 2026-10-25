class_name DeveloperCommands
extends RefCounted
var game: Node
var last_location: Dictionary = {}
var seed_at_location := 0
const HELP := "/location list：群系名称和 ID\n/location <名称或 ID>：最近生成中心及其平台坐标（含未探索群系）\n/tp location：前往上次定位的平台；/tp <x> <y> <z>：调试传送\n/pos：世界坐标和动力状态；/seed：世界种子；/volume <0~100>：本次音量\n/clear：清屏；/help：帮助；Esc：关闭；↑/↓：历史指令"

func _init(value: Node) -> void:
	game = value

func execute(text: String) -> String:
	var tokens := text.strip_edges().replace("\t", " ").split(" ", false)
	if tokens.is_empty():
		return "请输入指令；/help 查看帮助。"
	var command := String(tokens[0]).trim_prefix("/").to_lower()
	match command:
		"help": return HELP
		"clear": return ""
		"seed": return "世界种子 %d · 世界版本 %d" % [game.store.data.seed, game.store.data.world_version]
		"pos":
			var point: Vector3 = game._world_position()
			return "世界坐标 %.2f, %.2f, %.2f · %s" % [point.x, point.y, point.z, "高度保护断油中" if game.drone.altitude_cutoff else "动力正常"]
		"location":
			if not game.store.regions is BiomeWorld:
				return "当前世界版本不支持群系定位。"
			var locator := BiomeLocator.new(game.store.regions)
			if tokens.size() == 1 or tokens[1].to_lower() == "list":
				var rows := PackedStringArray(["群系名称 / 简写 / 完整 ID"])
				for choice in locator.choices():
					rows.append("%s / %s / %s" % [choice.name, choice.biome.id.get_slice(".", 2).trim_suffix("_fixture"), choice.biome.id])
				return "\n".join(rows)
			last_location = locator.locate(" ".join(tokens.slice(1)), game._world_position())
			seed_at_location = int(game.store.data.seed)
			return last_location.message
		"tp":
			var point := Vector3.ZERO
			if tokens.size() == 2 and tokens[1].to_lower() == "location":
				if not last_location.get("ok", false) or seed_at_location != int(game.store.data.seed):
					return "请先使用 /location <群系> 定位当前种子的目标。"
				point = last_location.point
			elif tokens.size() == 4:
				for index in range(1, 4):
					if not String(tokens[index]).is_valid_float():
						return "坐标必须是有限数字；用法 /tp <x> <y> <z>。"
				point = Vector3(float(tokens[1]), float(tokens[2]), float(tokens[3]))
			else:
				return "用法 /tp <x> <y> <z> 或 /tp location。"
			if not point.is_finite() or maxf(maxf(absf(point.x), absf(point.y)), absf(point.z)) > 10000000:
				return "坐标必须有限且各轴在 ±10000000 m 内。"
			game._debug_teleport(point)
			return "调试传送至 %.1f, %.1f, %.1f · Esc 关闭，等待地图就绪；不登记传送点。" % [point.x, point.y, point.z]
		"volume":
			if tokens.size() != 2 or not String(tokens[1]).is_valid_float():
				return "用法 /volume <0~100>，仅修改本次运行音量。"
			var volume := float(tokens[1])
			if not is_finite(volume) or volume < 0 or volume > 100:
				return "音量应为 0~100。"
			game.audio_mixer.set_session_master(volume / 100)
			return "本次音量 %.0f%%" % volume
	return "未知指令；/help 查看帮助。"
