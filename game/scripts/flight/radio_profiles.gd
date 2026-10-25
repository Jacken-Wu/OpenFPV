class_name RadioProfiles
extends RefCounted
## Stable dictionary keys preserve old profiles while names can change safely.
static func name_error(profiles: Dictionary, name_value: String, editing_key: String = "") -> String:
	var name_text := name_value.strip_edges()
	if name_text.is_empty() or name_text.length() > 48:
		return "配置名称需要1～48个字符。"
	# Legacy duplicates stay editable; creating or renaming cannot add another.
	if profiles.has(editing_key) and String(profiles[editing_key].get("name", "")).strip_edges().nocasecmp_to(name_text) == 0:
		return ""
	for key: String in profiles:
		if key != editing_key and String(profiles[key].get("name", "")).strip_edges().nocasecmp_to(name_text) == 0:
			return "已存在同名配置，请换一个名称。"
	return ""

static func suggested_name(profiles: Dictionary) -> String:
	var name_text := "我的遥控器"
	var index := 2
	while not name_error(profiles, name_text).is_empty():
		name_text = "我的遥控器 %d" % index
		index += 1
	return name_text

static func upsert(settings: Dictionary, value: Dictionary, editing_key: String = "", activate: bool = false) -> Dictionary:
	if not FlightInput.valid_profile(value):
		return {"ok": false, "message": "遥控器配置无效。"}
	var profiles: Dictionary = settings.get("radio_profiles", {})
	if not editing_key.is_empty() and not profiles.has(editing_key):
		return {"ok": false, "message": "此配置已不存在，请刷新后重试。"}
	var name_text := String(value.get("name", "")).strip_edges()
	var error := name_error(profiles, name_text, editing_key)
	if not error.is_empty():
		return {"ok": false, "message": error}
	var key := editing_key
	if key.is_empty():
		key = "radio:" + str(Time.get_ticks_usec())
		while profiles.has(key):
			key += "_"
	var next := settings.duplicate(true)
	next.radio_profiles = profiles.duplicate(true)
	next.radio_profiles_managed = true
	var profile := value.duplicate(true)
	profile.name = name_text
	next.radio_profiles[key] = profile
	if activate:
		next.active_radio_profile = key
		next.radio_active = true
		next.radio_selection_required = false
	return {"ok": true, "settings": next, "key": key, "profile": profile}

static func remove(settings: Dictionary, key: String) -> Dictionary:
	if not settings.get("radio_profiles", {}).has(key):
		return {"ok": false, "message": "配置不存在。"}
	var next := settings.duplicate(true)
	next.radio_profiles.erase(key)
	next.radio_profiles_managed = true
	var selected: bool = settings.get("active_radio_profile", "") == key
	var active: bool = selected and settings.get("radio_active", false)
	if selected:
		next.erase("active_radio_profile")
	if active:
		next.radio_active = false
		next.radio_selection_required = true
	return {"ok": true, "settings": next, "active": active}
