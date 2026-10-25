class_name GameEventAudio
extends Node
## Original short earcons. One queued voice prevents simultaneous unlocks piling up.
const CUES := {
	"achievement": {"notes": [880, 1109, 1319, 1760], "step": 0.15},
	"portal": {"notes": [392, 587, 784, 988], "step": 0.13},
	"region": {"notes": [523, 659, 784], "step": 0.12},
	"discovery": {"notes": [330, 440], "step": 0.12},
	"accept": {"notes": [523, 784], "step": 0.08},
	"complete": {"notes": [659, 880, 1047], "step": 0.13},
	"purchase": {"notes": [988, 659, 1319], "step": 0.075},
	"teleport": {"notes": [523, 392, 784, 1047], "step": 0.10},
	"failure": {"notes": [392, 330, 262], "step": 0.11}
}
var streams: Dictionary = {}
var pending: Array[String] = []
var player: AudioStreamPlayer
var cooldown: Dictionary = {}
var current := ""

func _ready() -> void:
	for key: String in CUES:
		streams[key] = synthesize(key)
	player = AudioStreamPlayer.new()
	player.bus = "Effects"
	player.volume_db = -9
	add_child(player)
	player.finished.connect(_next)

func play_event(event: String) -> void:
	if not CUES.has(event) or pending.has(event) or Time.get_ticks_msec() - int(cooldown.get(event, -10000)) < 400:
		return
	cooldown[event] = Time.get_ticks_msec()
	if pending.size() < 8:
		pending.append(event)
	if not player.playing:
		_next()

func _next() -> void:
	current = ""
	if pending.is_empty():
		return
	current = pending.pop_front()
	player.stream = streams[current]
	if DisplayServer.get_name() != "headless":
		player.play()

func _exit_tree() -> void:
	if is_instance_valid(player):
		player.stop()

static func synthesize(event: String) -> AudioStreamWAV:
	var cue: Dictionary = CUES[event]
	var step := float(cue.step)
	var samples := PackedFloat32Array()
	samples.resize(roundi((cue.notes.size() * step + 0.12) * FlightAudio.SAMPLE_RATE))
	for index in samples.size():
		var time := float(index) / FlightAudio.SAMPLE_RATE
		var slot := mini(cue.notes.size() - 1, int(time / step))
		var age := time - slot * step
		var length := step + (0.12 if slot == cue.notes.size() - 1 else 0.0)
		var envelope := minf(1, age / 0.008) * minf(1, maxf(0, length - age) / 0.055) * exp(-age * 2)
		var phase := TAU * float(cue.notes[slot]) * age
		samples[index] = (sin(phase) * 0.42 + sin(phase * 2) * 0.065 + sin(phase * 3) * 0.025) * envelope
	return FlightAudio._pcm(samples, false)
