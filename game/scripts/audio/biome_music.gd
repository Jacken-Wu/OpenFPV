class_name BiomeMusic
extends Node
## Two native streams, bounded memory and equal-power biome transitions.
const FADE_SECONDS := 2.0
const STABLE_SECONDS := 0.65
const MUSIC_GAIN_DB := -6.0
var players: Array[AudioStreamPlayer] = []
var gains := Vector2.ZERO
var start_gains := Vector2.ZERO
var target_gains := Vector2.ZERO
var target_stream: AudioStream
var candidate: AudioStream
var candidate_time := 0.0
var fade_time := FADE_SECONDS
var current_title := ""

func _ready() -> void:
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.bus = "Music"
		player.volume_db = -80
		add_child(player)
		players.append(player)

func observe(biome: BiomeDefinition, delta: float) -> void:
	var stream: AudioStream = biome.music if biome != null else null
	if candidate != stream:
		candidate = stream
		candidate_time = 0
	candidate_time += delta
	if candidate_time >= STABLE_SECONDS and target_stream != stream:
		transition(stream, biome.music_title if biome != null else "")

func transition(stream: AudioStream, title: String = "") -> void:
	if target_stream == stream:
		return
	target_stream = stream
	current_title = title
	var selected := -1
	for index in 2:
		if players[index].stream == stream and stream != null:
			selected = index
	if stream != null and selected < 0:
		selected = 0 if gains.x <= gains.y else 1
		players[selected].stop()
		players[selected].stream = stream
		gains[selected] = 0
		players[selected].volume_db = -80
		if DisplayServer.get_name() != "headless":
			players[selected].play()
	start_gains = gains
	target_gains = Vector2.ZERO
	if selected >= 0:
		target_gains[selected] = 1
	fade_time = 0

func _process(delta: float) -> void:
	fade_time = minf(FADE_SECONDS, fade_time + delta)
	var weight := smoothstep(0, 1, fade_time / FADE_SECONDS)
	for index in 2:
		gains[index] = sqrt(lerpf(start_gains[index] * start_gains[index], target_gains[index] * target_gains[index], weight))
		players[index].volume_db = linear_to_db(maxf(0.0001, gains[index])) + MUSIC_GAIN_DB
		if fade_time >= FADE_SECONDS and target_gains[index] == 0:
			players[index].stop()
			players[index].stream = null

func _exit_tree() -> void:
	for player in players:
		player.stop()
