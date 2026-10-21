# Riding a dirt bike: you, the bike, and your hands on its bars. Walk up to a bike to get on (it is the same as stepping on the board); in
# the headset you sit on it: you turn and pitch with it, and the bike leans as far as your head does.
#   The headset: squeeze a grip with a hand on a handlebar grip to hold it. Twist the right grip back for throttle, as on a real bike; the
#   right trigger is the brake. With both hands on, the bars turn the way you turn them. Lean your body (your head, side to side over the
#   pegs) and the bike leans with you and turns that way; bars and leaning work together. Let go with both and it shuts off and coasts.
#   Nearly stopped, the left stick walks it forwards or back.
#   A flat screen: W throttle, S brake (and, stopped, back), A / D steer.
# Getting off is the same as stepping off the board (the right stick held down, Q on a flat screen); you stand beside it on the left.
class_name BikeRide
extends RefCounted

const MOUNT_REACH := 0.5           # metres: your feet this close (across) to the middle of the pegs gets you on
const MOUNT_HEIGHT := 0.6          # and about level with the ground it stands on
const GRIP_REACH := 0.16           # a hand this close to a grip takes it when it squeezes
const BAR_GRIP := "res://assets/hands/bar_grip_solution.json"   # how each hand closes round a grip (tools/solve_bar_grip.gd)
const SQUEEZE_ON := 0.6
const SQUEEZE_OFF := 0.35
const TWIST_DEAD := deg_to_rad(4.0)     # twisting the right grip back: nothing for this much,
const TWIST_FULL := deg_to_rad(50.0)    # full throttle at this much
const STEP_OFF_SIDE := 0.75        # getting off puts you this far to the left of the bike
const SEATED_EYE := 1.65           # the headset: the eyes this high above the ground, as sitting on the seat (whatever your own height, and
                                   # whether you stand or sit for real)
const FLAT_EYE := 1.55             # a flat screen: the eye above the ground,
const FLAT_LOOK_DOWN := 0.18       # looking a little down the road

var bike: DirtBike
var rig: Node3D
var camera: Camera3D
var hands: VrHands
var vr: bool
var hold := HandleHold.new()
var grips := {}                    # "left" / "right" -> { state, from: the hand's turn in the bike's frame when it took hold, board: what
                                   # the hand had for holding the board (put back when it lets go) }
static var bar_grip = null         # the solution, read once
var rig_rel := Transform3D.IDENTITY   # the rig in the bike's level frame (headset)
var head_rest := Vector3.ZERO      # where the headset was in the rig when you got on (headset)
var twist := 0.0                   # how far the right grip is twisted back (radians)
var look_yaw := 0.0                # a flat screen: dragging to look about
var look_pitch := 0.0
var controls := DirtBike.Controls.new()


# Is a body at `feet` close enough to get on the bike `node`?
static func reaches(node: Node3D, feet: Vector3) -> bool:
	var rider := node.global_transform * (DirtBike.RIDER + Vector3(0.0, 0.0, 0.1))
	return Vector2(feet.x - rider.x, feet.z - rider.z).length() < MOUNT_REACH and absf(feet.y - node.global_position.y) < MOUNT_HEIGHT


func _init(p_bike: DirtBike, p_rig: Node3D, p_camera: Camera3D, p_hands: VrHands, p_vr: bool) -> void:
	bike = p_bike
	rig = p_rig
	camera = p_camera
	hands = p_hands
	vr = p_vr
	if vr:
		# the head over the seat at a sitting rider's height, facing the way the bike does
		var head_local := camera.position
		var forward_local := -camera.transform.basis.z
		var head_yaw := atan2(-forward_local.x, -forward_local.z)
		var target := bike.rider_point()
		var basis := Basis(Vector3.UP, bike.yaw - head_yaw)
		var xf := Transform3D(basis, Vector3(target.x, target.y + SEATED_EYE - head_local.y, target.z) - basis * Vector3(head_local.x, 0.0, head_local.z))
		rig_rel = bike.upright_transform().affine_inverse() * xf
		head_rest = head_local
	_follow()


# One frame of riding. `brake` (the right trigger, S) and `paddle` (the left stick forward / back) come from the caller, as do, on a flat
# screen, `flat_throttle` and `flat_steer`. Returns what the bike did ("", "land", "hit", "shift").
func update(dt: float, brake: float, paddle: float, flat_throttle := 0.0, flat_steer := 0.0) -> String:
	controls.brake = brake
	controls.paddle = paddle
	if vr:
		_update_grips()
		controls.throttle = throttle_for(twist) if grips.has("right") else 0.0
		controls.steer = 0.0
		controls.steer_to = DirtBike.hand_steer(bar_angle(), bike.speed) if grips.has("left") and grips.has("right") else NAN
		controls.lean = body_lean()
	else:
		controls.throttle = flat_throttle
		controls.steer = flat_steer
		controls.steer_to = NAN
		controls.lean = 0.0
	var happened := bike.update(controls, dt)
	_follow()
	return happened


# How far the rider leans the bike (radians, left +), one for one: how far the headset is tilted away from the bike's middle (the upright
# plane through it, front to back). (The view is bolted to the bike, so the bike leaning with you does not tilt your head in its frame:
# leaning is only ever you.)
func body_lean() -> float:
	var head_up := (bike.upright_transform().basis.inverse() * camera.global_basis.y).normalized()
	return asin(clampf(-head_up.x, -1.0, 1.0))


# Throttle from how far the right grip is twisted back.
static func throttle_for(angle: float) -> float:
	return clampf((angle - TWIST_DEAD) / (TWIST_FULL - TWIST_DEAD), 0.0, 1.0)


# The angle the rider's hands hold the bars at: the line from the left hand to the right, turned about the vertical in the frame the rider
# rides in (the right hand forward is a left turn).
func bar_angle() -> float:
	var left := (grips.left.state as VrHands.HandState).controller.global_position
	var right := (grips.right.state as VrHands.HandState).controller.global_position
	return bar_angle_of(bike.upright_transform().basis.inverse() * (right - left))


static func bar_angle_of(bar: Vector3) -> float:
	return atan2(-bar.z, bar.x)


# How far a hand has turned about the bar since it took hold (`from` and `now`: the hand in the bike's frame), back (towards the rider)
# being +: the part of the turn that is about the bar's axis (+X), whatever else the wrist does.
static func twist_about_bar(from: Quaternion, now: Quaternion) -> float:
	var turn := now * from.inverse()
	if turn.w < 0.0:
		turn = -turn
	return 2.0 * atan2(turn.x, turn.w)


# Each hand takes a grip when it squeezes near one, and lets go when it stops squeezing.
func _update_grips() -> void:
	# (measured in the frame the rider rides in, which moves with the bike: its pitching up a ramp or leaning is not a twist)
	var frame := bike.upright_transform().basis.get_rotation_quaternion().inverse()
	for state in hands.states:
		var side := state.handedness
		var held: bool = grips.has(side)
		var squeezing := state.squeeze() > (SQUEEZE_OFF if held else SQUEEZE_ON)
		var marker: Node3D = bike.grip_markers[side]
		if not held and squeezing and state.tracked() and not state.held:
			if hold.real_socket(state).distance_to(marker.global_position) < GRIP_REACH:
				# (held at the middle of the grip: it does not slide along it)
				var handle := {"node": marker, "axis": Vector3.RIGHT, "halfLength": 0.0}
				if hold.grab(state, handle):
					grips[side] = {"state": state, "from": frame * state.controller.global_basis.get_rotation_quaternion(),
						"board": {"offset": state.bar_offset, "paths": state.paths}}
					_fit_to_grip(state)
		elif held and not squeezing:
			_let_go(side)
	twist = 0.0
	if grips.has("right"):
		var right: VrHands.HandState = grips.right.state
		twist = twist_about_bar(grips.right.from, frame * right.controller.global_basis.get_rotation_quaternion())


# The hand closes round a round grip, not the board's thin edge: the grip's place in the hand and the fingers' paths from the bar-grip
# solution (the fingers stop at the rubber instead of closing through it).
func _fit_to_grip(state: VrHands.HandState) -> void:
	if bar_grip == null and FileAccess.file_exists(BAR_GRIP):
		bar_grip = JSON.parse_string(FileAccess.get_file_as_string(BAR_GRIP))
	if bar_grip == null or not (bar_grip as Dictionary).has(state.handedness):
		return
	var mine: Dictionary = bar_grip[state.handedness]
	state.bar_offset = Vector3(mine.bar_offset[0], mine.bar_offset[1], mine.bar_offset[2])
	state.paths = mine.fingers
	state.path_elapsed = 0.0


func _let_go(side: String) -> void:
	var state: VrHands.HandState = grips[side].state
	hold.release(state)
	state.bar_offset = grips[side].board.offset
	state.paths = grips[side].board.paths
	grips.erase(side)


# After the hands have posed: each holding hand onto its grip.
func place_hands() -> void:
	for side in grips:
		hold.place(grips[side].state)


func holding(side: String) -> bool:
	return grips.has(side)


# Getting off: the hands let go. Returns where to stand (beside the bike, on its left) and which way to face.
func end() -> Dictionary:
	for side in grips.keys():
		_let_go(side)
	var level := bike.level_transform()
	return {"pos": level * Vector3(-STEP_OFF_SIDE, 0.0, 0.1), "yaw": bike.yaw}


# The rig rides on the bike: it turns and pitches with it. Your head stays on the bike's centre line as it goes over, a rider's head over
# the seat and the bars, however far it leans; only your own tilt rolls your view (the bike leans as far as your head does, so the two stay
# together and the bars stay at your hands). Rolled by the lean too, your view turned twice as far as you leaned. Your head still moves
# up and down and back and forward as you move it, but not sideways: that is the bike's, in its lean. On a flat screen the eye is over the
# pegs, looking down the road.
func _follow() -> void:
	var upright := bike.upright_transform()
	if vr:
		var turned := upright.basis * rig_rel.basis
		var rest := rig_rel * head_rest   # where your head sat on the bike when you got on, in its frame: on its centre line
		var head := camera.position
		var moved := Vector3(0.0, head.y - head_rest.y, head.z - head_rest.z)   # (in the bike's own frame, so it goes over with it)
		rig.global_transform = Transform3D(turned, bike.ride_transform() * (rest + moved) - turned * head)
	else:
		var seat := Vector3(0.0, DirtBike.SEAT_HEIGHT, DirtBike.RIDER.z)
		var frame := Transform3D(upright.basis, upright.origin + bike.ride_transform() * seat - upright * seat)
		rig.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, look_yaw), frame * (DirtBike.RIDER + Vector3(0.0, FLAT_EYE, 0.0)))
		camera.position = Vector3.ZERO
		camera.rotation = Vector3(-FLAT_LOOK_DOWN + look_pitch, 0.0, 0.0)


func turn_view(dx: float, dy: float) -> void:
	look_yaw = clampf(look_yaw - dx * 0.003, -2.0, 2.0)
	look_pitch = clampf(look_pitch - dy * 0.003, -1.2, 1.2)
