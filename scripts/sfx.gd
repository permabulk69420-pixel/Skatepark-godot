# Board sounds. One-shots on the skater's events (pop, landing, rail clank, bail, wall knock, push scuff) and four loops whose
# loudness and pitch follow what the board is doing: rolling (concrete, or ply on wooden ramps and the loop), grinding metal
# (rails, steel coping) and grinding concrete (ledges). The clips were cut from CC0 recordings (see source/sfx in the web repo).
class_name Sfx
extends Node

const VOLUME := 0.85   # 0..1, all the board sounds
const FILES := ["pop", "pop2", "land", "landHard", "landHard2", "railHit", "grindMetal", "grindConcrete", "roll", "rollWood", "bailBody", "bailBoard"]
const ROLL := {"gain": 0.55, "fullSpeed": 8.0, "rateMin": 0.8, "rateMax": 1.35}   # loudest at fullSpeed m/s; pitch rises with speed
const GRIND := {"gain": 0.75, "rateMin": 0.85, "rateMax": 1.25}
const POP := 0.9
const LAND := 0.85   # scaled by how hard the landing was; past 5.5 m/s into the ground it is the heavy clip
const PUSH := 0.22
const WOOD := "Mini|Loop|Wood|Ply|Timber"   # collision meshes whose name matches this are ridden on the wooden roll
const ONE_SHOT_VOICES := 12

class LoopVoice:
	var player: AudioStreamPlayer
	var gain := 0.0       # linear, smoothed towards the target
	var rate := 1.0

var streams := {}
var loops := {}
var voices: Array[AudioStreamPlayer] = []
var scuffs: Array[AudioStreamWAV] = []
var played := {}
var surface_t := 0.0
var wood := false
var wood_re := RegEx.new()
var hit := SkateWorld.Hit.new()
var world: SkateWorld
var rng := RandomNumberGenerator.new()


func _init(p_world: SkateWorld = null) -> void:
	world = p_world


func _ready() -> void:
	rng.randomize()
	wood_re.compile("(?i)" + WOOD)
	for clip in FILES:
		var stream := load("res://assets/sfx/%s.ogg" % clip) as AudioStream
		if stream != null:
			streams[clip] = stream
	for _i in ONE_SHOT_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		voices.append(p)
	for clip in ["roll", "rollWood", "grindMetal", "grindConcrete"]:
		if not streams.has(clip):
			continue
		var stream: AudioStreamOggVorbis = streams[clip]
		stream.loop = true
		var v := LoopVoice.new()
		v.player = AudioStreamPlayer.new()
		v.player.stream = stream
		v.player.volume_db = -80.0
		add_child(v.player)
		# Start each loop at a random point, so two of them never line up the same way twice.
		v.player.play(rng.randf() * stream.get_length())
		loops[clip] = v
	for centre in [700.0, 850.0, 1000.0]:
		scuffs.append(_make_scuff(centre))


# A push: the back foot scuffing the ground, made rather than recorded (a short burst of band-passed noise).
func _make_scuff(centre: float) -> AudioStreamWAV:
	var rate := 44100
	var length := int(rate * 0.16)
	var noise := PackedFloat32Array()
	noise.resize(length)
	for i in length:
		var t := float(i) / length
		noise[i] = (rng.randf() * 2.0 - 1.0) * sin(PI * minf(1.0, t * 4.0)) * pow(1.0 - t, 2.0)
	# band-pass biquad, Q 0.9
	var w0 := TAU * centre / rate
	var alpha := sin(w0) / (2.0 * 0.9)
	var b0 := alpha
	var b2 := -alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w0)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var bytes := PackedByteArray()
	bytes.resize(length * 2)
	for i in length:
		var x := noise[i]
		var y := (b0 * x + b2 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		bytes.encode_s16(i * 2, int(clampf(y * 2.2, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	return wav


# gain 0..1, rate = playback speed (pitch); a little random detune keeps repeats from sounding identical.
func play(clip: String, gain: float = 1.0, rate: float = 1.0) -> void:
	if not streams.has(clip):
		return
	_play_stream(streams[clip], gain, rate)
	played[clip] = played.get(clip, 0) + 1


func _play_stream(stream: AudioStream, gain: float, rate: float) -> void:
	var voice: AudioStreamPlayer = null
	for p in voices:
		if not p.playing:
			voice = p
			break
	if voice == null:
		voice = voices[0]
	voice.stream = stream
	voice.pitch_scale = rate * (0.96 + rng.randf() * 0.08)
	voice.volume_db = linear_to_db(maxf(gain * VOLUME, 1e-4))
	voice.play()


# Skater events (main forwards them).
func event(type: String, data: Dictionary = {}) -> void:
	match type:
		"pop":
			play("pop" if rng.randf() < 0.5 else "pop2", POP * (0.8 + 0.2 * float(data.get("charge", 1.0))))
		"land":
			var impact: float = data.get("impact", 2.0)
			if impact < 0.6:
				return
			var hard := impact > 5.5   # an ollie on the flat lands at about 4 m/s; stairs and big airs come in harder
			var gain := LAND * minf(1.0, 0.3 + impact / 7.0)
			play(("landHard" if rng.randf() < 0.5 else "landHard2") if hard else "land", gain, 1.0 if hard else 1.05)
		"push":
			if not scuffs.is_empty():
				_play_stream(scuffs[rng.randi() % scuffs.size()], PUSH, 1.0)
		"catch":
			play("land", 0.45 if data.get("quality") == "clean" else 0.6, 1.15)   # the board slapping back under your feet
		"grindStart":
			var ledge: bool = data.get("kind") == "ledge"
			play("land" if ledge else "railHit", 0.5 if ledge else 0.7, 1.2 if ledge else 1.0)
		"wall":
			play("landHard2", minf(0.9, 0.2 + float(data.get("impact", 1.0)) * 0.15), 0.9)
		"bail":
			play("bailBody", 0.9)
			play("bailBoard", 0.8)


# Every frame: the loops follow the board.
func update(sim: Skater, dt: float) -> void:
	if loops.is_empty():
		return
	var rolling := absf(sim.roll_speed) if (sim.mode == Skater.Mode.GROUND or sim.mode == Skater.Mode.LOOP) else 0.0
	# What the wheels are on: the loop is ply; otherwise ask the collision under the board now and then.
	surface_t -= dt
	if sim.mode == Skater.Mode.LOOP:
		wood = true
	elif surface_t <= 0.0 and sim.mode == Skater.Mode.GROUND and world != null:
		surface_t = 0.15
		var g := world.ground(sim.pos.x, sim.pos.z, sim.pos.y + 0.3, hit, 1.0)
		wood = g != null and g.collider != null and wood_re.search(String(g.collider.name)) != null
	var level := pow(minf(1.0, rolling / ROLL.fullSpeed), 0.7) * (0.6 if sim.manual != null else 1.0)
	var rate: float = ROLL.rateMin + (ROLL.rateMax - ROLL.rateMin) * minf(1.0, rolling / 12.0)
	_fade("roll", 0.0 if wood else ROLL.gain * level, rate, dt)
	_fade("rollWood", ROLL.gain * 1.1 * level if wood else 0.0, rate, dt)
	var grinding := absf(sim.grind.gs) if (sim.mode == Skater.Mode.GRIND and sim.grind != null) else 0.0
	var metal := sim.grind != null and sim.grind.path.kind != "ledge"
	var glevel: float = GRIND.gain * minf(1.0, 0.45 + grinding / 7.0) if grinding > 0.2 else 0.0
	var grate: float = GRIND.rateMin + (GRIND.rateMax - GRIND.rateMin) * minf(1.0, grinding / 9.0)
	_fade("grindMetal", glevel if metal else 0.0, grate, dt, 0.03)
	_fade("grindConcrete", 0.0 if metal else glevel, grate, dt, 0.03)


# Paused (the menu is up): the loops die away.
func hush(dt: float) -> void:
	for clip in loops:
		_fade(clip, 0.0, loops[clip].rate, dt, 0.03)


# The gain eases towards its target over a time constant (like Web Audio's setTargetAtTime), and so does the pitch.
func _fade(clip: String, target: float, rate: float, dt: float, tc: float = 0.05) -> void:
	if not loops.has(clip):
		return
	var v: LoopVoice = loops[clip]
	v.gain += (target - v.gain) * (1.0 - exp(-dt / tc))
	v.rate += (rate - v.rate) * (1.0 - exp(-dt / 0.08))
	v.player.volume_db = linear_to_db(maxf(v.gain * VOLUME, 1e-4))
	v.player.pitch_scale = v.rate
