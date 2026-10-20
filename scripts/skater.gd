# The skater is the board: position is where the wheels meet the ground, heading is which way the nose points.
# The rider is placed over it by the view layer. Everything runs in fixed-ish substeps so frame rate does not change the feel.
#
# This is a line-for-line port of the web build's sim.js (names turned into snake_case; the tuning keys in config.gd keep theirs).
# Board heading h points the nose along (-sin h, 0, -cos h): h = 0 is -Z, the way the park entrance faces.
class_name Skater
extends RefCounted

const T = Config.Tuning
const BOARD = Config.Board
const RIDER = Config.Rider

enum Mode { GROUND, AIR, GRIND, BAIL, LOOP }

const WHEEL_LIFT := 0.3
const UP := Vector3.UP

signal event(type: String, data: Dictionary)


# What the player asks for, once per frame (skate_input.gd fills one in; tests build their own).
class Command:
	var steer := 0.0
	var drive := 0.0
	var lean := 0.0               # the hands (VR) or A/D (flat screen): what balances grinds and manuals
	var jump := false
	var grind := false
	var flip := false
	var detach := false
	var grabbing := false         # holding the board in a grab: what lets the stick flip you over
	var trick_stick := Vector2.ZERO
	var body_y := NAN             # head height (VR only)
	var recenter := false
	var toggle_stance := false


class SpawnPoint:
	var pos := Vector3.ZERO
	var heading := 0.0


class Wheels:
	var pts: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var nrm: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	var h: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var ok: Array[bool] = [false, false, false, false]
	var count := 0
	var max_y := 0.0
	var centre := Vector3.ZERO
	var normal := Vector3.UP
	var has_normal := false


class Manual:
	var kind := 1
	var pitch_sign := 1
	var bal := 0.0
	var bal_vel := 0.0
	var time := 0.0
	var p1 := 0.0
	var p2 := 0.0
	var name := ""


class Flip:
	var spin_sign := 1.0
	var angle := 0.0
	var progress := 0.0
	var kick := true
	var turns := 1             # how many full turns this flip is going for (a double or triple flip has more)
	var prefix := ""           # "Fakie " or ""
	var name := ""
	var varial := ""


class Shuv:
	var spin_sign := 1.0
	var angle := 0.0
	var progress := 0.0
	var bs := true
	var done := false
	var name := ""


class Grind:
	var path: GrindPath
	var mode := "truck"          # "truck" (50-50) or "slide" (boardslide)
	var s := 0.0
	var gs := 0.0
	var time := 0.0
	var yaw_offset := 0.0
	var stall := false
	var back := Vector3.ZERO
	var bal := 0.0
	var bal_vel := 0.0
	var p1 := 0.0
	var p2 := 0.0
	var variant := 0
	var vb := 0.0
	var v_nose := 0.0
	var v_tail := 0.0
	var snap := Vector3.ZERO
	var name := ""
	var tilt := Vector3.ZERO
	var u := Vector3.UP


class LoopState:
	var path: LoopPath
	var s := 0.0
	var gs := 0.0
	var l := 0.0
	var nose := 1
	var time := 0.0
	var min_ny := 1.0
	var entry := "start"


class BailBoard:
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var quat := Quaternion.IDENTITY


var world: SkateWorld
var rng := RandomNumberGenerator.new()
var random_fn := Callable()       # returns a float in [0, 1); tests set this to replay a recorded run, otherwise rng is used
var require_grind := false        # true in the game: rails and copings are only caught after a press of the grind button
var grind_held := false
var grind_was := false
var grind_arm := 0.0
var bounds: Dictionary            # the level's play area: half-extents x/z around an optional centre cx/cz
var paths: Array[GrindPath] = []
var loops: Array[LoopPath] = []   # loop-the-loops (loop_path.gd): ridden as a position along the track, like a grind
var loop: LoopState = null
var frame_right = null            # while on a loop, the board's right side (heading + up cannot describe upside down); Vector3 or null

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var heading := 0.0
var mode := Mode.AIR
var ground_normal := Vector3.UP
var up := Vector3.UP              # smoothed board up, for display
var face_offset := -PI / 2.0      # rider's facing relative to the nose (regular stance faces the board's right)

var steer := 0.0
var drive := 0.0
var lean := 0.0
var manual: Manual = null
var manual_queue = null           # { kind, t } or null
var manual_lift := 0.0
var clock := 0.0
var stick_extreme := 0
var stick_extreme_t := -9.0
var stick_extreme_speed := 0.0
var jump_was := false
var jump_held := false
var crouch_time := 0.0
var pop_request := -1.0           # a charge 0..1, or -1 for none
var pop_buffer := 0.0
var push_cool := 0.0
var push_pending := 0.0
var braking := false
var edge_grace := 0.0
var rolled_off := false
var launch_e := 0.0
var hold_fwd := 0.0
var pass_intent := false
var lip_exit := false
var air_floor_y := 0.0
var air_floor_normal := Vector3.UP
var air_floor_found := false
var spin_vel := 0.0
var exit_align := 0.0
var trick_controls := TrickControls.new()
var completed_tricks: Array[String] = []   # board tricks completed in this air, credited only on a landing or rail catch
var flip: Flip = null
var flip_roll := 0.0
var multi_out := false             # the stick is still pushed out from the flick that started (or lengthened) the current flip
var multi_t := 0.0                 # when that was
var spin_lock := false
var shuv: Shuv = null
var shuv_yaw := 0.0
var raw_steer := 0.0
var raw_drive := 0.0
var trick_prefix := ""
var switched := false
var freeze_t := 0.0
var freeze_pos := Vector3.ZERO
var pop_timer := 99.0
var vis_pitch := 0.0
var vis_roll := 0.0
var carve := 0.0
var crouch := 0.0
var roll_speed := 0.0
var body_ref := NAN
var body_y := NAN
var extend := 0.0
var pump_acc := 0.0
var grounded_time := 0.0
var air_time := 0.0
var grind: Grind = null
var last_grind_path: GrindPath = null
var grind_cooldown := 0.0
# The board taken off the feet in the air (board-off): board_off while it is in your hand; off_trick for this air once you have
# taken it off ({ name, far }); a sketchy catch makes a sketchy landing. board_off_pose: where the hand has it (for a bail).
var board_off := false
var off_trick = null
var catch_sketchy := false
var board_off_pose = null         # { pos, quat } or null
var grabbing := false
var body_roll := 0.0
var body_roll_vel := 0.0
var body_flip_hold := 0.0
var body_flipping := false        # backflips / frontflips (body_flip_step)
var bail_time := 0.0
var bail_board: BailBoard = null
var safe := SpawnPoint.new()
var spawn := SpawnPoint.new()
var bail_to_spawn := false        # a bail puts you back at the start rather than where you were (a timed run)
var bail_ground := PackedStringArray()   # parts of the level (by collision name) that bail you the moment you ride on them (Spillway's floor below the course)
var wheels := Wheels.new()

var _hit := SkateWorld.Hit.new()
var _cast := SkateWorld.Hit.new()


# The heading laid onto a surface with normal n: turned with the surface (by the rotation that takes straight up to n), not flattened
# onto it. On flat ground and gentle slopes the two agree; on a steep wall they do not: flattening a heading that points nearly into
# the wall leaves only its sideways part, so a few degrees of skew made "forward" point along the wall near the top of a ramp (pumping
# pushed you sideways, your real up-and-down motion was treated as sideways slip and gripped away, and fast airs ended in a crooked
# landing and a bail). Turned with the surface, "into the wall" is "up the face" and the skew stays a few degrees.
static func on_surface(h: Vector3, n: Vector3) -> Vector3:
	var q: Quaternion
	if n.y > -0.9999:
		q = Quaternion(UP, n)
	else:
		q = Quaternion(1.0, 0.0, 0.0, 0.0)
	var out := q * h
	out += n * (-out.dot(n))
	return out.normalized()


static func heading_vec(h: float) -> Vector3:
	return Vector3(-sin(h), 0.0, -cos(h))


static func yaw_of(x: float, z: float) -> float:
	return atan2(-x, -z)


static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return target + (current - target) * exp(-rate * dt)


# JS Math.round rounds halves up; GDScript's round() rounds them away from zero.
static func js_round(x: float) -> float:
	return floorf(x + 0.5)


static func wrap_angle(a: float) -> float:
	return a - TAU * js_round(a / TAU)


static func hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


# JS `Math.sign(x) || 1`
static func sign_or_one(x: float) -> float:
	var s := signf(x)
	return s if s != 0.0 else 1.0


# A short acceleration/deceleration at either end of a trick, with constant angular speed in the middle.
# A full turn still takes flipTime; a half turn still takes shuvTime. The physical angle and displayed angle agree.
static func trick_rotation_ease(progress: float) -> float:
	var p := clampf(progress, 0.0, 1.0)
	var ramp := 0.18
	if p < ramp:
		return p * p / (2.0 * ramp * (1.0 - ramp))
	if p > 1.0 - ramp:
		return 1.0 - (1.0 - p) * (1.0 - p) / (2.0 * ramp * (1.0 - ramp))
	return (p - ramp / 2.0) / (1.0 - ramp)


func _init(p_world: SkateWorld, p_paths: Array[GrindPath] = [], p_loops: Array[LoopPath] = [], p_bounds: Dictionary = {}, p_require_grind: bool = false) -> void:
	world = p_world
	require_grind = p_require_grind
	bounds = p_bounds if not p_bounds.is_empty() else T.bounds
	paths = p_paths
	loops = p_loops
	for l in loops:
		var w := l.window(T.loopEnterNy)
		l.s_in = w.x
		l.s_out = w.y
	rng.randomize()


func _rand() -> float:
	if random_fn.is_valid():
		return random_fn.call()
	return rng.randf()


func set_spawn(p_pos: Vector3, p_heading: float = 0.0) -> void:
	spawn.pos = p_pos
	spawn.heading = p_heading
	respawn(spawn)


func respawn(where: SpawnPoint = null) -> void:
	if where == null:
		where = safe
	pos = where.pos
	pos.y += 0.04
	heading = where.heading
	vel = Vector3.ZERO
	mode = Mode.AIR
	grind = null
	bail_board = null
	loop = null
	frame_right = null
	up = UP
	ground_normal = UP
	spin_vel = 0.0
	exit_align = 0.0
	vis_pitch = 0.0
	vis_roll = 0.0
	push_cool = 0.0
	push_pending = 0.0
	crouch = 0.0
	pop_request = -1.0
	hold_fwd = 0.0
	pass_intent = false
	lip_exit = false
	manual = null
	manual_queue = null
	manual_lift = 0.0
	stick_extreme = 0
	stick_extreme_t = clock
	stick_extreme_speed = 0.0
	end_flip()
	board_off = false
	off_trick = null
	catch_sketchy = false
	board_off_pose = null
	grabbing = false
	body_roll = 0.0
	body_roll_vel = 0.0
	body_flip_hold = 0.0
	body_flipping = false
	if switched:
		face_offset = -face_offset   # the spawn heading is the board's nose again
		switched = false
	safe.pos = where.pos
	safe.heading = where.heading
	event.emit("respawn", {})


var speed: float:
	get:
		return hypot(vel.x, vel.z)

# Whatever balance meter is running (a grind or a manual), for the HUD and haptics. Null when there is none.
var balance:
	get:
		if mode == Mode.GRIND:
			return grind
		return manual if mode == Mode.GROUND else null

var facing_yaw: float:
	get:
		return heading + face_offset

# Goofy or regular as the rider stands, whatever a shove-it has done to the board's heading since.
var goofy: bool:
	get:
		return (face_offset > 0.0) != switched


# ----- per-frame entry point -------------------------------------------------------------------------------
func update(input: Command, dt: float) -> void:
	if not (dt > 0.0):
		return
	steer = damp(steer, clampf(input.steer, -1.0, 1.0), 20.0, dt)
	lean = clampf(input.lean, -1.0, 1.0)
	grabbing = input.grabbing
	drive = clampf(input.drive, -1.0, 1.0)
	raw_steer = clampf(input.trick_stick.x, -1.0, 1.0)
	raw_drive = clampf(-input.trick_stick.y, -1.0, 1.0)
	# How long forward has been held; a tap does not build it and letting go drains it quickly.
	hold_fwd = clampf(hold_fwd + (dt if drive > T.driveThreshold else -dt * T.passHoldDrain), 0.0, T.passHoldMax)
	clock += dt
	var trick = trick_controls.sample(
		input.flip, raw_steer, -raw_drive, dt,
		(mode == Mode.GROUND or mode == Mode.AIR) and not board_off,
		mode == Mode.AIR and air_time >= T.flipMinAir and flip == null and shuv == null)
	if trick != null:
		start_trick(trick.flip, trick.shuv, int(trick.get("turns", 1)))
	multi_flip_step(input.trick_stick)
	detect_flick()

	var jump := input.jump
	if jump and not jump_was:
		crouch_time = 0.0
		crouch = maxf(crouch, RIDER.crouchPress)
		event.emit("crouch", {})
	if jump:
		crouch_time = minf(crouch_time + dt, 1.0)
	if not jump and jump_was:
		pop_request = clampf(crouch_time / T.popChargeTime, 0.0, 1.0)
		pop_buffer = 0.08
	jump_was = jump
	jump_held = jump
	# The grind button (right trigger): press it once and for the next moment a rail or coping that the board touches is caught.
	# It is the press that counts, not holding it, and a catch uses the press up.
	grind_held = input.grind
	if grind_held and not grind_was:
		grind_arm = T.grindArmWindow
	grind_was = grind_held
	grind_arm = maxf(0.0, grind_arm - dt)
	track_body(input.body_y, dt)
	pop_buffer -= dt
	if pop_buffer <= 0.0:
		pop_request = -1.0
	grind_cooldown = maxf(0.0, grind_cooldown - dt)

	if mode == Mode.BAIL:
		bail_step(dt)
	else:
		var n := maxi(1, ceili(dt / T.maxSubstep))
		var h := dt / n
		var i := 0
		while i < n and mode != Mode.BAIL:
			if mode == Mode.GROUND:
				ground_step(h)
			elif mode == Mode.AIR:
				air_step(h)
			elif mode == Mode.LOOP:
				loop_step(h)
			else:
				grind_step(h)
			i += 1
		if pos.y < T.killY:
			respawn(spawn)
		if mode == Mode.GROUND and bail_ground.size() > 0 and on_bail_ground():
			bail("ground")
		# Safety net: airborne with a real velocity but not moving at all means the board is wedged in the level geometry. Bail out of it
		# rather than hang there (and fall through it, in the end).
		if mode == Mode.AIR and pos.distance_squared_to(freeze_pos) < 1e-6 and vel.length_squared() > 0.25:
			freeze_t += dt
		else:
			freeze_t = 0.0
		freeze_pos = pos
		if freeze_t > T.freezeBail:
			freeze_t = 0.0
			bail("stuck")
	update_visuals(dt)


# Is the surface under the board one of the level's bail grounds?
func on_bail_ground() -> bool:
	var g := world.ground(pos.x, pos.z, pos.y + 0.3, _hit, 0.8)
	if g == null or g.collider == null:
		return false
	var name := String(g.collider.name)
	for part in bail_ground:
		if name.contains(part):
			return true
	return false


# Forward then back (or back then forward) on the stick, quickly, starts a manual.
func detect_flick() -> void:
	# Trick selection, grind variants and grabbed body flips own the stick. Neither half of those inputs is a manual gesture.
	var blocked := (mode != Mode.GROUND and mode != Mode.AIR) or trick_controls.held or trick_controls.pending \
		or (mode == Mode.AIR and (grabbing or body_flipping))
	if blocked:
		stick_extreme = 0
		stick_extreme_t = clock
		stick_extreme_speed = 0.0
		return
	var d := drive
	var sgn := 1 if d > T.flickThreshold else (-1 if d < -T.flickThreshold else 0)
	if sgn != 0 and sgn != stick_extreme:
		# Judge speed when the flick began: the forward half is itself a kick and must not lift a stand-still over the bar.
		if stick_extreme != 0 and clock - stick_extreme_t <= T.flickWindow and stick_extreme_speed >= T.manualMinSpeed:
			request_manual(stick_extreme)
		stick_extreme = sgn
		stick_extreme_t = clock
		stick_extreme_speed = speed
	elif sgn == 0 and clock - stick_extreme_t > T.flickWindow:
		stick_extreme = 0


# Ask for a manual (a flick of the stick). On the ground it starts now; in the air it is remembered and starts when you land:
# ollie, flick, land in it.
func request_manual(kind: int) -> void:
	if manual != null:
		return
	# A board-trick attempt owns the stick until it is consumed or expires.
	if mode == Mode.AIR and (trick_controls.held or trick_controls.pending):
		return
	# …and while grabbing, back or forward on the stick is a backflip or frontflip.
	if mode == Mode.AIR and (grabbing or body_flipping):
		return
	if mode == Mode.GROUND:
		try_manual(kind)
	elif mode == Mode.AIR:
		manual_queue = {"kind": kind, "t": clock}


# kind +1: tail manual (nose up), −1: nose manual (tail up).
func try_manual(kind: int, queued: bool = false, entry_trick: String = "") -> void:
	if mode != Mode.GROUND or manual != null or (jump_held and not queued):
		return
	if ground_normal.y < 0.97 or speed < T.manualMinSpeed:
		return
	# A manual lifts the end that leads: the nose going forward, the tail rolling fakie (and the nose manual the other way).
	var hv := heading_vec(heading)
	var fakie := vel.x * hv.x + vel.z * hv.z < -0.3
	var nm := ("Fakie " if fakie else "") + ("Manual" if kind > 0 else "Nose Manual")
	manual = Manual.new()
	manual.kind = kind
	manual.pitch_sign = -kind if fakie else kind
	manual.bal = 0.0
	manual.bal_vel = 0.0
	manual.time = 0.0
	manual.p1 = _rand() * TAU
	manual.p2 = _rand() * TAU
	manual.name = ("%s + %s" % [entry_trick, nm]) if entry_trick != "" else nm
	push_pending = 0.0
	stick_extreme = 0
	event.emit("manualStart", {"name": manual.name})


func end_manual(reason: String) -> void:
	var m := manual
	if m == null:
		return
	manual = null
	event.emit("manualEnd", {"reason": reason, "name": m.name, "time": m.time})


func manual_step(h: float, sp: float) -> void:
	var m := manual
	m.time += h
	var instab := minf(T.manualInstab0 + T.manualInstabGrow * m.time, T.manualInstabMax)
	var wobble := T.manualWobble * (0.6 * sin(2.1 * m.time + m.p1) + 0.4 * sin(4.9 * m.time + m.p2))
	# The meter is the interface: a push to the right moves the marker right, whichever way the board is leaning.
	# The first moments of a manual the pull towards falling is weaker, as on a grind, so there is time to get the hands up.
	var grace := lerpf(T.balGraceStart, 1.0, clampf(m.time / T.balGrace, 0.0, 1.0))
	var acc := (instab * m.bal + wobble) * grace + T.manualControl * lean - T.manualDamp * m.bal_vel
	m.bal_vel += acc * h
	m.bal += m.bal_vel * h
	if absf(m.bal) >= 1.0:
		m.bal = signf(m.bal)
		end_manual("bail")
		bail("manual")
		return
	if sp < T.manualEndSpeed:
		end_manual("stall")
	elif ground_normal.y < 0.93:
		end_manual("slope")


# Head height (VR only) → how fast the rider is standing up or squatting, relative to their own standing height.
func track_body(y: float, dt: float) -> void:
	if is_nan(y) or is_inf(y) or y < 0.2:
		extend = damp(extend, 0.0, 10.0, dt)
		return
	if is_nan(body_y):
		body_y = y
		body_ref = y
		return
	var rate := (y - body_y) / dt
	body_y = y
	body_ref += (y - body_ref) * (1.0 - exp(-dt / T.pumpRefTime))
	extend = damp(extend, clampf(rate, -3.0, 3.0), T.pumpResponse, dt)


# ----- ground ----------------------------------------------------------------------------------------------
func ground_step(h: float) -> void:
	grounded_time += h
	var m := manual
	var u := ground_normal
	var hv := heading_vec(heading)
	var f := on_surface(hv, u)
	var s := vel.dot(f)

	if pop_request >= 0.0:
		pop(pop_request)
		return
	if try_coping_magnet(pos, true):
		return

	var lat := vel + f * (-s)
	lat += u * (-lat.dot(u))

	# Gravity along the surface: this is all a bowl needs to work.
	var gt := Vector3(0.0, -T.gravity, 0.0)
	gt += u * (-gt.dot(u))
	var along := gt.dot(f)
	s += along * h
	lat += gt * h
	lat += f * (-along * h)

	# Pushing and braking
	push_cool -= h
	braking = false
	# Kicks go the way you are already rolling (rolling fakie, forward on the stick keeps you going, it does not brake you).
	var rolling := -1.0 if s < -0.3 else 1.0
	if m == null and drive > T.driveThreshold and push_cool <= 0.0 and absf(s) < T.pushMaxSpeed and u.y > 0.97:
		push_pending += T.pushImpulse * clampf(1.0 - absf(s) / T.pushMaxSpeed, 0.12, 1.0)
		push_cool = T.pushInterval
		event.emit("push", {"speed": s})
	if push_pending > 0.0:
		var give := minf(push_pending, T.pushDrain * h)
		s += give * rolling
		push_pending -= give
	if m == null and drive < -T.driveThreshold and absf(s) > 0.05:
		braking = true
		s -= signf(s) * minf(absf(s), T.brakeDecel * h)
	var sp := absf(s)
	if sp > 0.0:
		s -= signf(s) * minf(sp, (T.rollFriction + T.airDrag * sp * sp) * h)

	# Forward on the stick pumps a curved surface (the same input that pushes on the flat).
	var bend := clampf((1.0 - u.y) / T.pumpCurve, 0.0, 1.0)
	if m == null and drive > T.driveThreshold and bend > 0.0 and sp > 1.2 and sp < T.autoPumpMaxSpeed:
		var before := s
		s += signf(s) * T.autoPump * bend * h
		pump_acc += absf(s) - absf(before)

	# Pumping a transition: standing up out of a squat while on a curved surface adds speed along the way you are rolling.
	var curve := clampf((1.0 - u.y) / T.pumpCurve, 0.0, 1.0)
	if curve > 0.0 and sp > 1.0:
		var before2 := s
		if extend > 0.0:
			s += signf(s) * minf(T.pumpMaxAccel, T.pumpGain * extend * curve) * h
		else:
			s += signf(s) * T.pumpGain * 0.35 * extend * curve * h   # squatting costs a little, so mashing is not free
		pump_acc += absf(s) - absf(before2)
	if pump_acc > T.pumpEventSpeed and extend < 0.2:
		event.emit("pump", {"gain": pump_acc})
		pump_acc = 0.0
	elif extend < 0.0:
		pump_acc = 0.0

	if m != null:
		s -= signf(s) * minf(absf(s), T.manualDrag * h)
		manual_step(h, absf(s))
		if mode != Mode.GROUND:
			return

	# Steering: trucks need roll speed to bite, so almost-stopped turning is a slow tail pivot.
	var bite := clampf(sp / T.steerSpeedRef, 0.0, 1.0)
	var max_rate := minf(T.maxYawRate, T.maxLateralAccel / maxf(sp, 1.6))
	# Left and right mean left and right of where you are going, forward or fakie (a real board's trucks would turn the other
	# way rolling backwards, which is just confusing).
	heading = wrap_angle(heading - steer * (max_rate * (T.manualSteer if manual != null else 1.0) * bite + T.pivotRate * (1.0 - bite)) * h)
	carve = damp(carve, steer * clampf(sp / 6.0, 0.0, 1.0) * (-1.0 if s < 0.0 else 1.0), 10.0, h)

	hv = heading_vec(heading)
	f = on_surface(hv, u)
	lat *= exp(-T.lateralGrip * h)
	vel = f * s + lat
	roll_speed = s

	var np := pos + vel * h
	move_on_ground(np, h)
	if mode == Mode.GROUND and loops.size() > 0 and try_enter_loop():
		return
	if mode == Mode.GROUND and ground_normal.y > 0.92 and grounded_time > 0.5 and speed < 9.0:
		safe.pos = pos
		safe.heading = heading


func move_on_ground(np_in: Vector3, h: float) -> void:
	var np := np_in
	var old_y := pos.y
	var n := ground_normal
	var total_speed := vel.length()

	# Look ahead along the motion: a surface much steeper than the one we are on is a wall, not a ramp.
	if total_speed > 0.4:
		var sd := vel / total_speed
		var a := pos + n * 0.1
		var far := T.wallProbe + total_speed * h
		var c := world.cast(a, sd, far, _cast)
		if c != null and c.normal.dot(n) < T.wallCos:
			hit_wall(c)
			return

	np = clamp_bounds(np)
	var steep := n.y < T.steepNormalY
	var w := sample_wheels(np, heading, maxf(old_y, np.y) + 0.5, steep)
	if w.count == 0:
		if inside_solid(np):
			hit_wall(null)
			return
		pos = np
		leave_ground()
		return
	if steep:
		# Rays along the normal only report wheels that are actually near the surface; how high they hover says whether we left it.
		var hover := 0.0
		for k in 4:
			if w.ok[k]:
				hover += w.h[k]
		hover /= w.count
		if hover > T.steepLeave:
			pos = np
			leave_ground()
			return
		if w.count >= 3:
			pos = w.centre
			if w.has_normal:
				ground_normal = w.normal
		else:
			# Fewer than three wheels agree: at a crest the front wheels are over a flat deck and the rear ones still on the slope.
			# Sliding the board "down onto the surface" along the slope normal can drive it into the deck, so check the candidate
			# against the ground that is really under it. If that is a flat deck the board is over the lip and flies off with the
			# speed it has; otherwise it is lifted onto the real surface.
			var cand := np + n * (-hover)
			var mid := world.ground(cand.x, cand.z, cand.y + 0.6, _hit)
			if mid != null:
				if mid.normal.y > T.crestDeckNormalY and mid.y >= cand.y - T.crestLeave:
					pos = Vector3(cand.x, maxf(cand.y, mid.y), cand.z)
					leave_ground()
					return
				if cand.y < mid.y - 0.02:
					cand.y = mid.y
			pos = cand
		project_velocity(ground_normal)
		return
	var h_step := hypot(vel.x, vel.z) * h
	var expected := old_y + maxf(vel.y, 0.0) * h
	var allowed := T.maxStep + h_step * T.maxSlopeTan
	if w.centre.y - expected > allowed:
		# At the crest of a steep ramp the front wheels reach a flat deck while the rear ones are still on the slope; the wheel
		# fit then jumps well above the board, which looks like a wall. A surface that is continuous under the middle of the
		# board is a ramp, however steep its last few centimetres: judge by that, so a bank ending in a deck can be ridden over.
		var mid2 := world.ground(np.x, np.z, maxf(old_y, np.y) + 0.5, _hit)
		if mid2 != null and mid2.y - expected <= allowed and mid2.normal.y > T.crestMinNormalY:
			w.centre = Vector3(np.x, mid2.y, np.z)
			w.normal = mid2.normal
			w.has_normal = true
		else:
			# Higher ground behind us means we have rolled off an edge (tail still on the deck), not into a wall.
			var hv := hypot(vel.x, vel.z)
			var ahead := ((w.centre.x - np.x) * vel.x + (w.centre.z - np.z) * vel.z) / hv if hv > 1e-4 else 0.0
			if ahead < -0.05:
				pos = np
				leave_ground()
				return
			hit_wall(null)
			return
	if np.y - w.centre.y <= T.snapDistance:
		pos = Vector3(np.x, w.centre.y, np.z)
		if w.has_normal:
			ground_normal = w.normal
		project_velocity(ground_normal)
	else:
		pos = np
		leave_ground()


func project_velocity(n: Vector3) -> void:
	var total := vel.length()
	vel += n * (-vel.dot(n))
	var flat := vel.length()
	if flat > 1e-6 and total > flat:
		vel *= (flat + (total - flat) * T.transitionKeep) / flat


func leave_ground() -> void:
	mode = Mode.AIR
	air_time = 0.0
	completed_tricks.clear()
	edge_grace = T.edgeGrace
	rolled_off = true
	end_manual("air")
	launch_e = 0.5 * vel.length_squared() + T.gravity * pos.y
	pass_intent = pop_timer < T.passPopWindow   # an ollie arms a possible exit; forward input at the lip commits it
	lip_exit = false
	grounded_time = 0.0
	braking = false
	off_trick = null
	catch_sketchy = false
	body_roll = 0.0
	body_roll_vel = 0.0
	body_flip_hold = 0.0
	body_flipping = false


# ----- backflips and frontflips (while grabbing) -------------------------------------------------------------------------------
# In the air, while holding a grab, the stick held back flips you over backwards and held forward flips you forwards, for as long
# as you hold it. It has to be meant: the stick must be pushed most of the way (bodyFlipStick), close to straight back or forward
# (within bodyFlipCone), and held there for bodyFlipDelay before anything turns, so a spin or a brush of the stick never starts one.
# Once it has started you can push the stick diagonally to spin as well. You turn nose over tail, about the axis across the board:
# a backflip lifts the nose and goes over backwards, a frontflip dips it and goes over forwards.
func body_flip_step(h: float) -> void:
	var x := raw_steer
	var y := raw_drive
	var mag := hypot(x, y)
	var from_axis := atan2(absf(x), absf(y))   # 0 = straight back or forward
	if not body_flipping:
		var in_zone := grabbing and flip == null and shuv == null and not trick_controls.pending and mag >= T.bodyFlipStick and from_axis <= T.bodyFlipCone
		body_flip_hold = body_flip_hold + h if in_zone else 0.0
		if body_flip_hold >= T.bodyFlipDelay:
			body_flipping = true
	var target := 0.0
	if body_flipping and absf(y) > T.bodyFlipKeep:
		# backflip (stick back): the nose comes up and over
		target = (1.0 if y < 0.0 else -1.0) * T.bodyFlipRate
	body_roll_vel = damp(body_roll_vel, target, T.bodyFlipResponse, h)
	body_roll += body_roll_vel * h


# How far you are from upright after a flip, in radians.
func body_roll_residual() -> float:
	return absf(wrap_angle(body_roll))


# ----- the board off your feet (board-grab calls these) ------------------------------------------------------
# Take it off: only in the air, and not in the middle of a flip or shove-it (the board is busy).
func detach_board() -> bool:
	if mode != Mode.AIR or board_off or flip != null or shuv != null:
		return false
	board_off = true
	off_trick = {"name": "Board Off", "far": 0.0, "tpose": 0.0}
	trick_controls.reset()
	event.emit("detach", {})
	return true


# Back under your feet. quality 'clean' or 'sketchy'; reversed: caught nose-for-tail, so it is ridden the other way round from now.
func catch_board(quality: String, reversed: bool = false) -> void:
	if not board_off:
		return
	board_off = false
	board_off_pose = null
	if quality == "sketchy":
		catch_sketchy = true
	if reversed:
		heading = wrap_angle(heading + PI)
		face_offset = -face_offset
		switched = not switched
	event.emit("catch", {"quality": quality, "reversed": reversed, "name": off_trick.name if off_trick != null else ""})


func pop(charge: float) -> void:
	end_manual("pop")
	var pop_speed := T.popMin + (T.popMax - T.popMin) * clampf(charge, 0.0, 1.0)
	# Straight off the surface on flat ground, but leaning towards straight up as it steepens: popping off a wall along
	# its normal would throw you backwards into the pit.
	var n := ground_normal
	var energy_before_pop := 0.5 * vel.length_squared() + T.gravity * pos.y
	var lean_up := pow(clampf(n.y, 0.0, 1.0), T.popUpBias)
	var dir := (UP * (1.0 - lean_up) + n * lean_up).normalized()
	vel += dir * pop_speed
	pop_request = -1.0
	pop_timer = 0.0
	crouch = -RIDER.popRebound
	pos += ground_normal * 0.012   # lift off so the ground check does not re-catch us
	leave_ground()
	rolled_off = false
	launch_e = energy_before_pop   # speed carried to a lip is what counts, not the pop
	event.emit("pop", {"charge": charge, "speed": pop_speed})


# ----- air -------------------------------------------------------------------------------------------------
func air_step(h: float) -> void:
	air_time += h
	pop_timer += h
	vel.y -= T.gravity * h
	var sp := vel.length()
	vel *= maxf(0.0, 1.0 - T.airDrag * sp * h)

	# A little stick drift while carving into a jump must not spin you; spin only starts past the dead zone.
	var spin_input := signf(steer) * maxf(0.0, absf(steer) - T.airSpinDeadzone) / (1.0 - T.airSpinDeadzone)
	# Trick selection is already complete for this input frame; physics only animates it.
	if flip != null:
		var f := flip
		f.progress = clampf(f.progress + h / (T.flipTime * f.turns), 0.0, 1.0)
		f.angle = f.spin_sign * TAU * f.turns * trick_rotation_ease(f.progress)
		flip_roll = f.angle
	if shuv != null and not shuv.done:
		var s := shuv
		s.progress = clampf(s.progress + h / T.shuvTime, 0.0, 1.0)
		s.angle = s.spin_sign * PI * trick_rotation_ease(s.progress)
		shuv_yaw = s.angle
		if s.progress >= 1.0:
			commit_shuv()
	finish_air_trick()
	if spin_lock and (flip == null or flip.progress >= 1.0) and (shuv == null or shuv.done) and absf(steer) < T.airSpinDeadzone:
		spin_lock = false
	var spin_target := 0.0 if (spin_lock or trick_controls.pending or trick_controls.chain_live) else -spin_input * T.airSpinRate
	spin_vel = damp(spin_vel, spin_target, T.airSpinResponse, h)
	body_flip_step(h)
	heading = wrap_angle(heading + spin_vel * h)
	if exit_align > 0.0:
		exit_align -= h
		if absf(steer) < 0.35 and speed > 0.5:
			var travel := yaw_of(vel.x, vel.z)
			var diff := wrap_angle(travel - heading)
			if absf(diff) > PI / 2.0:
				diff = wrap_angle(diff - signf(diff) * PI)
			heading = wrap_angle(heading + clampf(diff, -T.exitAlignRate * h, T.exitAlignRate * h))

	if pop_timer < T.passPopWindow:
		pass_intent = true
	hug_wall(h)
	lip_air(h)
	sample_air_floor()

	var np := pos + vel * h
	np = clamp_bounds(np)

	# A board that is mid-flip cannot catch a rail; one that has come round (or is nearly there) can.
	# (and one that is in your hand, not under your feet, catches nothing)
	var flip_ready := flip == null or (absf(flip.angle) > PI and flip_residual() <= T.flipCleanRoll)
	var shuv_ready := shuv == null or shuv.done or (absf(shuv.angle) > PI / 2.0 and shuv_residual() <= T.shuvClean)
	if not board_off and flip_ready and shuv_ready and (try_grind(np, h) or try_coping_magnet(np)):
		return

	if sweep_board(np, h):
		return
	pos = np


# ----- flips and shove-its ---------------------------------------------------------------------------------
func make_flip(kick: bool) -> Flip:
	# Which way the board rolls for each flip; goofy is the mirror image. This is the one place to change if it looks backwards
	# (the first version was backwards: stick left looked like a heelflip in the headset).
	var f := Flip.new()
	f.spin_sign = (1.0 if kick else -1.0) * (1.0 if face_offset < 0.0 else -1.0)
	f.angle = 0.0
	f.progress = 0.0
	f.kick = kick
	f.prefix = trick_prefix
	f.name = flip_label(f, 1)
	return f


# "Kickflip", "Double Kickflip", "Triple Kickflip" (and the heelflips), with "Fakie " in front if it was one.
static func flip_label(f: Flip, turns: int) -> String:
	return f.prefix + ["", "", "Double ", "Triple "][clampi(turns, 1, 3)] + ("Kickflip" if f.kick else "Heelflip")


# What a flip that lands now is worth a name for: the turns it has really done, not the ones it was going for.
func flip_credit_name(f: Flip) -> String:
	return flip_label(f, maxi(1, int(js_round(absf(f.angle) / TAU))))


# The progress at which a flip with `turns` turns has done `done` turns' worth (the inverse of the rotation ease).
static func flip_progress_for(done_fraction: float) -> float:
	var lo := 0.0
	var hi := 1.0
	for i in 24:
		var mid := (lo + hi) / 2.0
		if trick_rotation_ease(mid) < done_fraction:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


# Flicking the stick the same way again, soon after the last flick, gives a started kickflip or heelflip another turn (double, triple).
# The flip carries on from exactly where it is, so nothing jumps: it just has further to go.
func multi_flip_step(stick: Vector2) -> void:
	var f := flip
	if f == null or shuv != null or f.varial != "" or f.progress >= 1.0:
		multi_out = false
		return
	var side := "left" if f.kick else "right"
	if TrickControls.stick_direction(stick.x, stick.y) != side:
		multi_out = false
		return
	if multi_out:
		return
	multi_out = true
	if f.turns < T.maxFlipTurns and clock - multi_t <= T.multiFlipWindow:
		var done := trick_rotation_ease(f.progress) * float(f.turns)
		f.turns += 1
		f.progress = flip_progress_for(done / float(f.turns))
		f.name = flip_label(f, f.turns)
		multi_t = clock
		event.emit("flipStart", {"name": f.name})


func make_shuv(bs: bool) -> Shuv:
	# Backside is the way the rider's back leads: clockwise seen from above for a regular rider (counter-clockwise for goofy).
	# A varial kickflip shoves backside and a varial heelflip frontside. Like the flip direction, this is the one place to change it.
	var s := Shuv.new()
	s.spin_sign = (1.0 if bs else -1.0) * signf(face_offset)
	s.angle = 0.0
	s.progress = 0.0
	s.bs = bs
	s.done = false
	s.name = trick_prefix + ("" if bs else "Frontside ") + "Pop Shove-it"
	return s


# flip_kick: null for no flip, true for a kickflip, false for a heelflip. shuv_bs: null for no shove-it, else true for backside.
func start_trick(flip_kick, shuv_bs, turns := 1) -> bool:
	var no_flip: bool = typeof(flip_kick) == TYPE_NIL
	var no_shuv: bool = typeof(shuv_bs) == TYPE_NIL
	if mode != Mode.AIR or board_off or flip != null or shuv != null or (no_flip and no_shuv):
		return false
	var hv := heading_vec(heading)
	var fakie := (vel.x * hv.x + vel.z * hv.z < -0.3) != switched   # a board that a shove-it turned round is not "fakie"
	trick_prefix = "Fakie " if fakie else ""
	if not no_flip:
		flip = make_flip(flip_kick)
		if no_shuv and turns > 1:   # flicked twice or three times before B: a double or triple
			flip.turns = clampi(turns, 1, T.maxFlipTurns)
			flip.name = flip_label(flip, flip.turns)
	if not no_shuv:
		shuv = make_shuv(shuv_bs)
	if flip != null and shuv != null:
		flip.varial = "%sVarial %s" % [trick_prefix, "Kickflip" if flip.kick else "Heelflip"]
	multi_out = true   # (the stick is out: it is the push that started this)
	multi_t = clock
	trick_controls.reset()
	spin_lock = true
	var shown := flip.varial if (flip != null and flip.varial != "") else (flip.name if flip != null else shuv.name)
	event.emit("flipStart", {"name": shown})
	return true


# Release a completed animation so the next press can start another trick in this air.
# Preserve the input buffer and spin lock; holding B is still one press, one trick.
func finish_air_trick() -> void:
	if (flip == null and shuv == null) or (flip != null and flip.progress < 1.0) or (shuv != null and not shuv.done):
		return
	if flip != null and flip.varial != "":
		completed_tricks.append(flip.varial)
	elif flip != null:
		completed_tricks.append(flip.name)
	else:
		completed_tricks.append(shuv.name)
	flip = null
	flip_roll = 0.0
	shuv = null
	shuv_yaw = 0.0


# The board has come round 180°: it is now travelling tail first. Turn the heading and the rider's stance with it, so the rider
# (who never moved) still faces the same way, and carry the board's tilts across so nothing jumps.
func commit_shuv() -> void:
	var s := shuv
	if s == null or s.done:
		return
	s.done = true
	s.angle = s.spin_sign * PI
	shuv_yaw = 0.0
	heading = wrap_angle(heading + PI)
	face_offset = -face_offset
	switched = not switched
	# Reparenting 180° of local shove yaw into board heading must preserve the visible orientation.
	# Pitch reverses in the new frame, but roll (including a mid-varial flip) does NOT:
	# reversing the flip here used to make the board snap abruptly halfway through a varial.
	vis_pitch = -vis_pitch


# How far the board is from pointing straight (or straight round), in radians.
func shuv_residual() -> float:
	var s := shuv
	if s == null or s.done:
		return 0.0
	var a := absf(s.angle)
	return minf(a, PI - a)


# How far the board is from lying flat, in radians: the distance to the nearest whole turn.
func flip_residual() -> float:
	var a := absf(flip.angle)
	return absf(a - js_round(a / TAU) * TAU)


func end_flip() -> void:
	flip = null
	flip_roll = 0.0
	shuv = null
	shuv_yaw = 0.0
	completed_tricks.clear()
	trick_controls.reset()
	spin_lock = false


# The name to credit when the board is back under you, or "" if nothing really happened.
func trick_credit() -> String:
	var f := flip
	var s := shuv
	var flip_ok := f != null and absf(f.angle) > PI and flip_residual() <= T.flipCleanRoll
	var shuv_ok := s != null and (s.done or (absf(s.angle) > PI / 2.0 and shuv_residual() <= T.shuvClean))
	var current := ""
	if flip_ok and shuv_ok:
		current = f.varial if f.varial != "" else f.name
	elif flip_ok:
		current = flip_credit_name(f)
	elif shuv_ok:
		current = s.name
	var parts := PackedStringArray()
	for t in completed_tricks:
		if t != "":
			parts.append(t)
	if current != "":
		parts.append(current)
	return " + ".join(parts)


# What is below the airborne board, so its tilt can ease towards that surface's before it lands.
func sample_air_floor() -> void:
	var hit := world.ground(pos.x, pos.z, pos.y + 0.2, _hit, 40.0)
	air_floor_found = hit != null
	if hit != null:
		air_floor_y = hit.y
		air_floor_normal = hit.normal


# Airs near a coping lip stay over the pit regardless of speed unless an ollie and forward input
# deliberately commit to crossing the lip. Once chosen, an exit remains committed for this air.
func lip_air(h: float) -> void:
	var best_path: GrindPath = null
	var best_seg: GrindPath.Segment = null
	var best_t := 0.0
	var best_d := T.lipZone
	var px := pos.x
	var pz := pos.z
	for path in paths:
		if path.kind != "coping":
			continue
		var b := path.bounds
		if maxf(maxf(b.position.x - px, 0.0), px - b.end.x) > best_d or maxf(maxf(b.position.z - pz, 0.0), pz - b.end.z) > best_d:
			continue
		for seg in path.segments:
			var abx := seg.b.x - seg.a.x
			var abz := seg.b.z - seg.a.z
			var len2 := abx * abx + abz * abz
			if len2 < 1e-9:
				continue
			var t := clampf(((px - seg.a.x) * abx + (pz - seg.a.z) * abz) / len2, 0.0, 1.0)
			var d := hypot(px - (seg.a.x + abx * t), pz - (seg.a.z + abz * t))
			if d < best_d:
				best_d = d
				best_path = path
				best_seg = seg
				best_t = t
	if best_seg == null:
		return
	var seg2 := best_seg
	var lip_y := seg2.a.y + (seg2.b.y - seg2.a.y) * best_t + best_path.top_offset
	if pos.y < lip_y + 0.02 or pos.y > lip_y + 10.0:
		return
	var pit = pit_direction(seg2)
	if pit == null:
		return
	var cx := seg2.a.x + (seg2.b.x - seg2.a.x) * best_t
	var cz := seg2.a.z + (seg2.b.z - seg2.a.z) * best_t
	var into_pit: float = (px - cx) * pit.x + (pz - cz) * pit.y   # + over the pit, − over the deck
	var outward: float = -(vel.x * pit.x + vel.z * pit.y)         # + moving out over the lip
	# Speed controls how high you get, never whether you are allowed out.
	# Require a deliberate forward hold during an ollie near the coping; do not drop
	# the exit decision if forward is released while crossing.
	if pass_intent and drive > T.driveThreshold:
		lip_exit = true
	if not lip_exit:
		# A damped spring to just inside the lip line: the air stays over the pit and comes back down against the wall.
		if into_pit > -0.7 and into_pit < T.lipHoldDist + 2.0:
			var acc := clampf(T.lipSpring * (T.lipHoldDist - into_pit) + T.lipDamp * outward, -T.lipMaxAccel, T.lipMaxAccel)
			vel.x += pit.x * acc * h
			vel.z += pit.y * acc * h
	elif into_pit > -T.lipOutwardZone and outward < T.lipOutwardSpeed:
		var dv := minf(T.lipOutwardSpeed - outward, T.lipOutwardAccel * h)
		vel.x -= pit.x * dv
		vel.z -= pit.y * dv


# Rolling slowly off a lip onto a steep wall (a drop-in) the rider leans into the wall and rides it down; without this the
# board just drifts away from the face and free-falls onto the curve, losing most of the speed the drop should give.
func hug_wall(h: float) -> void:
	if not rolled_off or air_time > T.hugTime:
		return
	var hv := hypot(vel.x, vel.z)
	if hv < 0.05 or hv > T.hugMaxSpeed:
		return
	var sd := Vector3(-vel.x / hv, 0.0, -vel.z / hv)
	var a := pos
	a.y -= 0.3
	var c := world.cast(a, sd, T.hugReach, _cast)
	if c == null or c.normal.y > 0.5 or c.normal.x * -sd.x + c.normal.z * -sd.z < 0.5:
		return
	var k := exp(-T.hugDamp * h)
	vel.x *= k
	vel.z *= k


# Continuous collision while airborne: the board's centre and its leading wheels (and, once clear of the edge
# it just left, its trailing wheels) are swept along this step's motion. Whatever they meet first is what the
# board lands on or bounces off, however steep, so there is no separate "wall" guess from wheel heights.
func sweep_board(np: Vector3, h: float) -> bool:
	var sd := np - pos
	var length := sd.length()
	if length < 1e-5:
		return false
	sd = sd / length
	var hv := heading_vec(heading)
	var lead := 1.0 if hv.x * sd.x + hv.z * sd.z >= 0.0 else -1.0
	edge_grace = maxf(0.0, edge_grace - h)
	var best_found := false
	var best_dist := 0.0
	var best_normal := Vector3.UP
	for i in 3:
		if i == 2 and edge_grace > 0.0:
			continue
		var off := 0.0 if i == 0 else (lead if i == 1 else -lead) * BOARD.wheelHalfBase
		var a := pos + hv * off
		a.y += 0.02
		# Just after an ollie the board is still tilted with the ground it left: on a slope the leading wheel would be inside the
		# surface ahead and "land" the board on the spot, so popping on any incline went nowhere. Only the middle counts until it is clear.
		if i != 0 and pop_timer < T.popWheelFree:
			continue
		var c := world.cast(a, sd, length, _cast)
		if c == null or (best_found and c.dist >= best_dist):
			continue
		if i != 0 and c.normal.y >= T.sweepLandMinNormalY:
			# A wheel that clips the edge of a flat surface is only a landing if the board's middle would be over that surface too. With
			# the middle hanging out over a drop (the lip of a ramp) the board just catches the corner, and landing there left it
			# perched on its front wheels, sat "on the coping" and then sinking through the ramp.
			var cx := pos.x + sd.x * c.dist
			var cz := pos.z + sd.z * c.dist
			var cy := pos.y + sd.y * c.dist
			var under := world.ground(cx, cz, cy + T.sweepSupportReach, _hit)
			if under == null or under.y < cy - T.sweepSupportDrop:
				continue
		best_found = true
		best_dist = c.dist
		best_normal = c.normal
	if not best_found:
		return false
	pos += sd * best_dist
	if best_normal.y >= T.sweepLandMinNormalY:
		land_on(best_normal)
		return true
	pos.x += best_normal.x * 0.01
	pos.z += best_normal.z * 0.01
	var wall := SkateWorld.Hit.new()
	wall.dist = best_dist
	wall.normal = best_normal
	hit_wall(wall)
	return true


# Touch down on a surface with this normal: let the wheels settle the board onto it, then run the landing checks.
func land_on(normal: Vector3) -> void:
	ground_normal = normal
	var steep := normal.y < T.steepNormalY
	var w := sample_wheels(pos, heading, pos.y + 0.5, steep)
	if w.count >= 3 and w.has_normal:
		pos = w.centre
		ground_normal = w.normal
	land(true, ground_normal)


func land(has_normal: bool, normal: Vector3) -> void:
	var credit := ""
	var sketchy := false
	# Coming down without the board under you is a slam, however softly.
	if board_off:
		bail("no board")
		return
	if body_roll != 0.0:
		# Back upright (near enough) and it counts; a bit off and you stagger; upside down or on your side and you slam.
		var off := body_roll_residual()
		var turns := int(js_round(absf(body_roll) / TAU))
		var back := body_roll > 0.0
		body_roll = 0.0
		body_roll_vel = 0.0
		body_flipping = false
		body_flip_hold = 0.0
		if off > T.bodyFlipBail:
			bail("flip")
			return
		if off > T.bodyFlipClean:
			sketchy = true
		if turns >= 1:
			credit = "%s%s" % [["", "", "Double ", "Triple "][mini(turns, 3)], "Backflip" if back else "Frontflip"]
	if off_trick != null:
		credit = "%s %s" % [credit, off_trick.name] if credit != "" else off_trick.name
		sketchy = sketchy or catch_sketchy
		off_trick = null
		catch_sketchy = false
	trick_controls.reset()   # a pending attempt must not carry into the next jump
	var board_credit := trick_credit()
	if flip != null or shuv != null:
		# Beginning a flip/shove just before touchdown is not a completed trick.
		# The old residual check treated a barely-started turn as already aligned and silently cancelled it.
		var incomplete_flip := flip != null and absf(flip.angle) < PI
		var incomplete_shuv := shuv != null and not shuv.done and absf(shuv.angle) < PI / 2.0
		if incomplete_flip or incomplete_shuv or (flip != null and flip_residual() > T.flipBailRoll) or (shuv != null and shuv_residual() > T.shuvBail):
			bail("flip")
			return
		sketchy = sketchy or (flip != null and flip_residual() > T.flipCleanRoll) or (shuv != null and shuv_residual() > T.shuvClean)
		if shuv != null and absf(shuv.angle) > PI / 2.0:
			commit_shuv()   # landed it round: you are riding the other way
	var parts := PackedStringArray()
	if board_credit != "":
		parts.append(board_credit)
	if credit != "":
		parts.append(credit)
	credit = " + ".join(parts)
	end_flip()
	if has_normal:
		ground_normal = normal
	else:
		ground_normal = UP
	var n := ground_normal
	var impact := maxf(0.0, -vel.dot(n))
	var tmp := vel + n * (-vel.dot(n))
	var flat_speed := tmp.length()
	if flat_speed > T.landAngleMinSpeed:
		# Compare along the surface, not along the horizontal, so landing on a wall is judged fairly.
		var hv := heading_vec(heading)
		var f := on_surface(hv, n)
		var align := 0.0
		if f.length_squared() > 1e-6:
			align = acos(clampf(absf(tmp.dot(f.normalized())) / flat_speed, 0.0, 1.0))
		if align > T.landMaxAngle:
			bail("landing")
			return
	vel = tmp
	# Coming back down onto a steep wall you are riding it, not slamming into it: most of the fall carries on down the face.
	var wallness := clampf((T.wallLandFrom - n.y) / T.wallLandSpan, 0.0, 1.0)
	if wallness > 0.0 and flat_speed > 1e-3:
		var total := hypot(flat_speed, impact)
		vel *= (flat_speed + (total - flat_speed) * T.wallLandKeep * wallness) / flat_speed
	mode = Mode.GROUND
	rolled_off = false
	pass_intent = false
	grounded_time = 0.0
	spin_vel = 0.0
	vis_pitch *= 0.4
	crouch = RIDER.landCompress * clampf(impact / 6.0, 0.25, 1.3)
	if sketchy:
		vel *= T.flipSketchySpeed
		crouch = maxf(crouch, RIDER.landCompress * 1.3)
		event.emit("sketchy", {})
	event.emit("land", {"impact": impact})
	if credit != "":
		event.emit("flip", {"name": credit})
	var q = manual_queue
	manual_queue = null
	if q != null and clock - q.t <= T.manualQueueWindow:
		try_manual(q.kind, true, credit)


# ----- walls -----------------------------------------------------------------------------------------------
# Throw away the part of the motion that goes into the surface. `c` is the probe hit, or null when we only know we are blocked.
func hit_wall(c: SkateWorld.Hit) -> void:
	var total := vel.length()
	if total < 1e-4:
		return
	var wn: Vector3
	if c != null:
		wn = c.normal
	else:
		var sd := Vector3(vel.x, 0.0, vel.z)
		if sd.length_squared() < 1e-8:
			return
		sd = sd.normalized()
		var probe := Vector3(pos.x, pos.y + 0.12, pos.z)
		var found := world.cast(probe, sd, 0.7, _cast)
		if found != null:
			wn = found.normal
		else:
			wn = -sd
	var vn := vel.dot(wn)
	if vn >= 0.0:
		return
	var impact := -vn
	vel += wn * (-vn * 1.15)
	if impact > T.wallEventSpeed:
		event.emit("wall", {"impact": impact})
	if impact > T.wallBailSpeed:
		bail("wall")


func clamp_bounds(np_in: Vector3) -> Vector3:
	var np := np_in
	var b := bounds
	var cx: float = b.get("cx", 0.0)
	var cz: float = b.get("cz", 0.0)
	var bx: float = b["x"]
	var bz: float = b["z"]
	if np.x > cx + bx:
		np.x = cx + bx
		if vel.x > 0.0:
			vel.x = 0.0
	if np.x < cx - bx:
		np.x = cx - bx
		if vel.x < 0.0:
			vel.x = 0.0
	if np.z > cz + bz:
		np.z = cz + bz
		if vel.z > 0.0:
			vel.z = 0.0
	if np.z < cz - bz:
		np.z = cz - bz
		if vel.z < 0.0:
			vel.z = 0.0
	return np


func inside_solid(p: Vector3) -> bool:
	var hit := world.ground(p.x, p.z, p.y + 12.0, _hit, 40.0)
	return hit != null and hit.y > p.y + 0.02


# Raycasts under the four wheels; fills `wheels` with their contact points and the plane through them.
# Flat ground is probed straight down. Steep ground (a bowl wall) is probed along the board's own normal, because
# a vertical ray cannot see a surface that is almost vertical itself.
func sample_wheels(np: Vector3, p_heading: float, from_y: float, steep: bool = false, trail_vel = null) -> Wheels:
	var w := wheels
	var n := ground_normal
	var hv := heading_vec(p_heading)
	var sf: Vector3
	var sr: Vector3
	if steep:
		sf = on_surface(hv, n)
		sr = sf.cross(n)
	else:
		sf = hv
		sr = Vector3(cos(p_heading), 0.0, -sin(p_heading))
	for k in 4:
		var across := (1.0 if (k & 1) != 0 else -1.0) * BOARD.wheelHalfTrack
		var along := (1.0 if (k & 2) != 0 else -1.0) * BOARD.wheelHalfBase
		var so := np + sf * along + sr * across
		if steep:
			so += n * WHEEL_LIFT
			var sd := -n
			var c := world.cast(so, sd, WHEEL_LIFT + T.steepContact, _cast)
			w.ok[k] = c != null and c.normal.dot(n) > 0.3
			if w.ok[k]:
				w.pts[k] = so + sd * c.dist
				w.nrm[k] = c.normal
				w.h[k] = WHEEL_LIFT - c.dist
		else:
			var hit := world.ground(so.x, so.z, from_y, _hit)
			w.ok[k] = hit != null
			if hit != null:
				w.pts[k] = Vector3(so.x, hit.y, so.z)
				w.nrm[k] = hit.normal
	if trail_vel != null:
		for k in 4:
			var across2 := (1.0 if (k & 1) != 0 else -1.0) * BOARD.wheelHalfTrack
			var along2 := (1.0 if (k & 2) != 0 else -1.0) * BOARD.wheelHalfBase
			if sf.x * along2 * trail_vel.x + sf.z * along2 * trail_vel.z + sr.x * across2 * trail_vel.x + sr.z * across2 * trail_vel.z < 0.0:
				w.ok[k] = false
	var count := 0
	for k in 4:
		if w.ok[k]:
			count += 1
	w.count = count
	w.has_normal = false
	w.max_y = 0.0
	if count == 0:
		return w

	# Three or four wheels define a plane. If that plane disagrees with the surfaces the wheels actually hit, the
	# wheels are straddling a step or an edge rather than lying on a slope: keep only the wheels on the higher surface.
	if count >= 3:
		fit_plane(w)
		var wn := Vector3.ZERO
		for k in 4:
			if w.ok[k]:
				wn += w.nrm[k]
		wn = wn.normalized()
		var straddling := w.normal.dot(wn) < T.planeAgreement
		for k in 4:
			if straddling:
				break
			if w.ok[k] and w.nrm[k].dot(w.normal) < T.wheelAgreement:
				straddling = true
		if straddling:
			var top := -INF
			for k in 4:
				if w.ok[k]:
					top = maxf(top, w.pts[k].dot(wn))
			count = 0
			for k in 4:
				if w.ok[k] and w.pts[k].dot(wn) < top - 0.08:
					w.ok[k] = false
				if w.ok[k]:
					count += 1
			w.count = count
		else:
			w.has_normal = w.normal.y > 0.02 or (steep and w.normal.dot(n) > 0.5)
	# The three-wheel fill above wrote a made-up fourth point; the centre is the mean of the real ones.
	w.centre = Vector3.ZERO
	var real := 0
	var max_y := -INF
	for k in 4:
		if w.ok[k]:
			w.centre += w.pts[k]
			real += 1
			max_y = maxf(max_y, w.pts[k].y)
	w.centre = w.centre / real
	w.max_y = max_y
	if w.has_normal and real == 3:
		# Fourth corner by parallelogram, so the centre sits in the middle of the board, not of three wheels.
		w.centre = Vector3.ZERO
		for k in 4:
			w.centre += w.pts[k]
		w.centre = w.centre / 4.0
	return w


# Plane through the wheel contacts (three valid wheels get a parallelogram fourth). Leaves the normal in w.normal.
func fit_plane(w: Wheels) -> void:
	if w.count == 3:
		var m := w.ok.find(false)
		w.pts[m] = w.pts[m ^ 1] + w.pts[m ^ 2] - w.pts[3 - m]
	var a := w.pts[2] + w.pts[3] - w.pts[0] - w.pts[1]   # rear → front
	var b := w.pts[1] + w.pts[3] - w.pts[0] - w.pts[2]   # left → right
	w.normal = b.cross(a).normalized()


# ----- grinding --------------------------------------------------------------------------------------------
# How far from the middle of the board a rail still catches it, with the board turned `theta` from parallel with the rail: anywhere the
# board would touch it (its footprint across the rail), plus the reach each side. 0: just the width; 90° (a boardslide): its length.
static func board_reach(theta: float) -> float:
	return Config.Board.length / 2.0 * sin(theta) + Config.Board.width / 2.0 * cos(theta) + Config.Tuning.grindReach


func try_grind(np: Vector3, h: float) -> bool:
	if require_grind and grind_arm <= 0.0:
		return false
	var hv := heading_vec(heading)
	var best = null
	var best_score := INF
	for path in paths:
		if path == last_grind_path and grind_cooldown > 0.0:
			continue
		if path.kind == "coping" and pass_intent:
			continue   # going over the top: the coping is not a place to land
		if not path.bounds.has_point(np):
			continue
		var segs := path.segments
		for i in segs.size():
			var seg := segs[i]
			if seg.h_len < 0.05:
				continue
			var abx := seg.b.x - seg.a.x
			var abz := seg.b.z - seg.a.z
			var len2 := abx * abx + abz * abz
			var raw := ((np.x - seg.a.x) * abx + (np.z - seg.a.z) * abz) / len2
			var t := clampf(raw, 0.0, 1.0)
			if absf(raw - t) * sqrt(len2) > 0.12:
				continue
			var cx := seg.a.x + abx * t
			var cz := seg.a.z + abz * t
			var d := hypot(np.x - cx, np.z - cz)
			if d > (T.stallLateral if path.kind == "coping" else board_reach(PI / 2.0)):
				continue
			var theta := acos(clampf(absf(hv.x * seg.dir_h.x + hv.z * seg.dir_h.y), 0.0, 1.0))
			# However the board is turned it is one or the other: along the rail is a 50-50, across it a boardslide.
			var gmode := "truck" if theta < T.grindSplit else "slide"
			var reach := (T.stallLateral if gmode == "slide" else board_reach(0.0)) if path.kind == "coping" else board_reach(theta)
			if d > reach:
				continue
			if gmode == "slide" and path.kind == "coping" and rolling_into_pit(seg, np):
				continue
			var top := seg.a.y + (seg.b.y - seg.a.y) * t + path.top_offset
			var dy := np.y + (BOARD.truckBottom if gmode == "truck" else path.slide_contact) - top
			if dy < -T.catchBelow or dy > T.catchAbove + maxf(0.0, -vel.y * h):
				continue
			var score := d / reach + absf(dy) / 0.1
			if score < best_score:
				best_score = score
				best = {"path": path, "seg": seg, "i": i, "t": t, "mode": gmode, "theta": theta, "d": d, "reach": reach}
	if best == null:
		return false
	return start_grind(best, np)


# Press the grind button near the top of a ramp or bowl wall and the board latches onto the coping and grinds along it: from the wall
# while it is still rolling up, from the air, or from the deck, at whatever angle it arrives. It needs real speed along the lip
# (arriving square-on and slow, there is nothing to grind along).
# np_is_pos: np is the board's own position (the ground step asks with it). The web build passed that very object, so the catch moved it
# onto the rail with nothing to blend (start_grind keeps that).
func try_coping_magnet(np: Vector3, np_is_pos := false) -> bool:
	if not require_grind or grind_arm <= 0.0:
		return false
	var hv := heading_vec(heading)
	var reach: float = T.magnetReach
	var best = null
	var best_score := INF
	for path in paths:
		if path.kind != "coping":
			continue
		if path == last_grind_path and grind_cooldown > 0.0:
			continue
		var b := path.bounds
		if np.x < b.position.x - reach or np.x > b.end.x + reach or np.z < b.position.z - reach or np.z > b.end.z + reach:
			continue
		var segs := path.segments
		for i in segs.size():
			var seg := segs[i]
			if seg.h_len < 0.05:
				continue
			var abx := seg.b.x - seg.a.x
			var abz := seg.b.z - seg.a.z
			var len2 := abx * abx + abz * abz
			var raw := ((np.x - seg.a.x) * abx + (np.z - seg.a.z) * abz) / len2
			var t := clampf(raw, 0.0, 1.0)
			var d := hypot(np.x - (seg.a.x + abx * t), np.z - (seg.a.z + abz * t))
			if d > reach or absf(raw - t) * sqrt(len2) > 0.3:
				continue
			var top := seg.a.y + (seg.b.y - seg.a.y) * t + path.top_offset
			var dy := top - np.y   # + the board is below the lip
			if dy < -T.magnetAbove or dy > T.magnetBelow:
				continue
			if absf(vel.dot(seg.dir)) < T.magnetMinSpeed:
				continue
			var score := d / reach + absf(dy) / T.magnetBelow
			if score < best_score:
				best_score = score
				best = {"path": path, "seg": seg, "i": i, "t": t, "d": d}
	if best == null:
		return false
	var theta := acos(clampf(absf(hv.x * best.seg.dir_h.x + hv.z * best.seg.dir_h.y), 0.0, 1.0))
	best.mode = "truck" if theta <= T.magnetTruckAngle else "slide"
	best.theta = theta
	return start_grind(best, np, np_is_pos)


# Which side of this stretch of coping is the drop (lower ground), as a horizontal unit vector (x, z); cached on the segment.
# Returns a Vector2 or null.
func pit_direction(seg: GrindPath.Segment):
	if not seg.pit_known:
		seg.pit_known = true
		var mx := (seg.a.x + seg.b.x) / 2.0
		var mz := (seg.a.z + seg.b.z) / 2.0
		var y := maxf(seg.a.y, seg.b.y)
		var px := -seg.dir_h.y
		var pz := seg.dir_h.x
		# The ramp is the side with the steep face just inside the lip; the other side is a flat deck, or a drop. (Going by "the lower
		# side" alone picks the wrong side for a wall quarter whose far side is the lower ground outside the building.)
		var face_a := world.ground(mx + px * 0.3, mz + pz * 0.3, y + 1.0, _hit, 30.0)
		var steep_a := (1.0 - face_a.normal.y) if face_a != null else 0.0
		var face_b := world.ground(mx - px * 0.3, mz - pz * 0.3, y + 1.0, _hit, 30.0)
		var steep_b := (1.0 - face_b.normal.y) if face_b != null else 0.0
		if absf(steep_a - steep_b) > 0.25:
			seg.pit = Vector2(px, pz) if steep_a > steep_b else Vector2(-px, -pz)
			return seg.pit
		var hi := world.ground(mx + px * 0.7, mz + pz * 0.7, y + 1.0, _hit, 30.0)
		var lo := hi.y if hi != null else -INF
		var hj := world.ground(mx - px * 0.7, mz - pz * 0.7, y + 1.0, _hit, 30.0)
		var lo2 := hj.y if hj != null else -INF
		if lo == lo2:
			seg.pit = null
		else:
			seg.pit = Vector2(px, pz) if lo < lo2 else Vector2(-px, -pz)
	return seg.pit


# Heading over the coping towards the drop is a drop-in (or an air coming down onto the deck side), not something to stall on.
func rolling_into_pit(seg: GrindPath.Segment, _np: Vector3) -> bool:
	var pit = pit_direction(seg)
	if pit == null:
		return false
	return vel.x * pit.x + vel.z * pit.y > T.stallIntoPit


func start_grind(c: Dictionary, np: Vector3, np_is_pos := false) -> bool:
	var path: GrindPath = c.path
	var seg: GrindPath.Segment = c.seg
	var t: float = c.t
	var gmode: String = c.mode
	var s := seg.start + t * seg.length
	var gs := vel.dot(seg.dir)
	# Square-on to coping and nearly stopped is not a failed grind, it is an axle stall (rock to fakie).
	var stall := gmode == "slide" and path.kind == "coping" and absf(gs) < T.grindMinSpeed
	if absf(gs) < T.grindMinSpeed and not stall:
		return false
	# Dropping back onto a coping while barely moving along it is not a boardslide (it crawled along the lip until the balance meter dumped you).
	if not stall and path.kind == "coping" and gmode == "slide" and absf(gs) < T.copingSlideMinSpeed:
		return false
	# No axle stalls: arriving at a coping almost stopped just rolls you back in. (Catching it made the board sit on the lip, perched
	# on its front wheels, until it rocked out or sank into the ramp; nobody wanted that.)
	if stall:
		return false
	# Pick the board orientation on the rail closest to how we arrived, then see how sloppy the entry was.
	var path_yaw := yaw_of(seg.dir.x, seg.dir.z)
	var options := [0.0, PI] if gmode == "truck" else [PI / 2.0, -PI / 2.0]
	var offset: float = options[0]
	var best_diff := INF
	for o: float in options:
		var diff := absf(wrap_angle(path_yaw + o - heading))
		if diff < best_diff:
			best_diff = diff
			offset = o
	var g := Grind.new()
	g.path = path
	g.mode = gmode
	g.s = s
	g.gs = gs
	g.time = 0.0
	g.yaw_offset = offset
	g.stall = stall
	g.back = Vector3.ZERO
	g.bal = 0.0
	g.bal_vel = 0.0
	g.p1 = _rand() * TAU
	g.p2 = _rand() * TAU
	g.variant = 0
	g.vb = 0.0
	g.v_nose = 0.0
	g.v_tail = 0.0
	g.snap = Vector3.ZERO
	g.name = ""
	# The stick held up or down as you land on the rail starts you in the nosegrind or 5-0.
	if gmode == "truck" and not stall:
		g.variant = variant_for(0)
		g.vb = float(g.variant)
	mode = Mode.GRIND
	grind = g
	grind_arm = 0.0
	if flip != null or shuv != null or completed_tricks.size() > 0:
		var credit := trick_credit()
		if shuv != null and absf(shuv.angle) > PI / 2.0:
			commit_shuv()
		end_flip()
		if credit != "":
			event.emit("flip", {"name": credit})
	vel = seg.dir * gs
	spin_vel = 0.0
	braking = false

	# Where the board would sit if it were already perfectly on the rail, to blend the catch instead of teleporting.
	place_on_rail(g, 0.0)
	if np_is_pos:
		np = pos   # (the web build's np was this very vector, so it now reads as the spot on the rail)
	g.snap = np - pos
	# However the board arrived, the meter starts in the middle.
	g.name = "Axle Stall" if stall else "%s%s" % ["Coping " if path.kind == "coping" else "", "50-50" if gmode == "truck" else "Boardslide"]
	pos = np
	place_on_rail(g, 0.0)
	pos += g.snap
	last_grind_path = path
	event.emit("grindStart", {"name": g.name, "kind": path.kind, "mode": gmode, "pathName": path.name, "speed": absf(gs)})
	return true


# Sets pos / up / heading targets for the current grind state; h is the heading slew time (0: no slew).
func place_on_rail(g: Grind, h: float) -> void:
	var path := g.path
	var seg := path.segment_at(g.s)
	var target := wrap_angle(yaw_of(seg.dir.x, seg.dir.z) + g.yaw_offset)
	if h > 0.0:
		var diff := wrap_angle(target - heading)
		heading = wrap_angle(heading + clampf(diff, -T.grindAlignRate * h, T.grindAlignRate * h))
	var hv := heading_vec(heading)
	var p := path.point_at(g.s)
	p.y += path.top_offset

	# Board attitude: lie along the rail's slope for a 50-50, stay level for a boardslide.
	var face := Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var truck_shift := 0.0
	var u: Vector3
	var f := Vector3.ZERO
	if g.mode == "truck":
		var phi := atan2(seg.dir.y, maxf(seg.h_len, 1e-6))
		var forward_sign := 1.0 if absf(wrap_angle(yaw_of(seg.dir.x, seg.dir.z) - heading)) < PI / 2.0 else -1.0
		f = Vector3(hv.x * cos(phi), forward_sign * sin(phi), hv.z * cos(phi)).normalized()
		var r := f.cross(UP).normalized()
		u = r.cross(f).normalized()
		g.tilt = r * sign_or_one(r.dot(face))
		# Nosegrind (vb > 0): pitched nose-down onto the front truck; 5-0 (vb < 0): nose up onto the back one.
		var a := g.vb * T.variantTilt
		if a != 0.0:
			var ua := u * cos(a) + f * sin(a)
			var fb := f * cos(a) + u * (-sin(a))
			u = ua
			f = fb
			truck_shift = g.vb * BOARD.wheelHalfBase
	else:
		u = UP
		var player_right := face.cross(UP)
		g.tilt = hv * sign_or_one(hv.dot(player_right))
	var rho := clampf(g.bal, -1.0, 1.0) * T.balMaxTilt
	g.u = (u * cos(rho) + g.tilt * sin(rho)).normalized()
	var contact: float = BOARD.truckBottom if g.mode == "truck" else path.slide_contact
	pos = p + g.u * (-contact)
	# The rail is under one truck, so the middle of the board is behind it (nosegrind) or ahead of it (5-0).
	if truck_shift != 0.0:
		pos += f * (-truck_shift)


# Stick up is the nose on the rail, down is the tail; between the two thresholds it stays as it was.
func variant_for(current: int) -> int:
	if drive > T.variantStick:
		return 1
	if drive < -T.variantStick:
		return -1
	return 0 if absf(drive) < T.variantRelease else current


func grind_name(g: Grind) -> String:
	var prefix := "Coping " if g.path.kind == "coping" else ""
	if maxf(g.v_nose, g.v_tail) < T.variantMinTime:
		return prefix + "50-50"
	return prefix + ("Nosegrind" if g.v_nose >= g.v_tail else "5-0 Grind")


func grind_step(h: float) -> void:
	var g := grind
	var path := g.path
	g.time += h

	if pop_request >= 0.0:
		var pop_speed := (T.popMin + (T.popMax - T.popMin) * pop_request) * (T.stallPopScale if g.stall else 0.9)
		pop_request = -1.0
		end_grind("pop", pop_speed)
		return

	# Rolled up to the top of a ramp and stopped on the coping: a held stall rocks back in by itself rather than freezing until the
	# balance meter dumps you.
	if g.stall and g.time > T.stallAutoRock:
		end_grind("rock", T.popMin * T.stallPopScale)
		return

	if g.mode == "truck" and not g.stall:
		g.variant = variant_for(g.variant)
		g.vb += (g.variant - g.vb) * (1.0 - exp(-T.variantResponse * h))
		if g.variant != 0:
			if g.variant > 0:
				g.v_nose += h
			else:
				g.v_tail += h
		g.name = grind_name(g)

	# Speed along the rail: gravity on sloped rails, friction on everything.
	var seg := path.segment_at(g.s)
	if not g.stall:
		g.gs += -T.gravity * seg.dir.y * h
		var fric := path.friction * (1.0 + T.variantDrag * absf(g.vb)) * h
		g.gs -= signf(g.gs) * minf(absf(g.gs), fric)
		g.s += g.gs * h
	roll_speed = g.gs

	if path.closed:
		g.s = fposmod(g.s, path.length)
	elif g.s <= 0.0 or g.s >= path.length:
		g.s = clampf(g.s, 0.0, path.length)
		place_on_rail(g, h)
		end_grind("end", 0.0)
		return
	if not g.stall and absf(g.gs) < T.grindStallSpeed:
		end_grind("stall", 0.0)
		return
	# A coping slide that has slowed to a crawl drops you back into the pit instead of creeping along the lip.
	if not g.stall and path.kind == "coping" and absf(g.gs) < T.copingSlideEnd:
		var pit = pit_direction(path.segment_at(g.s))
		end_grind("stall", 0.0)
		if pit != null:
			# Face the way you are going (down the wall), not along the lip, so the landing on the wall is a clean one.
			vel.x = pit.x * T.copingDropIn
			vel.z = pit.y * T.copingDropIn
			heading = yaw_of(pit.x, pit.y)
			spin_vel = 0.0
		return

	# Balance: left unattended the board leans over and falls off; a push from the hands pushes the lean back.
	var instab := minf(T.balInstab0 + T.balInstabGrow * g.time, T.balInstabMax) * (1.0 + (T.variantHard - 1.0) * absf(g.vb))
	var wobble := T.balWobble * (0.6 * sin(2.3 * g.time + g.p1) + 0.4 * sin(5.7 * g.time + g.p2))
	# The first moments of a grind the pull towards falling is weaker, so there is time to get the hands up.
	var grace := lerpf(T.balGraceStart, 1.0, clampf(g.time / T.balGrace, 0.0, 1.0))
	var acc := (instab * g.bal + wobble) * grace + T.balControl * lean - T.balDamp * g.bal_vel
	g.bal_vel += acc * h
	g.bal += g.bal_vel * h
	if absf(g.bal) >= 1.0:
		g.bal = signf(g.bal)
		bail("balance")
		return

	place_on_rail(g, h)
	g.snap *= exp(-18.0 * h)
	pos += g.snap
	var cur := path.segment_at(g.s)
	vel = cur.dir * g.gs


func end_grind(reason: String, pop_speed: float) -> void:
	var g := grind
	var seg := g.path.segment_at(g.s)
	vel = seg.dir * g.gs
	launch_e = 0.5 * vel.length_squared() + T.gravity * pos.y
	pass_intent = pop_speed > 0.0
	if pop_speed > 0.0:
		vel.y += pop_speed
	if g.stall and pop_speed > 0.0:
		vel += g.back * T.stallBackSpeed
	mode = Mode.AIR
	rolled_off = false
	air_time = 0.0
	exit_align = T.exitAlignTime
	grind_cooldown = T.stallCooldown if g.stall else T.grindCooldown
	last_grind_path = g.path
	pop_timer = 0.0 if pop_speed > 0.0 else 99.0
	if pop_speed > 0.0:
		crouch = -RIDER.popRebound
	grind = null
	event.emit("grindEnd", {"reason": reason, "name": g.name, "time": g.time})


# ----- loops -----------------------------------------------------------------------------------------------
# Rolling onto the curved part of a loop's track hands the board to the loop: from here it is a position s along the track, a
# signed speed along it and a sideways offset. Gravity along the track, rolling drag, and the one real rule of a loop: the track
# can only push, so wherever it would have to pull (speed² × curvature less than gravity's share pulling you off it) you fall.
func try_enter_loop() -> bool:
	for lp in loops:
		if not lp.bounds.has_point(pos):
			continue
		var p = lp.project(pos, lp.s_in, lp.s_out, 0.25)
		if p == null or p.s < lp.s_in or p.s > lp.s_out or absf(p.l) > lp.width / 2.0 - T.loopEdge * 0.5:
			continue
		var lf := lp.frame(p.s)
		var gs := vel.dot(lf.t)
		var hv := heading_vec(heading)
		end_manual("loop")
		mode = Mode.LOOP
		var ls := LoopState.new()
		ls.path = lp
		ls.s = p.s
		ls.gs = gs
		ls.l = clampf(p.l, -(lp.width / 2.0 - T.loopEdge), lp.width / 2.0 - T.loopEdge)
		ls.nose = 1 if hv.dot(lf.t) >= 0.0 else -1
		ls.time = 0.0
		ls.min_ny = 1.0
		ls.entry = "start" if gs >= 0.0 else "end"
		loop = ls
		event.emit("loopStart", {"name": lp.name, "speed": absf(gs)})
		place_on_loop(0.0)
		return true
	return false


func loop_step(h: float) -> void:
	var L := loop
	var lp := L.path
	L.time += h
	var lf := lp.frame(L.s)
	# Ollie out only where the track is still fairly flat (the run in and out); higher up there is nothing to pop from.
	if pop_request >= 0.0:
		if lf.n.y > T.loopPopNy:
			var charge := pop_request
			leave_loop("pop")
			pop(charge)
			return
		pop_request = -1.0
	var gs := L.gs
	gs -= T.gravity * lf.t.y * h
	var sp := absf(gs)
	gs -= signf(gs) * minf(sp, (T.rollFriction + T.airDrag * sp * sp) * T.loopFriction * h)
	# Forward on the stick pumps the bottom half of the loop (the same input that pumps a transition).
	if drive > T.driveThreshold and lf.n.y > 0.0 and sp > 1.2:
		gs += signf(gs) * T.loopPump * clampf(lf.k * 2.0, 0.0, 1.0) * h
	# The track pushes the board towards the middle of the loop with whatever it takes to bend its path: speed² × curvature,
	# less the part of gravity already pressing it on (n.y > 0) or pulling it off (n.y < 0, upside down). Below zero it falls.
	var press := gs * gs * lf.k + T.gravity * lf.n.y
	L.min_ny = minf(L.min_ny, lf.n.y)
	if press < -T.loopGrip:
		vel = lf.t * gs
		event.emit("loopEnd", {"reason": "fell", "name": lp.name, "completed": false})
		bail("loop")
		return
	L.gs = gs
	L.s += gs * h
	# Steering drifts you across the track, never off its edge.
	var edge := lp.width / 2.0 - T.loopEdge
	L.l = clampf(L.l + steer * T.loopSteer * h * sign_or_one(gs), -edge, edge)
	if L.s <= lp.s_in and gs < 0.0:
		leave_loop("start")
		return
	if L.s >= lp.s_out and gs > 0.0:
		leave_loop("end")
		return
	place_on_loop(h)


# Board on the track at the loop's s and l: position, normal, velocity, heading (and the right-side vector for the view).
func place_on_loop(_h: float) -> void:
	var L := loop
	var lf := L.path.frame(L.s)
	pos = lf.p + lf.b * L.l
	ground_normal = lf.n
	vel = lf.t * L.gs
	roll_speed = L.gs * L.nose
	# The nose points along the track (or back along it, riding fakie). Its horizontal direction is the heading; at the very top it
	# flips round, which is what riding over the top is. The board's right side carries the attitude through it.
	var fwd := lf.t * float(L.nose)
	if hypot(fwd.x, fwd.z) > 0.05:
		heading = yaw_of(fwd.x, fwd.z)
	frame_right = fwd.cross(lf.n).normalized()


func leave_loop(where: String) -> void:
	var L := loop
	var lf := L.path.frame(clampf(L.s, 0.0, L.path.length))
	pos = lf.p + lf.b * L.l
	ground_normal = lf.n
	# Out along the lane: the track's last bit of sideways drift is not carried on across the floor.
	var fwd := lf.t - L.path.across * lf.t.dot(L.path.across)
	fwd = fwd.normalized()
	vel = fwd * L.gs
	fwd *= float(L.nose)
	heading = yaw_of(fwd.x, fwd.z)
	mode = Mode.GROUND
	loop = null
	frame_right = null
	# All the way round: came in one end and out of the other, having been upside down.
	var completed := L.min_ny < -0.9 and ((where == "end" and L.entry == "start") or (where == "start" and L.entry == "end"))
	event.emit("loopEnd", {"reason": where, "name": L.path.name, "completed": completed, "time": L.time})


# ----- bail ------------------------------------------------------------------------------------------------
func bail(reason: String) -> void:
	if mode == Mode.BAIL:
		return
	manual = null
	manual_queue = null
	if grind != null:
		grind = null
	mode = Mode.BAIL
	bail_time = 0.0
	braking = false
	var held: bool = board_off and board_off_pose != null   # a board in your hand tumbles away from your hand, not your feet
	var bb := BailBoard.new()
	bb.pos = board_off_pose.pos if held else pos
	bb.vel = vel * 0.8 + Vector3((_rand() - 0.5) * 3.0, 2.5 + _rand() * 2.0, (_rand() - 0.5) * 3.0)
	bb.spin = Vector3((_rand() - 0.5) * 14.0, (_rand() - 0.5) * 10.0, (_rand() - 0.5) * 14.0)
	bb.quat = board_off_pose.quat if held else board_quaternion()
	bail_board = bb
	loop = null
	frame_right = null
	board_off = false
	off_trick = null
	catch_sketchy = false
	board_off_pose = null
	grabbing = false
	body_roll = 0.0
	body_roll_vel = 0.0
	body_flip_hold = 0.0
	body_flipping = false
	end_flip()
	event.emit("bail", {"reason": reason})


func bail_step(dt: float) -> void:
	bail_time += dt
	# The rider skids to a stop; the board tumbles off on its own.
	vel *= exp(-2.6 * dt)
	var np := pos + vel * dt
	var g := world.ground(np.x, np.z, pos.y + 0.5, _hit)
	if g != null and g.y <= pos.y + 0.3:
		pos = Vector3(np.x, g.y, np.z)
	var b := bail_board
	if b != null:
		b.vel.y -= T.gravity * dt
		b.pos += b.vel * dt
		var gb := world.ground(b.pos.x, b.pos.z, b.pos.y + 0.6, _hit)
		var floor_y := gb.y if gb != null else pos.y
		if b.pos.y < floor_y:
			b.pos.y = floor_y
			if b.vel.y < -1.0:
				b.vel.y *= -0.3
			else:
				b.vel.y = 0.0
			b.vel.x *= 0.7
			b.vel.z *= 0.7
			b.spin *= 0.6
		var q := Quaternion.from_euler(Vector3(b.spin.x * dt, b.spin.y * dt, b.spin.z * dt))
		b.quat = q * b.quat
	if bail_time >= T.bailTime:
		respawn(spawn if bail_to_spawn else safe)


# ----- display ---------------------------------------------------------------------------------------------
func update_visuals(dt: float) -> void:
	if mode == Mode.GRIND and grind != null:
		up = grind.u
	elif mode == Mode.LOOP:
		up = up.lerp(ground_normal, 1.0 - exp(-60.0 * dt)).normalized()
	elif mode == Mode.GROUND:
		var lift := 0.0
		var u := ground_normal
		if manual != null:
			# The board rocks back (or forward) onto one pair of wheels; the rider's world rocks with it.
			var a := manual.pitch_sign * (T.manualTilt + manual.bal * T.manualMaxTilt)
			var hv := heading_vec(heading)
			var f := on_surface(hv, ground_normal)
			u = u * cos(a) + f * (-sin(a))
			lift = BOARD.wheelHalfBase * absf(sin(a))
		manual_lift = damp(manual_lift, lift, 14.0, dt)
		up = up.lerp(u, 1.0 - exp(-30.0 * dt)).normalized()
	elif mode == Mode.AIR:
		# Keep the tilt we left the surface with; ease towards what is below, faster as it gets close.
		var rate: float = T.airTiltFar
		var target := UP
		if air_floor_found:
			target = air_floor_normal
			rate += (T.airTiltNear - T.airTiltFar) * clampf(1.0 - (pos.y - air_floor_y) / T.airTiltReach, 0.0, 1.0)
		up = up.lerp(target, 1.0 - exp(-rate * dt)).normalized()
	else:
		up = up.lerp(UP, 1.0 - exp(-1.6 * dt)).normalized()

	if mode != Mode.GROUND:
		manual_lift = damp(manual_lift, 0.0, 14.0, dt)

	if mode == Mode.AIR and pop_timer < T.popAnimTime:
		vis_pitch = 0.5 * sin(PI * pop_timer / T.popAnimTime)
	else:
		vis_pitch = damp(vis_pitch, 0.0, 12.0, dt)
	vis_roll = damp(vis_roll, -carve * 0.16 if mode == Mode.GROUND else 0.0, 12.0, dt)

	var target_crouch: float = RIDER.crouchHold if jump_held else 0.0
	crouch = damp(crouch, target_crouch, RIDER.crouchSettle, dt)


# The board's orientation. With `flair` the pop pitch and carve roll are included (the model); without it this is the
# frame the rider is bolted to: heading plus whatever surface (or grind tilt) the board is lying on.
func board_quaternion(flair: bool = true, p_up = null) -> Quaternion:
	var u: Vector3 = up if p_up == null else p_up
	var hv := heading_vec(heading)
	var r: Vector3
	if frame_right != null:
		r = frame_right - u * frame_right.dot(u)   # on a loop: the track's own frame
	else:
		r = on_surface(hv, u).cross(u)
	if r.length_squared() < 1e-8:
		r = Vector3(cos(heading), 0.0, -sin(heading))
	r = r.normalized()
	var f := u.cross(r)
	var q := Basis(r, u, -f).orthonormalized().get_rotation_quaternion()
	if body_roll != 0.0:
		q = q * Quaternion(Vector3.RIGHT, body_roll)   # flipped over in the air, nose over tail (backflip / frontflip)
	if flair:
		q = q * Quaternion(Vector3.RIGHT, vis_pitch)
		if shuv_yaw != 0.0:
			q = q * Quaternion(Vector3.UP, shuv_yaw)   # spins flat, then the flip rolls about the board's own length
		q = q * Quaternion(Vector3.BACK, vis_roll + flip_roll)
	return q
