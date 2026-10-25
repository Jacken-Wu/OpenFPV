class_name GameAudioMixer
extends Node
## Shared buses are built once; settings contain preferences, never device indices.
const BUSES := {"master": "Master", "effects": "Effects", "motors": "Motors", "shutter": "Shutter", "music": "Music"}
const OUTPUT_GAIN_DB := 8.0
const OUTPUT_CEILING_DB := -1.0
const OUTPUT_LIMITER_NAME := "OpenFPV output headroom"
var settings := GameAudioSettings.defaults()
var device_timer := 0.0
var actual_device := ""

func _ready() -> void:
	for key: String in BUSES:
		var bus: String = BUSES[key]
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		if key != "master":
			AudioServer.set_bus_send(AudioServer.get_bus_index(bus), "Effects" if key in ["motors", "shutter"] else "Master")
	var master := AudioServer.get_bus_index("Master")
	var limiter: AudioEffectHardLimiter
	for index in AudioServer.get_bus_effect_count(master):
		var effect := AudioServer.get_bus_effect(master, index)
		if effect is AudioEffectHardLimiter and effect.resource_name == OUTPUT_LIMITER_NAME:
			limiter = effect
	if limiter == null:
		limiter = AudioEffectHardLimiter.new()
		limiter.resource_name = OUTPUT_LIMITER_NAME
		AudioServer.add_bus_effect(master, limiter)
	# Gain belongs before the ceiling; Master slider still attenuates afterwards.
	limiter.pre_gain_db = OUTPUT_GAIN_DB
	limiter.ceiling_db = OUTPUT_CEILING_DB
	limiter.release = 0.08
	apply(settings)

func apply(value: Dictionary) -> bool:
	if not GameAudioSettings.valid(value):
		return false
	settings = value.duplicate(true)
	for key: String in BUSES:
		var index := AudioServer.get_bus_index(BUSES[key])
		AudioServer.set_bus_mute(index, float(settings[key]) <= 0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, settings[key])))
	refresh_device()
	return true

func output_devices() -> PackedStringArray:
	return AudioServer.get_output_device_list()

func refresh_device() -> void:
	var devices := output_devices()
	var wanted: String = settings.output_device if devices.has(settings.output_device) else "Default"
	if AudioServer.output_device != wanted:
		AudioServer.output_device = wanted
	actual_device = AudioServer.output_device

func _process(delta: float) -> void:
	device_timer -= delta
	if device_timer <= 0:
		device_timer = 1.0
		refresh_device()

func set_session_master(amount: float) -> void:
	var next := settings.duplicate(true)
	next.master = amount
	apply(next)
