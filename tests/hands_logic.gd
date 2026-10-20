# The hands and board-grab mechanics, tested without a headset: real hand models on stand-in controllers and the real board model.
#   godot --headless --path . -s res://tests/hands_logic.gd
extends SceneTree

var failures := 0
var events: Array = []


# Stands in for an XRController3D.
class FakeController extends Node3D:
	var floats := {}
	var buzzes := []

	func get_float(action: String) -> float:
		return floats.get(action, 0.0)

	func get_has_tracking_data() -> bool:
		return true

	func trigger_haptic_pulse(_action: String, _frequency: float, amplitude: float, duration: float, _delay: float) -> void:
		buzzes.append([amplitude, duration])


func check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	test_skinning()
	await test_grab_and_place()
	await test_board_off()
	test_flat_screen_board_off()
	test_judge_catch()
	print("\n%s" % ("all hand checks pass" if failures == 0 else "%d checks FAILED" % failures))
	quit(0 if failures == 0 else 1)


# The CPU skinning the grip solver relies on: at the rest pose every skinned vertex is where the mesh says it is.
func test_skinning() -> void:
	print("hand skinning (the grip solver's maths)")
	for handedness in ["left", "right"]:
		var hand := HandModel.create(handedness)
		var holder := Node3D.new()
		root.add_child(holder)
		holder.add_child(hand.root)   # the skeleton only updates its bones inside the scene tree
		hand.prepare_skinning()
		hand.skeleton.reset_bone_poses()
		var m := hand.skin_matrices()
		var worst := 0.0
		for i in hand.verts.size():
			worst = maxf(worst, hand.skinned_vertex(i, m).distance_to(hand.verts[i]))
		check(worst < 1e-4, "%s hand: rest pose reproduces the mesh (worst %s m over %d vertices)" % [handedness, str(snappedf(worst, 1e-7)), hand.verts.size()])
		hand.set_pose("Fist", 1.0)
		m = hand.skin_matrices()
		var moved := 0.0
		for i in hand.verts.size():
			moved = maxf(moved, hand.skinned_vertex(i, m).distance_to(hand.verts[i]))
		check(moved > 0.03, "%s hand: a fist actually moves the skin (up to %.1f cm)" % [handedness, moved * 100.0])
		holder.queue_free()


class Rig:
	var holder: Node3D
	var board: Node3D
	var left: FakeController
	var right: FakeController
	var hands: VrHands
	var grab: BoardGrab
	var sim: Skater
	var camera: Camera3D


func make_rig(vr: bool) -> Rig:
	var r := Rig.new()
	r.holder = Node3D.new()
	root.add_child(r.holder)
	r.board = Node3D.new()
	r.holder.add_child(r.board)
	r.board.add_child((load("res://assets/board/skateboard.glb") as PackedScene).instantiate())
	r.board.global_position = Vector3(0, 1.5, 0)
	r.camera = Camera3D.new()
	r.holder.add_child(r.camera)
	var controllers := {}
	if vr:
		r.left = FakeController.new()
		r.right = FakeController.new()
		r.holder.add_child(r.left)
		r.holder.add_child(r.right)
		controllers = {"left": r.left, "right": r.right}
	r.hands = VrHands.new(controllers)
	r.grab = BoardGrab.new(r.hands, r.board, r.camera, null)
	r.grab.event.connect(func(type: String, data: Dictionary): events.append([type, data]))
	r.sim = Skater.new(SkateWorld.new(r.holder.get_world_3d().direct_space_state))
	r.sim.mode = Skater.Mode.AIR
	r.sim.pos = r.board.global_position
	return r


func frame(r: Rig, dt: float = 0.014, air: bool = true) -> void:
	r.grab.update(dt, air)
	r.grab.hold_board(r.sim, dt)
	r.hands.update(dt)
	r.grab.place()


func event_names() -> Array:
	return events.map(func(e): return e[0])


func test_grab_and_place() -> void:
	print("grabbing the board")
	var r := make_rig(true)
	check(r.hands.states.size() == 2, "a hand on each controller")
	for s in r.hands.states:
		check(s.paths.size() == 5, "%s hand has its solved grip (five finger paths)" % s.handedness)

	# the right hand reaches for the nose
	r.right.position = Vector3(0.05, 1.75, -0.5)
	r.right.floats["grip"] = 1.0
	events.clear()
	frame(r)
	check(event_names().has("grabStart") and r.grab.holding(), "squeezing near the nose starts a grab")
	check(events[0][1].name == "Nose grab" and events[0][1].part == "nose", "...and it is the nose grab")
	var state: VrHands.HandState = r.hands.states[1]
	for i in 40:
		frame(r)
	var lifted := r.board.global_position.y - 1.5
	check(lifted > 0.02 and lifted <= BoardGrab.GRAB.maxLift + 1e-4, "the board comes up to the hand (%.1f cm, never more than %.0f cm)" % [lifted * 100.0, BoardGrab.GRAB.maxLift * 100.0])
	var marker: Node3D = r.grab.grabs[state].marker
	var plate_origin := state.model.socket_global() * state.bar_offset
	check(plate_origin.distance_to(marker.global_position) < 1e-3, "the plate in the hand sits on the board's edge (%.2f mm off)" % (plate_origin.distance_to(marker.global_position) * 1000.0))
	# the plate runs out of the palm; for a nose grab it should run along the board, inward (+z in board space)
	var along_edge := marker.global_transform.basis * Vector3(1, 0, 0)
	var plate_dir := state.model.socket_global().basis * state.plate_out
	plate_dir -= along_edge * plate_dir.dot(along_edge)
	var inward := r.board.global_transform.basis * Vector3(0, 0, 1)
	check(plate_dir.normalized().dot(inward) > 0.99, "the hand is turned so the board runs off inward from the edge (dot %.4f)" % plate_dir.normalized().dot(inward))
	var wrist := state.anchor.global_position
	check((wrist - marker.global_position).dot(r.board.global_transform.basis * Vector3.UP) > 0.0, "the wrist is on the top side of the board")
	# fingers have closed to the solved pose
	var index_joint: VrHands.Joint = state.joints["index"][0]
	var path: Array = state.paths["index"]
	var last: Array = path[path.size() - 1]
	var expected := Quaternion(index_joint.open).slerp(index_joint.grip, minf(last[0], 0.65) / 0.65) if last[0] <= 0.65 else Quaternion(index_joint.grip).slerp(index_joint.fist, (last[0] - 0.65) / 0.35)
	var got := state.model.skeleton.get_bone_pose_rotation(index_joint.bone)
	check(expected.angle_to(got) < 1e-3, "the fingers end in the solved pose (index base off by %.5f rad)" % expected.angle_to(got))

	# the left hand reaches for the left edge in the middle
	r.left.position = Vector3(-0.3, 1.9, 0.05)
	r.left.floats["grip"] = 1.0
	events.clear()
	for i in 5:
		frame(r)
	check(event_names().has("grabStart") and events[0][1].name == "Melon", "the left hand on the left edge is a Melon (got %s)" % str(events[0][1].name if not events.is_empty() else "nothing"))
	check(r.grab.names().size() == 2, "both hands can hold the board at once")

	# let go
	r.right.floats["grip"] = 0.0
	r.left.floats["grip"] = 0.0
	events.clear()
	for i in 20:
		frame(r)
	check(event_names().has("grabEnd") and not r.grab.holding(), "letting go of the grips ends the grabs")
	check(r.hands.states[0].anchor.transform.is_equal_approx(r.hands.states[0].home), "the hand goes back to where the controller holds it")

	# too far away to reach
	r.right.position = Vector3(0.0, 3.5, 0.0)
	r.right.floats["grip"] = 1.0
	events.clear()
	frame(r)
	frame(r)
	check(not r.grab.holding(), "a hand more than 60 cm from the board grabs nothing")
	r.right.floats["grip"] = 0.0

	# grabs only start in the air
	r.right.position = Vector3(0.05, 1.75, -0.5)
	frame(r, 0.014, false)
	r.right.floats["grip"] = 1.0
	frame(r, 0.014, false)
	check(not r.grab.holding(), "no grab on the ground")
	# and a grab ends when the board comes down
	frame(r, 0.014, true)
	r.right.floats["grip"] = 0.0
	frame(r)
	r.right.floats["grip"] = 1.0
	frame(r)
	check(r.grab.holding(), "(squeezing again in the air does grab)")
	frame(r, 0.014, false)
	check(not r.grab.holding(), "touching down lets go of the grab")
	r.holder.queue_free()


func test_board_off() -> void:
	print("taking the board off and catching it")
	events.clear()
	var r := make_rig(true)
	r.right.position = Vector3(0.05, 1.75, -0.5)
	r.right.floats["grip"] = 1.0
	for i in 30:
		frame(r)
	check(r.grab.toggle_off(r.sim, true) and r.sim.board_off, "squeezing the left trigger while holding the board takes it off your feet")
	check(r.sim.off_trick != null and r.sim.off_trick.name == "Board Off", "...which is a Board Off")
	# the hand carries it away from the feet: a Christ Air
	var start := r.board.global_position
	for i in 30:
		r.right.position += Vector3(0.02, 0.0, 0.0)
		frame(r)
	check(r.board.global_position.distance_to(start) > 0.4, "the board follows the hand (moved %.0f cm)" % (r.board.global_position.distance_to(start) * 100.0))
	check(r.sim.off_trick.name == "Board Off", "held away from your feet on its own is still just a Board Off (%.0f cm)" % (r.sim.off_trick.far * 100.0))
	# arms out in a T, the board in the right hand: a Christ Air
	var head := r.camera.global_position
	var right_was := r.right.global_position
	var left_was := r.left.global_position
	r.right.global_position = head + Vector3(0.75, -0.2, 0.0)
	r.left.global_position = head + Vector3(-0.75, -0.2, 0.0)
	for i in 8:
		frame(r)
	check(r.sim.off_trick.name == "Board Off", "a T for a moment is not enough yet")
	for i in 30:
		frame(r)
	check(r.sim.off_trick.name == "Christ Air", "arms out in a T while holding it is a Christ Air (%.2fs)" % r.sim.off_trick.tpose)
	r.right.global_position = right_was    # (and back, for the rest of the test)
	r.left.global_position = left_was
	frame(r)
	# trying to catch it way off does nothing
	events.clear()
	r.sim.pos = Vector3(0, 0, 0)
	check(not r.grab.toggle_off(r.sim, true) and event_names().has("catchMiss") and r.sim.board_off, "a catch with the board far from your feet is a miss and nothing happens")
	# bring the board home and catch it
	r.sim.pos = r.board.global_position + Vector3(0.05, 0.0, 0.0)
	r.sim.heading = 0.0
	r.board.global_transform = Transform3D(Basis.IDENTITY, r.board.global_position)
	r.right.position = Vector3.ZERO
	events.clear()
	var caught := r.grab.toggle_off(r.sim, true)
	check(caught and not r.sim.board_off, "with the board back at your feet a catch works")
	check(r.grab.settle != null, "...and swings the last few degrees into line")

	# drop it: let go of the grip with the board off
	r.grab.release_all()
	r.right.floats["grip"] = 0.0
	frame(r)
	r.right.position = Vector3(0.05, 1.75, -0.5)
	r.right.floats["grip"] = 1.0   # a fresh squeeze
	for i in 5:
		frame(r)
	events.clear()
	check(r.grab.holding() and r.grab.toggle_off(r.sim, true), "(take it off again)")
	r.right.floats["grip"] = 0.0
	frame(r)
	check(event_names().has("dropBoard") and r.grab.off_state().get("dropped", false), "letting go of the grip with it off drops it")
	var y0 := r.board.global_position.y
	for i in 20:
		frame(r)
	check(r.board.global_position.y < y0, "a dropped board falls")
	check(not r.grab.toggle_off(r.sim, true), "...and cannot be caught")
	r.sim.mode = Skater.Mode.GROUND
	frame(r, 0.014, false)
	check(r.grab.off == null, "landing without it ends the board-off (the sim bails you)")
	r.holder.queue_free()


func test_flat_screen_board_off() -> void:
	print("board off on a flat screen (no hands)")
	events.clear()
	var r := make_rig(false)
	check(r.hands.states.is_empty(), "no hands without controllers")
	r.camera.global_position = Vector3(0, 1.65, 0)
	check(not r.grab.toggle_off(r.sim, true), "in the headset you have to be holding the board")
	check(r.grab.toggle_off(r.sim, false) and r.sim.board_off, "on a flat screen the detach key takes it off")
	frame(r)
	var offset := r.camera.global_transform.affine_inverse() * r.board.global_position
	check(offset.x > 0.5 and offset.y < -0.5, "...and holds it out to your right and below (%s)" % str(offset))
	r.sim.pos = r.board.global_position
	check(r.grab.toggle_off(r.sim, false) and not r.sim.board_off, "pressing again brings it back (always clean on a flat screen)")
	r.holder.queue_free()


func test_judge_catch() -> void:
	print("judging a catch")
	var feet_q := Quaternion.IDENTITY
	var v := BoardOff.judge_catch(Vector3(0, 0.1, 0), Quaternion.IDENTITY, Vector3.ZERO, feet_q)
	check(v.quality == "clean" and not v.reversed, "lined up and close: clean")
	v = BoardOff.judge_catch(Vector3(0, 0.4, 0), Quaternion(Vector3.UP, 0.7), Vector3.ZERO, feet_q)
	check(v.quality == "sketchy", "40 degrees off and 40 cm away: sketchy")
	v = BoardOff.judge_catch(Vector3(0, 0.9, 0), Quaternion.IDENTITY, Vector3.ZERO, feet_q)
	check(v.quality == "miss", "90 cm away: a miss")
	v = BoardOff.judge_catch(Vector3(0, 0.1, 0), Quaternion(Vector3.UP, PI), Vector3.ZERO, feet_q)
	check(v.quality == "clean" and v.reversed, "nose for tail is fine, and ridden the other way round")
	v = BoardOff.judge_catch(Vector3(0, 0.1, 0), Quaternion(Vector3.FORWARD, PI), Vector3.ZERO, feet_q)
	check(v.quality == "miss", "upside down: a miss")
	print("the T pose of a Christ Air")
	var head := Vector3(0, 1.7, 0)
	check(BoardOff.is_tpose(head, Vector3(-0.75, 1.5, 0), Vector3(0.75, 1.5, 0)), "arms straight out either side at shoulder height: a T")
	check(BoardOff.is_tpose(head, Vector3(-0.6, 1.4, 0.1), Vector3(0.7, 1.6, -0.1)), "roughly a T is enough")
	check(not BoardOff.is_tpose(head, Vector3(-0.3, 1.5, 0), Vector3(0.3, 1.5, 0)), "hands close together is not")
	check(not BoardOff.is_tpose(head, Vector3(-0.5, 1.5, -0.7), Vector3(0.5, 1.5, -0.7)), "both arms out in front is not")
	check(not BoardOff.is_tpose(head, Vector3(0.4, 1.5, 0), Vector3(1.4, 1.5, 0)), "both arms out to the same side is not")
	check(not BoardOff.is_tpose(head, Vector3(-0.75, 0.6, 0), Vector3(0.75, 0.6, 0)), "arms down by the knees is not")
	check(not BoardOff.is_tpose(head, Vector3(-0.75, 2.4, 0), Vector3(0.75, 2.4, 0)), "arms way over the head is not")
	check(not BoardOff.is_tpose(head, Vector3(-0.75, 1.2, 0), Vector3(0.75, 1.75, 0)), "one hand much higher than the other is not")
	check(BoardOff.is_tpose(Vector3(3, 1.7, -2), Vector3(2.25, 1.5, -2), Vector3(3.75, 1.5, -2)), "wherever you are standing")
