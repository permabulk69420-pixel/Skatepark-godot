# Holding the edge of something with a hand: the board's edge. One rule for it: the hollow of the closed hand goes on the edge.
#
# The web build solved that at every grab (the plate in the hand, slid out of the palm until it cleared the skin); here the answer is
# pre-solved (tools/solve_grip.gd) and stored per hand: where the plate sits in the grip socket (bar_offset) and which way it runs out of
# the palm (plate_out). Every frame the hand model is then moved (from where the controller really holds it) so that plate lies on the
# real edge: same line, the point nearest the hand, turned so the plate runs off inward along the board, with the wrist on the top side.
#
# A handle is { node: a marker on the edge, axis: the edge's direction in the marker's space, halfLength: how far either way the hand may
# slide, inward: which way the board runs off the edge, wristSide: the side the wrist comes from }.
#   grab(state, handle)  when the squeeze starts      place(state)  every frame after the board has moved
#   release(state)       when the squeeze ends
class_name HandleHold
extends RefCounted

var holds := {}    # VrHands.HandState -> { handle }


func holding(state: VrHands.HandState) -> bool:
	return holds.has(state)


# Start holding `handle` with this hand. False if the hand has no model yet or is already holding something else.
func grab(state: VrHands.HandState, handle: Dictionary) -> bool:
	if state == null or state.anchor == null or state.model == null or handle.get("node") == null:
		return false
	if holds.has(state):
		holds[state].handle = handle
		return true
	if state.held:
		return false
	holds[state] = {"handle": handle}
	state.held = true
	state.held_pose = VrHands.GRIP_POSES["medium"]
	state.path_elapsed = 0.0
	return true


# Where the hand really is (the controller's pose, before any hold moved the model): the grip socket's world position.
func real_socket(state: VrHands.HandState) -> Vector3:
	_restore(state)
	return state.model.socket_global().origin


func _restore(state: VrHands.HandState) -> void:
	if state.anchor != null:
		state.anchor.transform = state.home


# Move the hand model so the solved plate lies on the edge. Call every frame, after whatever carries the board has moved.
func place(state: VrHands.HandState) -> void:
	var hold = holds.get(state)
	if hold == null:
		return
	var handle: Dictionary = hold.handle
	var anchor := state.anchor
	_restore(state)
	var anchor_world := anchor.global_transform
	var socket_in_anchor := anchor_world.affine_inverse() * state.model.socket_global()
	# the plate as the solver left it, in the hand model's frame (it has no turn of its own in the socket's frame)
	var bar_in_anchor := socket_in_anchor * Transform3D(Basis.IDENTITY, state.bar_offset)
	var bar_world := anchor_world * bar_in_anchor
	var p := bar_world.origin
	var q := bar_world.basis.orthonormalized().get_rotation_quaternion()
	# the edge: its line through the marker
	var node: Node3D = handle.node
	var c := node.global_position
	var handle_q := node.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var axis := (handle_q * (handle.get("axis", Vector3.UP) as Vector3)).normalized()
	var half: float = handle.get("halfLength", 0.0)
	# turn the plate (as little as it takes, either way round) onto the edge's line, then put it on the line at the nearest point
	var bar_axis := q * Vector3.UP
	if bar_axis.dot(axis) < 0.0:
		axis = -axis
	var along := clampf((p - c).dot(axis), -half, half)
	var nq := Quaternion(bar_axis, axis) * q
	p = c + axis * along
	var inverse_bar := bar_in_anchor.affine_inverse()
	if handle.has("inward"):
		# Turn the hand about the edge until the plate runs off inward.
		var palm := nq * state.plate_out
		palm -= axis * palm.dot(axis)
		var inward := handle_q * (handle.inward as Vector3)
		inward -= axis * inward.dot(axis)
		if palm.length_squared() > 1e-8 and inward.length_squared() > 1e-8:
			palm = palm.normalized()
			inward = inward.normalized()
			var angle := atan2(palm.cross(inward).dot(axis), palm.dot(inward))
			nq = Quaternion(axis, angle) * nq
		# A hand reaching for an edge comes from the `wristSide` (the top of a board): if this fit would put the wrist on the other side,
		# turn it over about the inward direction (the edge runs the other way, the plate still runs inward).
		if handle.has("wristSide"):
			var wrist_up := handle_q * (handle.wristSide as Vector3)
			var wrist_at := (Transform3D(Basis(nq), p) * inverse_bar).origin
			if (wrist_at - p).dot(wrist_up) < 0.0 and inward.length_squared() > 1e-8:
				nq = Quaternion(inward, PI) * nq
	# and the hand model where that puts it
	anchor.global_transform = Transform3D(Basis(nq), p) * inverse_bar


func release(state: VrHands.HandState) -> void:
	if not holds.has(state):
		return
	_restore(state)
	holds.erase(state)
	state.held = false
	state.held_pose = null
