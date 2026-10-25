class_name FlightTuning
extends RefCounted
## Shared settings and curve math for UI, persistence and the flight controller.

const AXES: Array[String] = ["roll", "pitch", "yaw"]
const RULES := {
	"max_rate_dps": {"min": 30.0, "max": 1200.0, "step": 1.0},
	"expo": {"min": 0.0, "max": 0.95, "step": 0.01},
	"gravity": {"min": 0.0, "max": 30.0, "step": 0.01},
	"air_drag": {"min": 0.0, "max": 5.0, "step": 0.05},
	"angular_drag": {"min": 0.0, "max": 5.0, "step": 0.05},
	"p": {"min": 0.0, "max": 80.0, "step": 0.5},
	"i": {"min": 0.0, "max": 40.0, "step": 0.1},
	"d": {"min": 0.0, "max": 4.0, "step": 0.05},
	"d_filter_hz": {"min": 5.0, "max": 60.0, "step": 1.0},
}

static func defaults() -> Dictionary:
	return {"axes": {"roll": {"max_rate_dps": 360.0, "expo": 0.25}, "pitch": {"max_rate_dps": 360.0, "expo": 0.25}, "yaw": {"max_rate_dps": 252.0, "expo": 0.25}}, "pid": {"roll": {"p": 36.0, "i": 3.0, "d": 1.8}, "pitch": {"p": 36.0, "i": 3.0, "d": 1.8}, "yaw": {"p": 28.0, "i": 3.0, "d": 1.3}}, "d_filter_hz": 20.0, "gravity": 9.81, "air_drag": 1.0, "angular_drag": 1.0}

static func with_pid(value: Dictionary) -> Dictionary:
	var next := value.duplicate(true)
	if not next.has("pid"):
		next.pid = defaults().pid
	if not next.has("d_filter_hz"):
		next.d_filter_hz = defaults().d_filter_hz
	return next

static func valid_number(value: Variant, key: String) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= RULES[key].min and value <= RULES[key].max

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["axes", "gravity", "air_drag", "angular_drag"]) or not value.axes is Dictionary:
		return false
	for key: String in ["gravity", "air_drag", "angular_drag"]:
		if not valid_number(value[key], key):
			return false
	for axis: String in AXES:
		if not value.axes.get(axis) is Dictionary or not value.axes[axis].has_all(["max_rate_dps", "expo"]):
			return false
		for key: String in ["max_rate_dps", "expo"]:
			if not valid_number(value.axes[axis][key], key):
				return false
	if value.has("pid"):
		if not value.pid is Dictionary:
			return false
		for axis in AXES:
			if not value.pid.get(axis) is Dictionary:
				return false
			for key: String in ["p", "i", "d"]:
				if not valid_number(value.pid[axis].get(key), key):
					return false
	if value.has("d_filter_hz") and not valid_number(value.d_filter_hz, "d_filter_hz"):
		return false
	return true

static func from_settings(settings: Dictionary) -> Dictionary:
	if settings.has("flight"):
		return with_pid(settings.flight) if valid(settings.flight) else defaults()
	var value := defaults()
	var old_rate: Variant = settings.get("rates", 360.0)
	var old_expo: Variant = settings.get("expo", 0.25)
	var rate := clampf(float(old_rate), 180, 600) if (old_rate is float or old_rate is int) and is_finite(float(old_rate)) else 360.0
	var curve := clampf(float(old_expo), 0, 0.6) if (old_expo is float or old_expo is int) and is_finite(float(old_expo)) else 0.25
	for axis in AXES:
		value.axes[axis] = {"max_rate_dps": rate * (0.7 if axis == "yaw" else 1.0), "expo": curve}
	return value

static func response(input: float, axis: Dictionary) -> float:
	var x := clampf(input, -1, 1)
	var curve := float(axis.expo)
	return float(axis.max_rate_dps) * (x * (1.0 - curve) + x * x * x * curve)
