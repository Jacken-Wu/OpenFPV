extends SceneTree

var failed := 0

func check(condition: bool, description: String) -> void:
	print("PASS " if condition else "FAIL ", description)
	if not condition:
		failed += 1

func _initialize() -> void:
	var axis := {"axis": 0, "min": -0.8, "max": 0.9, "center": 0.1, "invert": false, "deadzone": 0.025}
	check(is_equal_approx(FlightInput.normalize_axis(0.1, axis, false), 0), "asymmetric RC center calibrates to zero")
	check(is_equal_approx(FlightInput.normalize_axis(-0.8, axis, false), -1) and is_equal_approx(FlightInput.normalize_axis(0.9, axis, false), 1), "independent full travel reaches both endpoints")
	var diagonal := Vector2(FlightInput.normalize_axis(0.9, axis, false), FlightInput.normalize_axis(0.9, axis, false))
	check(diagonal == Vector2.ONE, "simultaneous full roll and pitch are never circular-normalized")
	check(FlightInput.normalize_axis(-0.8, axis, true) == 0 and FlightInput.normalize_axis(0.9, axis, true) == 1, "non-centering throttle maps full travel to 0..1")
	axis.invert = true
	check(FlightInput.normalize_axis(0.9, axis, false) == -1 and FlightInput.normalize_axis(0.9, axis, true) == 0, "reversed throttle and attitude channels")
	var profile := {"axes": {}}
	for index in 4:
		profile.axes[FlightInput.CHANNELS[index]] = axis.duplicate()
		profile.axes[FlightInput.CHANNELS[index]].axis = index
	check(FlightInput.valid_profile(profile), "valid calibration profile")
	profile.axes.throttle.axis = 0
	check(not FlightInput.valid_profile(profile), "duplicate RC axes rejected")
	var reader := FlightInput.new()
	reader._ready()
	reader.keyboard_throttle = 0.9
	reader.channels = Vector4.ZERO
	check(is_equal_approx(reader.current_channels().w, 0.9), "current throttle is sampled rather than stale displayed channels")
	reader.using_radio = true
	reader.selected_device = 99
	check(reader.current_channels() == Vector4.ZERO, "missing active device provides no flight controls")
	reader.free()
	print("INPUT_RESULT failures=", failed)
	quit(1 if failed else 0)
