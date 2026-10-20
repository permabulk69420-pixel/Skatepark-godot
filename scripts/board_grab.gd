# Grabbing the board in the air. Squeeze a grip button with your hand anywhere near the board and the board comes up to meet it (as if
# you'd tucked your knees), then your hand closes on the nearest edge: the nose, the tail, or either side in the middle of the deck.
# Which hand on which part names the grab. The grab lets go when you let go of the grip, or when the board touches down, lands on a
# rail or bails. The physics never changes for a plain grab; the board and hands only move for the eye.
#
# Taking the board off your feet (board_off.gd): while a hand holds the board, toggle_off() lets it go from your feet and it then
# follows that hand rigidly, from wherever it was, until toggle_off() again catches it (or not, if it is too far off). Let go of the
# grip with it off and you have dropped it: it falls, and you bail when you land. On a flat screen (no hands) it is held out to your
# right instead.
class_name BoardGrab
extends RefCounted

signal event(type: String, data: Dictionary)

const GRAB := {
	"squeezeOn": 0.6,    # grip button travel that starts a grab...
	"squeezeOff": 0.35,  # ...and that ends one (a little lower, so it doesn't flicker)
	"maxLift": 0.45,     # metres the board can come up toward your hand (a tuck of the knees, not a yank across the room)
	"reach": 0.15,       # and how far your hand can still be from the edge after that: so your hand has to be within 0.6 m of the part you grab
	"follow": 16.0,      # per second: how quickly the board comes up (and settles back when you let go)
	"between": 0.17,     # side grabs sit in the middle of the deck, within this of its centre
}
# On a flat screen the board is held out to your right, below the camera.
const DESK_HOLD := Transform3D(Basis(Vector3(0, 0, 1), PI / 2.4), Vector3(0.62, -0.75, -0.25))


# The board's outline from its deck mesh, in the board's own space (nose toward -z, right toward +x, up +y).
class Outline:
	var pts := PackedVector3Array()

	# the side edge at z: its outermost point that way, halfway up the deck's thickness there
	func side(sign_: float, z: float) -> Vector3:
		var near := PackedVector3Array()
		for p in pts:
			if absf(p.z - z) < 0.015:
				near.append(p)
		if near.is_empty():
			return Vector3(sign_ * 0.15, 0.03, z)
		var out := -INF
		for p in near:
			out = maxf(out, p.x * sign_)
		var lo := INF
		var hi := -INF
		for p in near:
			if p.x * sign_ > out - 0.006:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
		return Vector3(sign_ * out, (lo + hi) / 2.0, z)

	# the very tip at x (sign -1: the nose, +1: the tail), halfway up its thickness
	func tip(sign_: float, x: float) -> Vector3:
		var near := PackedVector3Array()
		for p in pts:
			if absf(p.x - x) < 0.02:
				near.append(p)
		if near.is_empty():
			return Vector3(x, 0.05, sign_ * 0.78)
		var out := -INF
		for p in near:
			out = maxf(out, p.z * sign_)
		var lo := INF
		var hi := -INF
		for p in near:
			if p.z * sign_ > out - 0.006:
				lo = minf(lo, p.y)
				hi = maxf(hi, p.y)
		return Vector3(x, (lo + hi) / 2.0, sign_ * out)


class Grab:
	var part := ""
	var name := ""
	var marker: Node3D
	var time := 0.0
	var inward := Vector3.ZERO


var hands: VrHands
var board: Node3D                  # the board's root in the scene (BoardView.root)
var desk: Node3D = null            # on a flat screen: what the board is held relative to (the camera)
var haptics: Haptics = null
var hold := HandleHold.new()
var grabs := {}                    # VrHands.HandState -> Grab
var shape: Outline = null
var offset := Vector3.ZERO         # how far the board has come up towards the hands
var log: Array = []                # finished grabs this jump: { name, time } (for points, later)
# The board off your feet: { hand (a HandState, or null on a flat screen), rel (board relative to the hand), dropped, vel, spin }
var off = null
var settle = null                  # { from, t }
var prev := Vector3.ZERO
var hand_vel := Vector3.ZERO


func _init(p_hands: VrHands, p_board: Node3D, p_desk: Node3D = null, p_haptics: Haptics = null) -> void:
	hands = p_hands
	board = p_board
	desk = p_desk
	haptics = p_haptics


func holding() -> bool:
	return not grabs.is_empty()


func names() -> Array:
	return grabs.values().map(func(g: Grab): return g.name)


static func grab_name(part: String, handedness: String) -> String:
	match part:
		"nose":
			return "Nose grab"
		"tail":
			return "Tail grab"
		"right":
			return "Indy" if handedness == "right" else "Stalefish"
		_:
			return "Melon" if handedness == "left" else "Mute"


# The deck mesh's vertices in the board's own space.
func _outline() -> Outline:
	var deck: MeshInstance3D = null
	var first: MeshInstance3D = null
	var stack: Array = [board]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			if first == null:
				first = n
			var label := String(n.name) + (String(n.get_parent().name) if n.get_parent() != null else "")
			if deck == null and label.to_lower().contains("deck"):
				deck = n
	if deck == null:
		deck = first
	if deck == null:
		return null
	var to_board := board.global_transform.affine_inverse() * deck.global_transform
	var out := Outline.new()
	for s in deck.mesh.get_surface_count():
		var verts: PackedVector3Array = deck.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			out.pts.append(to_board * v)
	return out


# Which part of the board a hand at `local` (the hand's grip, in the board's own space) would take: whichever is closest of the nose
# tip, the tail tip, and the side edges level with the hand (kept within `between` of the middle of the deck).
func pick_grab(local: Vector3) -> Dictionary:
	var cx := clampf(local.x, -0.07, 0.07)
	var cz := clampf(local.z, -GRAB.between, GRAB.between)
	var options := [
		{"part": "nose", "point": shape.tip(-1.0, cx), "axis": Vector3(1, 0, 0), "inward": Vector3(0, 0, 1)},
		{"part": "tail", "point": shape.tip(1.0, cx), "axis": Vector3(1, 0, 0), "inward": Vector3(0, 0, -1)},
		{"part": "right", "point": shape.side(1.0, cz), "axis": Vector3(0, 0, 1), "inward": Vector3(-1, 0, 0)},
		{"part": "left", "point": shape.side(-1.0, cz), "axis": Vector3(0, 0, 1), "inward": Vector3(1, 0, 0)},
	]
	var best: Dictionary = options[0]
	var best_d := INF
	for o in options:
		var d: float = (o.point as Vector3).distance_to(local)
		if d < best_d:
			best_d = d
			best = o
	return best


func _pulse(state, intensity: float, ms: float) -> void:
	if haptics != null and state != null:
		haptics.pulse(intensity, ms, state.handedness)


func _start(state: VrHands.HandState) -> bool:
	if shape == null:
		shape = _outline()
	if shape == null or state.anchor == null:
		return false
	var socket := hold.real_socket(state)
	var local := board.global_transform.affine_inverse() * socket
	# Grab whichever part your hand is actually closest to: the nose, the tail, or the side edge level with your hand.
	var pick := pick_grab(local)
	var marker := Node3D.new()
	marker.name = "Grab %s" % pick.part
	marker.position = pick.point
	board.add_child(marker)
	if marker.global_position.distance_to(socket) > GRAB.maxLift + GRAB.reach:
		_drop_marker(marker)
		return false
	var handle := {"node": marker, "axis": pick.axis, "halfLength": 0.0, "inward": pick.inward, "wristSide": Vector3.UP}
	if not hold.grab(state, handle):
		_drop_marker(marker)
		return false
	var g := Grab.new()
	g.part = pick.part
	g.name = grab_name(pick.part, state.handedness)
	g.marker = marker
	g.inward = pick.inward
	grabs[state] = g
	_pulse(state, 0.5, 45)
	event.emit("grabStart", {"name": g.name, "part": g.part})
	return true


static func _drop_marker(marker: Node3D) -> void:
	marker.get_parent().remove_child(marker)
	marker.free()


func _stop(state: VrHands.HandState, air: bool = false) -> void:
	var g: Grab = grabs.get(state)
	if g == null:
		return
	# Letting go of the board in the air while it is off your feet drops it: it carries on with the hand's speed and falls.
	if air and off != null and off.hand == state and not off.dropped:
		off.dropped = true
		off.vel = hand_vel
		off.spin = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 6.0
		event.emit("dropBoard", {})
	hold.release(state)
	_drop_marker(g.marker)
	grabs.erase(state)
	if g.time > 0.1:
		log.append({"name": g.name, "time": g.time})
	event.emit("grabEnd", {"name": g.name, "part": g.part, "time": g.time})


# After the board has been put where the physics says. `air`: in the air and riding (grabs only start then).
func update(dt: float, air: bool) -> void:
	for state in hands.states:
		var sq := state.squeeze()
		var g: Grab = grabs.get(state)
		if g != null and (not air or sq < GRAB.squeezeOff):
			_stop(state, air)
		elif g == null and air and sq > GRAB.squeezeOn and not state.was_squeezed:
			_start(state)
		state.was_squeezed = sq > GRAB.squeezeOn
	# Bring the board up so the grabbed edges meet the hands (the average, with both), no further than it can come.
	var want := Vector3.ZERO
	if not grabs.is_empty():
		for state in grabs:
			var g: Grab = grabs[state]
			g.time += dt
			want += hold.real_socket(state) - g.marker.global_position
		want = (want / grabs.size()).limit_length(GRAB.maxLift)
	offset = offset.lerp(want, minf(1.0, GRAB.follow * dt))
	if offset.length_squared() > 1e-8:
		board.global_position += offset


# The detach button was pressed (main, after hold): take the board off your feet, or catch it. `sim` is the skater.
func toggle_off(sim: Skater, presenting: bool) -> bool:
	if off == null:
		if sim.mode != Skater.Mode.AIR:
			return false
		var hand = grabs.keys()[0] if not grabs.is_empty() else null
		if hand == null and presenting:
			return false   # in the headset you have to be holding it
		if not sim.detach_board():
			return false
		var anchor: Node3D = hand.controller if hand != null else desk
		var rel := DESK_HOLD
		if hand != null:
			rel = anchor.global_transform.affine_inverse() * board.global_transform
		off = {"hand": hand, "rel": rel, "dropped": false, "vel": Vector3.ZERO, "spin": Vector3.ZERO}
		prev = anchor.global_position
		hand_vel = Vector3.ZERO
		settle = null
		if hand != null:
			_pulse(hand, 0.6, 40)
		return true
	if off.dropped:
		return false   # nothing in your hand to put back
	var bt := board.global_transform
	var bq := bt.basis.orthonormalized().get_rotation_quaternion()
	var feet_q := sim.board_quaternion(false)
	# On a flat screen there is no hand to line it up with: a press always brings it back clean.
	var verdict := {"quality": "clean", "reversed": false}
	if off.hand != null:
		verdict = BoardOff.judge_catch(bt.origin, bq, sim.pos, feet_q)
	if verdict.quality == "miss":
		if off.hand != null:
			_pulse(off.hand, 0.15, 20)
		event.emit("catchMiss", verdict)
		if BoardOff.MISS_BAILS:
			sim.bail("missed catch")
		return false
	sim.catch_board(verdict.quality, verdict.reversed)
	# Swing the last few degrees into line rather than snapping (from where it was, relative to the feet; reversed: the other end first).
	feet_q = sim.board_quaternion(false)
	var from := feet_q.inverse() * bq
	if verdict.reversed:
		from = Quaternion(Vector3.UP, PI) * from
	settle = {"from": from, "t": 0.0}
	offset = bt.origin - sim.pos   # and let the existing lift ease it back down to the feet
	if off.hand != null:
		_pulse(off.hand, 0.9 if verdict.quality == "clean" else 0.6, 60 if verdict.quality == "clean" else 90)
	off = null
	return true


# After update, before toggle_off: while the board is off, put it where the hand has it (or where it has fallen to).
func hold_board(sim: Skater, dt: float) -> void:
	if off != null and sim.mode != Skater.Mode.AIR:
		off = null   # landed (a bail, the sim saw to that) or respawned
		settle = null
	if off == null:
		if settle != null and sim.mode != Skater.Mode.BAIL:
			settle.t += dt
			var k := minf(1.0, settle.t / BoardOff.SETTLE)
			var step := Quaternion.IDENTITY.slerp(settle.from, 1.0 - k)
			var t := board.global_transform
			board.global_transform = Transform3D(Basis(t.basis.orthonormalized().get_rotation_quaternion() * step), t.origin)
			if k >= 1.0:
				settle = null
		return
	if off.dropped:
		off.vel.y -= 9.81 * dt
		var pose_pos: Vector3 = sim.board_off_pose.pos if sim.board_off_pose != null else board.global_position
		var pose_q: Quaternion = sim.board_off_pose.quat if sim.board_off_pose != null else board.global_transform.basis.get_rotation_quaternion()
		var spun := Quaternion.from_euler(off.spin * dt) * pose_q
		board.global_transform = Transform3D(Basis(spun), pose_pos + off.vel * dt)
	else:
		var anchor: Node3D = off.hand.controller if off.hand != null else desk
		board.global_transform = anchor.global_transform * off.rel
		if off.hand != null:
			var p := anchor.global_position
			if dt > 0.0:
				hand_vel = (p - prev) / dt
			prev = p
	# How you hold it decides the name: arms out in a T for a moment while it is in your hand is a Christ Air (on a flat screen, with no
	# arms to see, holding it far from your feet is). The sim keeps the pose in case you bail with it in your hand.
	if sim.off_trick != null:
		sim.off_trick.far = maxf(sim.off_trick.far, board.global_position.distance_to(sim.pos))
		var christ := false
		if hands.states.size() == 2:
			if off.hand != null and not off.dropped and _in_tpose():
				sim.off_trick.tpose += dt
			christ = sim.off_trick.tpose >= BoardOff.CHRIST_HOLD
		else:
			christ = sim.off_trick.far >= BoardOff.CHRIST
		if christ:
			sim.off_trick.name = BoardOff.NAME_FAR
	sim.board_off_pose = {"pos": board.global_position, "quat": board.global_transform.basis.orthonormalized().get_rotation_quaternion()}


# Are both hands out in a T about the head right now?
func _in_tpose() -> bool:
	var left = null
	var right = null
	for h in hands.states:
		if not h.tracked():
			return false
		if h.handedness == "left":
			left = h.controller.global_position
		else:
			right = h.controller.global_position
	return left != null and right != null and BoardOff.is_tpose(desk.global_position, left, right)


func off_state() -> Dictionary:
	if off == null:
		return {}
	return {"dropped": off.dropped, "hand": off.hand.handedness if off.hand != null else ""}


# After the hands have posed: fit each holding hand onto its edge.
func place() -> void:
	for state in grabs.keys():
		hold.place(state)


func release_all() -> void:
	for state in grabs.keys():
		_stop(state)


func clear_log() -> void:
	log.clear()
