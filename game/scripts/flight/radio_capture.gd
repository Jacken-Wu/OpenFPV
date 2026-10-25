class_name RadioCapture
extends RefCounted
## One sampling session for all stick ranges, or one auxiliary control.

const MIN_TRAVEL := 0.4
var lows: Array[float] = []
var highs: Array[float] = []
var initial_buttons: Array[bool] = []
var changed_buttons: Array[int] = []

func begin(axes: Array[float], buttons: Array[bool] = []) -> void:
	lows.assign(axes)
	highs.assign(axes)
	initial_buttons.assign(buttons)
	changed_buttons.clear()

func sample(axes: Array[float], buttons: Array[bool] = []) -> void:
	for index in mini(axes.size(), lows.size()):
		lows[index] = minf(lows[index], axes[index])
		highs[index] = maxf(highs[index], axes[index])
	for index in mini(buttons.size(), initial_buttons.size()):
		if buttons[index] != initial_buttons[index] and not changed_buttons.has(index):
			changed_buttons.append(index)

func moved_axes(excluded: Array[int] = []) -> Array[int]:
	var result: Array[int] = []
	for index in lows.size():
		if not excluded.has(index) and highs[index] - lows[index] >= MIN_TRAVEL:
			result.append(index)
	return result

func stick_mapping(rest: Array[float], previous: Dictionary = {}) -> Dictionary:
	var detected := moved_axes()
	if detected.size() != 4 or rest.size() != lows.size():
		return {}
	# At rest, only the non-centering throttle should be near an endpoint.
	var throttle := -1
	for index in detected:
		var fraction := (rest[index] - lows[index]) / (highs[index] - lows[index])
		if fraction < 0.15 or fraction > 0.85:
			if throttle >= 0:
				return {}
			throttle = index
	if throttle < 0:
		return {}
	var remaining := detected.duplicate()
	remaining.erase(throttle)
	var result: Dictionary = {}
	for role: String in FlightInput.CHANNELS:
		var index := throttle
		if role != "throttle":
			var old_index := int(previous.get(role, {}).get("axis", -1))
			index = old_index if remaining.has(old_index) else int(remaining[0])
			remaining.erase(index)
		result[role] = {"axis": index, "min": lows[index], "max": highs[index], "center": rest[index], "invert": rest[index] > (lows[index] + highs[index]) * 0.5 if role == "throttle" else bool(previous.get(role, {}).get("invert", false)), "deadzone": previous.get(role, {}).get("deadzone", 0.025 if role != "throttle" else 0.0)}
	return result
