# Riding a dirt bike: you, the bike, and your hands on its bars. Walk up to a bike to get on (it is the same as stepping on the board); in
# the headset you stand on its pegs, bolted to it as you are to the board: you turn, pitch and lean with it.
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
const SQUEEZE_ON := 0.6
const SQUEEZE_OFF := 0.35
const TWIST_DEAD := deg_to_rad(4.0)     # twisting the right grip back: nothing for this much,
const TWIST_FULL := deg_to_rad(50.0)    # full throttle at this much
const BODY_DEAD := 0.03            # metres your head can be off the middle of the bike, side to side, without leaning it,
const BODY_FULL := 0.22            # and this far is leaning all the way
const STEP_OFF_SIDE := 0.75        # getting off puts you this far to the left of the bike
const FLAT_EYE := 1.55             # a flat screen: the eye above the ground,
const FLAT_LOOK_DOWN := 0.18       # looking a little down the road

var bike: DirtBike
var rig: Node3D
var camera: Camera3D
var hands: VrHands
var vr: bool
var hold := HandleHold.new()
var grips := {}                    # "left" / "right" -> { state, from: the hand's turn in the bike's frame when it took hold }
var rig_rel := Transform3D.IDENTITY   # the rig in the bike's level frame (headset)
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
		# the head over the pegs, facing the way the bike does, the feet on the pegs
		var head_local := camera.position
		var forward_local := -camera.transform.basis.z
		var head_yaw := atan2(-forward_local.x, -forward_local.z)
		var target := bike.rider_point()
		var basis := Basis(Vector3.UP, bike.yaw - head_yaw)
		var xf := Transform3D(basis, Vector3(target.x, target.y + DirtBike.PEG_HEIGHT, target.z) - basis * Vector3(head_local.x, 0.0, head_local.z))
		rig_rel = bike.ride_transform().affine_inverse() * xf
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


# How far the rider leans (-1..1, left +): the head's way off the middle of the bike, side to side. (The view is bolted to the bike, so the
# bike leaning with you does not move your head in its frame: leaning is only ever you.)
func body_lean() -> float:
	var off := -(bike.ride_transform().affine_inverse() * camera.global_position).x
	return signf(off) * clampf((absf(off) - BODY_DEAD) / (BODY_FULL - BODY_DEAD), 0.0, 1.0)


# Throttle from how far the right grip is twisted back.
static func throttle_for(angle: float) -> float:
	return clampf((angle - TWIST_DEAD) / (TWIST_FULL - TWIST_DEAD), 0.0, 1.0)


# The angle the rider's hands hold the bars at: the line from the left hand to the right, turned about the vertical in the frame the rider
# rides in (the right hand forward is a left turn).
func bar_angle() -> float:
	var left := (grips.left.state as VrHands.HandState).controller.global_position
	var right := (grips.right.state as VrHands.HandState).controller.global_position
	return bar_angle_of(bike.ride_transform().basis.inverse() * (right - left))


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
	var frame := bike.ride_transform().basis.get_rotation_quaternion().inverse()
	for state in hands.states:
		var side := state.handedness
		var held: bool = grips.has(side)
		var squeezing := state.squeeze() > (SQUEEZE_OFF if held else SQUEEZE_ON)
		var marker: Node3D = bike.grip_markers[side]
		if not held and squeezing and state.tracked() and not state.held:
			if hold.real_socket(state).distance_to(marker.global_position) < GRIP_REACH:
				var handle := {"node": marker, "axis": Vector3.RIGHT, "halfLength": 0.04}
				if hold.grab(state, handle):
					state.held_pose = VrHands.GRIP_POSES["thin"]
					grips[side] = {"state": state, "from": frame * state.controller.global_basis.get_rotation_quaternion()}
		elif held and not squeezing:
			hold.release(state)
			grips.erase(side)
	twist = 0.0
	if grips.has("right"):
		var right: VrHands.HandState = grips.right.state
		twist = twist_about_bar(grips.right.from, frame * right.controller.global_basis.get_rotation_quaternion())


# After the hands have posed: each holding hand onto its grip.
func place_hands() -> void:
	for side in grips:
		hold.place(grips[side].state)


func holding(side: String) -> bool:
	return grips.has(side)


# Getting off: the hands let go. Returns where to stand (beside the bike, on its left) and which way to face.
func end() -> Dictionary:
	for side in grips.keys():
		hold.release(grips[side].state)
	grips.clear()
	var level := bike.level_transform()
	return {"pos": level * Vector3(-STEP_OFF_SIDE, 0.0, 0.1), "yaw": bike.yaw}


# The rig is bolted to the bike: it keeps where it was on it, turning, pitching and leaning with it. On a flat screen the eye is over the
# pegs, looking down the road.
func _follow() -> void:
	var frame := bike.ride_transform()
	if vr:
		rig.global_transform = frame * rig_rel
	else:
		rig.global_transform = Transform3D(frame.basis * Basis(Vector3.UP, look_yaw), frame * (DirtBike.RIDER + Vector3(0.0, FLAT_EYE, 0.0)))
		camera.position = Vector3.ZERO
		camera.rotation = Vector3(-FLAT_LOOK_DOWN + look_pitch, 0.0, 0.0)


func turn_view(dx: float, dy: float) -> void:
	look_yaw = clampf(look_yaw - dx * 0.003, -2.0, 2.0)
	look_pitch = clampf(look_pitch - dy * 0.003, -1.2, 1.2)
