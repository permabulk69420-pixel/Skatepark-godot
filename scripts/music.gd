# The soundtrack: the three tracks in assets/music play one after another, forever.
class_name Music
extends Node

const VOLUME := 0.4   # 0..1, the whole soundtrack
const TRACKS := ["heatwave", "rebellion", "punk-rock"]

var player: AudioStreamPlayer
var track := 0
var streams: Array[AudioStream] = []


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = linear_to_db(VOLUME)
	player.finished.connect(_next)
	add_child(player)
	for track_name in TRACKS:
		var stream := load("res://assets/music/%s.mp3" % track_name) as AudioStream
		if stream != null:
			streams.append(stream)


func start() -> void:
	if streams.is_empty() or player.playing:
		return
	player.stream = streams[track % streams.size()]
	player.play()


func set_volume(v: float) -> void:
	player.volume_db = linear_to_db(v)


func _next() -> void:
	track = (track + 1) % maxi(1, streams.size())
	start()
