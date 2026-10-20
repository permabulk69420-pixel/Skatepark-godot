# Picking the board up and carrying it in a hand while on foot. Squeeze a grip with your hand near the board to pick it up; it then
# follows that hand exactly (turn your wrist and it turns with it) until you let go, and what the hand was doing when you let go is what
# it does next: let it drop and it falls, swing and let go and it is thrown (board_prop.gd takes over from there).
#
# How it sits in the hand depends on what you took hold of. By the nose or the tail it hangs out of the bottom of your fist, the way a
# carried board does: the tip in your fist, the rest running down along the handle with its top toward your leg. The hand stays exactly
# on the controller. By a side it stays turned the way it was lying, with your hand fitted onto that edge (the same fit the grabs in
# the air use).
class_name BoardCarry
extends RefCounted

signal picked(part: String)
signal released(pose: Transform3D, velocity: Vector3, spin: Vector3)

const REACH := 0.5            # metres: the nearest part of the board has to be within this of your hand to pick it up
const EASE := 0.15            # seconds the board takes to come to the hand
const SQUEEZE_ON := 0.6
const SQUEEZE_OFF := 0.35
const MAX_THROW := 12.0       # m/s
const MAX_SPIN := 25.0        # rad/s

var hands: VrHands
var grab: BoardGrab           # for the deck's outline and which part of it a hand takes
var board: Node3D             # BoardView.root
var hold := HandleHold.new()
var held = null               # { state, part, marker, rel (the board relative to the controller), from (where it was), t }
var hand_vel := Vector3.ZERO
var hand_spin := Vector3.ZERO
var _prev_p := Vector3.ZERO
var _prev_q := Quaternion.IDENTITY
var _seen := false
var _squeezed := {}           # HandState -> squeezing last frame


func _init(p_hands: VrHands, p_grab: BoardGrab, p_board: Node3D) -> void:
	hands = p_hands
	grab = p_grab
	board = p_board


func holding() -> bool:
	return held != null


func hand_name() -> String:
	return held.state.handedness if held != null else ""


# Once a frame, after the hands have posed. `pose`: where the board is lying (from its physics) while nobody has it. `allow(state)`:
# may this hand pick something up right now (it is not holding something else)? Returns the board's pose.
func update(dt: float, pose: Transform3D, allow: Callable) -> Transform3D:
	for state in hands.states:
		var squeezing: bool = state.squeeze() > (SQUEEZE_OFF if held != null and held.state == state else SQUEEZE_ON)
		var was: bool = _squeezed.get(state, false)
		if held == null and squeezing and not was and state.tracked() and allow.call(state):
			_pick(state, pose)
		elif held != null and held.state == state and not squeezing:
			_let_go()
		_squeezed[state] = squeezing
	if held == null:
		return pose
	var state: VrHands.HandState = held.state
	_track(state.controller, dt)
	held.t = minf(1.0, held.t + dt / EASE)
	var target: Transform3D = state.controller.global_transform * held.rel
	var k: float = held.t * held.t * (3.0 - 2.0 * held.t)
	return (held.from as Transform3D).interpolate_with(target, k)


# After the board has been moved to that pose and the hands have posed: fit the hand onto what it is holding.
func place() -> void:
	if held != null and not held.hanging:
		hold.place(held.state)


# Let go without throwing (the board is being put somewhere else: stepped onto, say).
func drop_quietly() -> void:
	if held == null:
		return
	_release_hand(held)
	_free_marker(held.marker)
	held = null


func _pick(state: VrHands.HandState, pose: Transform3D) -> void:
	if state.held:
		return   # that hand has the remote or something else
	grab.ensure_shape()
	if grab.shape == null:
		return
	board.global_transform = pose
	var socket := hold.real_socket(state)
	var local := pose.affine_inverse() * socket
	var pick := grab.pick_grab(local)
	if (pose * (pick.point as Vector3)).distance_to(socket) > REACH:
		return
	var marker := Node3D.new()
	marker.name = "Carry %s" % pick.part
	marker.position = pick.point
	board.add_child(marker)
	var hanging: bool = pick.part == "nose" or pick.part == "tail"
	var in_socket: Transform3D
	var socket_world: Transform3D = state.model.socket_global()
	if hanging:
		# the hand stays on the controller: only the fist pose is set
		state.held = true
		state.held_pose = VrHands.GRIP_POSES["medium"]
		state.path_elapsed = 0.0
		in_socket = hanging_pose(state, pick)
	else:
		var handle := {"node": marker, "axis": pick.axis, "halfLength": 0.0, "inward": pick.inward, "wristSide": Vector3.UP}
		if not hold.grab(state, handle):
			_free_marker(marker)
			return
		socket_world = state.model.socket_global()
		var turn := socket_world.basis.inverse() * pose.basis
		in_socket = Transform3D(turn, state.bar_offset - turn * (pick.point as Vector3))
	var target := socket_world * in_socket
	held = {
		"state": state, "part": pick.part, "marker": marker, "hanging": hanging,
		"rel": state.controller.global_transform.affine_inverse() * target,
		"from": pose, "t": 0.0,
	}
	_seen = false
	hand_vel = Vector3.ZERO
	hand_spin = Vector3.ZERO
	picked.emit(pick.part)


# The board's pose in the hand's grip frame when it is held by its nose or tail: the tip in the fist (on the solved bar), the rest of the
# board running out of the bottom of the fist along the handle (the bar's direction, whichever way points down when you hold the
# controller upright), and the top of the board facing the way the palm faces (toward your leg).
func hanging_pose(state: VrHands.HandState, pick: Dictionary) -> Transform3D:
	var socket_world: Transform3D = state.model.socket_global()
	var to_socket := socket_world.basis.inverse()
	var down_in_socket: Vector3 = to_socket * (state.controller.global_transform.basis.orthonormalized() * Vector3.DOWN)
	var bar := Vector3.UP
	var dir := bar if down_in_socket.dot(bar) >= 0.0 else -bar
	var top: Vector3 = state.plate_out - dir * state.plate_out.dot(dir)
	top = top.normalized() if top.length() > 1e-4 else Vector3.RIGHT
	var inward: Vector3 = pick.inward
	var source := Basis(inward, Vector3.UP, inward.cross(Vector3.UP))
	var target := Basis(dir, top, dir.cross(top))
	var turn := target * source.inverse()
	return Transform3D(turn, state.bar_offset - turn * (pick.point as Vector3))


func _let_go() -> void:
	var state: VrHands.HandState = held.state
	var marker: Node3D = held.marker
	var pose := board.global_transform
	var v := hand_vel + hand_spin.cross(pose.origin - state.controller.global_position)
	_release_hand(held)
	_free_marker(marker)
	held = null
	released.emit(pose, v.limit_length(MAX_THROW), hand_spin.limit_length(MAX_SPIN))


func _release_hand(h: Dictionary) -> void:
	if h.hanging:
		var state: VrHands.HandState = h.state
		state.held = false
		state.held_pose = null
	else:
		hold.release(h.state)


func _track(controller: Node3D, dt: float) -> void:
	var p := controller.global_position
	var q := controller.global_transform.basis.get_rotation_quaternion()
	if _seen and dt > 0.0:
		var blend := minf(1.0, 20.0 * dt)
		hand_vel = hand_vel.lerp((p - _prev_p) / dt, blend)
		var dq := q * _prev_q.inverse()
		if dq.w < 0.0:
			dq = -dq
		var angle := dq.get_angle()
		var turn := dq.get_axis() * angle / dt if angle > 1e-5 else Vector3.ZERO
		hand_spin = hand_spin.lerp(turn, blend)
	_prev_p = p
	_prev_q = q
	_seen = true


static func _free_marker(marker: Node3D) -> void:
	if marker != null and marker.get_parent() != null:
		marker.get_parent().remove_child(marker)
		marker.free()
