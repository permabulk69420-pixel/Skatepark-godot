# Real hand/board models with stand-in controllers: on-foot pickup must align
# the deck with the tracked wrist, including pickups of an upside-down board.
extends SceneTree

class Controller extends Node3D:
	var grip := 0.0
	var tracked := true
	func get_float(action: String) -> float:
		return grip if action == "grip" else 0.0
	func get_has_tracking_data() -> bool:
		return tracked

var failures := 0
var checks := 0
var stage: Node3D
var board: Node3D
var hands: VrHands
var carry: BoardCarry
var grab: BoardGrab
var releases: Array[Dictionary] = []

func _init() -> void:
	run.call_deferred()

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ", what)

func step(dt: float, pose: Transform3D) -> Transform3D:
	hands.update(dt)
	var result := carry.update(dt, pose, func(_state): return true)
	board.global_transform = result
	carry.place()
	return result

func prepare(state: VrHands.HandState, part: String, orientation: Basis, wrist: Basis) -> Transform3D:
	for other in hands.states:
		other.controller.grip = 0.0
		other.controller.global_position = Vector3(10, 10, 10)
	step(0.02, board.global_transform)
	var pose := Transform3D(orientation, Vector3(2, 1, -3))
	board.global_transform = pose
	var point: Vector3
	match part:
		"nose": point = grab.shape.tip(-1.0, 0.0)
		"tail": point = grab.shape.tip(1.0, 0.0)
		"left": point = grab.shape.side(-1.0, 0.0)
		_: point = grab.shape.side(1.0, 0.0)
	state.controller.global_basis = wrist
	state.anchor.transform = state.home
	state.controller.global_position += pose * (point + Vector3.UP * 0.08) - state.model.socket_global().origin
	return pose

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	stage.transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(1, 0.4, -2))
	var left := Controller.new()
	var right := Controller.new()
	stage.add_child(left)
	stage.add_child(right)
	hands = VrHands.new({"left": left, "right": right})
	board = Node3D.new()
	stage.add_child(board)
	board.add_child((load("res://assets/board/skateboard.glb") as PackedScene).instantiate())
	grab = BoardGrab.new(hands, board)
	grab.ensure_shape()
	carry = BoardCarry.new(hands, grab, board)
	carry.released.connect(func(pose: Transform3D, velocity: Vector3, spin: Vector3):
		releases.append({"pose": pose, "velocity": velocity, "spin": spin}))
	var orientations := [Basis.IDENTITY, Basis(Vector3.FORWARD, PI),
		Basis(Vector3.FORWARD, PI / 2.0), Basis.from_euler(Vector3(0.4, 0.8, -0.3))]
	for state in hands.states:
		for part in ["nose", "tail", "left", "right"]:
			for i in orientations.size():
				var label := "%s %s pose %d" % [state.handedness, part, i]
				var pose := prepare(state, part, orientations[i], Basis.from_euler(Vector3(0.3 * i, -0.4, 0.7 * i)))
				state.controller.grip = 1.0
				hands.update(0.01)
				var start := carry.update(0.0, pose, func(_s): return true)
				check(carry.holding() and carry.held.part == part, label + ": picks the nearest edge")
				check(start.is_equal_approx(pose), label + ": board starts easing from its resting pose")
				check(state.anchor.transform.is_equal_approx(state.home), label + ": pickup leaves wrist tracked")
				carry.place()
				check(state.anchor.transform.is_equal_approx(state.home), label + ": first placement does not flip the hand")
				pose = step(BoardCarry.EASE / 2.0, start)
				check(state.anchor.transform.is_equal_approx(state.home), label + ": wrist stays tracked during easing")
				pose = step(BoardCarry.EASE, pose)
				check(state.anchor.transform.is_equal_approx(state.home), label + ": settled hand stays tracked")
				var marker: Node3D = carry.held.marker
				var plate := state.model.socket_global()
				check((plate * state.bar_offset).distance_to(marker.global_position) < 0.0001, label + ": board edge meets the grip")
				var handle: Dictionary = carry.hold.holds[state].handle
				var edge: Vector3 = pose.basis * handle.axis
				check(absf(edge.normalized().dot(plate.basis.y.normalized())) > 0.999, label + ": deck edge follows the fingers")
				var inward: Vector3 = pose.basis * handle.inward
				var palm: Vector3 = plate.basis * state.plate_out
				check(inward.normalized().dot(palm.normalized()) > 0.999, label + ": deck runs into the grip")
				check((state.anchor.global_position - marker.global_position).dot(pose.basis.y) >= -0.0001, label + ": wrist remains on deck-top side")
				var controller_before := state.controller.global_transform
				state.controller.global_position += Vector3(0.04, 0.01, -0.02)
				state.controller.global_basis = Basis(Vector3.UP, 0.3) * state.controller.global_basis
				var expected := state.controller.global_transform * controller_before.affine_inverse() * pose
				pose = step(0.02, pose)
				check(pose.is_equal_approx(expected), label + ": board follows wrist movement and rotation rigidly")
				check(state.anchor.transform.is_equal_approx(state.home), label + ": turning wrist never applies a second hand fit")
				state.controller.grip = 0.0
				var release_count := releases.size()
				step(0.02, pose)
				check(not carry.holding() and not state.held and state.held_pose == null, label + ": letting go releases the hand")
				check(releases.size() == release_count + 1 and releases[-1].pose.is_equal_approx(pose), label + ": drop keeps the held board pose")
				check(releases[-1].velocity.length() > 0.1 and releases[-1].velocity.length() <= BoardCarry.MAX_THROW + 0.001,
					label + ": throw velocity remains available and bounded")
				check(releases[-1].spin.length() > 0.1 and releases[-1].spin.length() <= BoardCarry.MAX_SPIN + 0.001,
					label + ": wrist spin remains available and bounded")
	var state := hands.states[0]
	var pose := prepare(state, "left", Basis.IDENTITY, Basis.IDENTITY)
	state.controller.grip = 1.0
	state.controller.tracked = false
	step(0.02, pose)
	check(not carry.holding(), "Untracked hand cannot pick up a board")
	state.controller.grip = 0.0
	state.controller.tracked = true
	step(0.02, pose)
	state.controller.grip = 1.0
	state.held = true
	step(0.02, pose)
	check(not carry.holding(), "Hand holding another object cannot pick up the board")
	state.held = false
	state.controller.grip = 0.0
	step(0.02, pose)
	state.controller.grip = 1.0
	pose = step(BoardCarry.EASE, pose)
	check(carry.holding(), "Fresh squeeze picks up after the hand becomes available")
	var count := releases.size()
	carry.drop_quietly()
	check(not carry.holding() and not state.held and releases.size() == count,
		"Stepping onto the board clears carrying without throwing it")
	check(state.anchor.transform.is_equal_approx(state.home), "Quiet release keeps the wrist tracked")
	print("CARRY_VALIDATION checks=%d failures=%d" % [checks, failures])
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)
