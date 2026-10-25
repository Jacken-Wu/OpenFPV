class_name GameAudioSettings
extends RefCounted

const LABELS := {"master": "主音量", "effects": "音效总音量", "motors": "电机 / 螺旋桨", "shutter": "拍照快门", "music": "背景音乐"}

static func defaults() -> Dictionary:
	return {"output_device": "Default", "master": 0.8, "effects": 1.0, "motors": 1.0, "shutter": 1.0, "music": 0.45}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or not value.get("output_device") is String or value.output_device.is_empty():
		return false
	for key: String in LABELS:
		var amount: Variant = value.get(key)
		if not FlightInput.finite_number(amount) or amount < 0 or amount > 1:
			return false
	return true

static func from_settings(settings: Dictionary) -> Dictionary:
	return settings.audio.duplicate(true) if valid(settings.get("audio")) else defaults()
