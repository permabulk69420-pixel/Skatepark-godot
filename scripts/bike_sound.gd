# The dirt bike's sound. The engine is made as it plays, not a recording: a single cylinder four-stroke fires once every two turns of the
# crank, so each firing is a thump that rings the exhaust (two resonances and a burst of noise), at a rate that follows the revs. Open
# throttle fires hard and bright; shut, at high revs, it fires weakly, misses and now and then pops. Wind rises with speed, and the tyres
# roll on the board's rolling clip, pitched down. A heavy landing or a wall plays the board's heavy landing.
class_name BikeSound
extends Node

const RATE := 22050.0
const BUFFER := 0.12               # seconds of sound kept queued
const VOLUME := 0.6
const EXHAUST := [[80.0, 40.0, 1.0], [170.0, 110.0, 0.45], [480.0, 220.0, 0.22]]   # the exhaust's ringing: [frequency, bandwidth (Hz), loudness]
const NOISE_DECAY := 0.004         # seconds the burst of noise in each firing lasts
const THUMP := 0.035               # how much of the low thump goes through
const DRIVE := 0.09                # into the soft clip: a little grit when it works hard, not a buzz
const ROLL := {"gain": 0.4, "full": 15.0, "rate_min": 0.55, "rate_max": 0.95}

var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var roll: AudioStreamPlayer
var thud: AudioStreamPlayer
var running := false
var rpm := DirtBike.IDLE
var load_ := 0.0
var speed := 0.0
var level := 0.0                   # fades in when the engine starts, out when it stops
var phase := 0.0
var rings: Array = []              # per resonance: [a1, a2, gain, y1, y2]
var noise_env := 0.0
var noise_decay := 0.0
var low := 0.0
var wind := 0.0
var dc_in := 0.0
var dc_out := 0.0
var seed_ := 22222


func _init() -> void:
	for r in EXHAUST:
		var radius := exp(-PI * r[1] / RATE)
		rings.append([2.0 * radius * cos(TAU * r[0] / RATE), -radius * radius, (1.0 - radius) * r[2], 0.0, 0.0])
	noise_decay = exp(-1.0 / (NOISE_DECAY * RATE))


func _ready() -> void:
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = RATE
	stream.buffer_length = BUFFER * 2.0
	player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = linear_to_db(VOLUME)
	add_child(player)
	var rolling := load("res://assets/sfx/roll.ogg") as AudioStreamOggVorbis
	if rolling != null:
		rolling = rolling.duplicate()
		rolling.loop = true
		roll = AudioStreamPlayer.new()
		roll.stream = rolling
		roll.volume_db = -80.0
		add_child(roll)
	thud = AudioStreamPlayer.new()
	thud.stream = load("res://assets/sfx/landHard.ogg")
	add_child(thud)


func start() -> void:
	running = true
	if not player.playing:
		player.play()
		playback = player.get_stream_playback()
	if roll != null and not roll.playing:
		roll.play()


func stop() -> void:
	running = false


# Every frame, from the bike: its revs, the throttle, its speed and whether its tyres are on the ground.
func update(dt: float, bike: DirtBike) -> void:
	if bike != null:
		rpm = bike.rpm
		load_ = bike.throttle
		speed = absf(bike.speed)
	level = move_toward(level, 1.0 if running else 0.0, dt * (4.0 if running else 1.5))
	if roll != null:
		var on := bike != null and not bike.air and running
		var gain := ROLL.gain * clampf(speed / ROLL.full, 0.0, 1.0) * (1.0 if on else 0.0)
		roll.volume_db = linear_to_db(maxf(gain, 1e-4))
		roll.pitch_scale = lerpf(ROLL.rate_min, ROLL.rate_max, clampf(speed / ROLL.full, 0.0, 1.0))
	if playback == null:
		return
	if level <= 0.0 and not running:
		player.stop()
		playback = null
		if roll != null:
			roll.stop()
		return
	_fill()


# A knock (landing hard, hitting a wall): how hard, in m/s.
func knock(impact: float) -> void:
	if impact < 3.0 or thud.stream == null:
		return
	thud.volume_db = linear_to_db(clampf(impact / 10.0, 0.2, 1.0) * 0.9)
	thud.pitch_scale = 0.8
	thud.play()


func _fill() -> void:
	var frames := playback.get_frames_available()
	if frames > 0:
		playback.push_buffer(render(frames))


# The next `frames` samples of the engine (and the wind), as it is now.
func render(frames: int) -> PackedVector2Array:
	var step := rpm / 120.0 / RATE           # firings per sample (once every two turns)
	var hard := 0.3 + 0.7 * load_
	var shut := load_ < 0.08 and rpm > 3800.0
	var wind_gain := clampf(speed / 30.0, 0.0, 1.0)
	wind_gain *= wind_gain * 0.25
	var r0: Array = rings[0]
	var r1: Array = rings[1]
	var r2: Array = rings[2]
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	for i in frames:
		var kick := 0.0
		phase += step
		if phase >= 1.0:
			phase -= 1.0
			if shut and _rand() < 0.22:
				if _rand() < 0.25:
					kick = 1.3                    # a pop on the overrun
					noise_env = 1.0
			else:
				kick = (hard * 0.5 if shut else hard) * (0.85 + 0.3 * _rand())
				noise_env = kick
		noise_env *= noise_decay
		var noise := (_rand() * 2.0 - 1.0)
		var excite := kick + noise * noise_env * 0.6
		var y0: float = r0[0] * r0[3] + r0[1] * r0[4] + excite * r0[2] * 60.0
		r0[4] = r0[3]
		r0[3] = y0
		var y1: float = r1[0] * r1[3] + r1[1] * r1[4] + excite * r1[2] * 60.0
		r1[4] = r1[3]
		r1[3] = y1
		var y2: float = r2[0] * r2[3] + r2[1] * r2[4] + excite * r2[2] * 60.0
		r2[4] = r2[3]
		r2[3] = y2
		low += (kick * 30.0 - low) * THUMP
		wind += (noise - wind) * 0.05
		var y := y0 + y1 + y2 + low * 0.04 + noise * noise_env * 0.08
		y *= DRIVE
		y = y / (1.0 + absf(y))                   # (a soft clip: some grit when it is working hard)
		# take out any steady offset
		dc_out = y - dc_in + 0.995 * dc_out
		dc_in = y
		var out := (dc_out + wind * wind_gain) * level
		buffer[i] = Vector2(out, out)
	return buffer


# A cheap random number in 0..1 (one per sample is plenty for noise).
func _rand() -> float:
	seed_ ^= (seed_ << 13) & 0xFFFFFFFF
	seed_ ^= seed_ >> 17
	seed_ ^= (seed_ << 5) & 0xFFFFFFFF
	return float(seed_ & 0xFFFFFF) / 16777216.0
