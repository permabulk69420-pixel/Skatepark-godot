# The headset layer, tested without a headset: hand balance, where the rig puts your head, the controller
# button mapping (with stand-in controllers) and the buzz routing.
#   godot --headless --path . -s res://tests/vr_logic.gd
extends SceneTree

var failures := 0


# Stands in for an XRController3D.
class FakeController extends Node3D:
	var buttons := {}
	var stick := Vector2.ZERO
	var buzzes := []

	func is_button_pressed(action: String) -> bool:
		return buttons.get(action, false)

	func get_vector2(_action: String) -> Vector2:
		return stick

	func trigger_haptic_pulse(action: String, frequency: float, amplitude: float, duration: float, delay: float) -> void:
		buzzes.append([action, frequency, amplitude, duration, delay])


func check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func _init() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	test_hand_balance()
	test_controller_mapping()
	test_trick_controls()
	test_rig_geometry()
	test_haptics()
	print("\n%s" % ("all headset-logic checks pass" if failures == 0 else "%d checks FAILED" % failures))
	quit(0 if failures == 0 else 1)


func test_hand_balance() -> void:
	print("hand balance")
	var hb := HandBalance.new()
	var left := Vector3(-0.3, 1.0, 0.0)
	var right := Vector3(0.3, 1.6, 0.0)   # the right hand way up when the grind starts
	for i in 72:
		hb.update(1.0 / 72.0, left, right, true)
	check(absf(hb.lean) < 0.01, "hands wherever they are when a balance starts are the neutral: no push (%.3f)" % hb.lean)
	right.y = 2.2
	for i in 72:
		hb.update(1.0 / 72.0, left, right, true)
	check(hb.lean > 0.5, "raising the right hand from there pushes right (%.3f)" % hb.lean)
	for i in 72:
		hb.update(1.0 / 72.0, left, right, false)
	right.y = 1.0
	for i in 72:
		hb.update(1.0 / 72.0, left, right, true)
	check(absf(hb.lean) < 0.01, "and the next balance takes its own neutral (%.3f)" % hb.lean)


func test_controller_mapping() -> void:
	print("controller mapping")
	var left := FakeController.new()
	var right := FakeController.new()
	var input := SkateInput.new()
	input.vr_left = left
	input.vr_right = right
	var c := input.poll(0.014)
	check(c.steer == 0.0 and c.drive == 0.0 and not c.jump and not c.grind and not c.flip, "nothing pressed: nothing happens")
	check(c.lean == 0.0, "balance comes from the hands, not the stick")

	left.stick = Vector2(0.6, 0.9)   # right and up
	c = input.poll(0.014)
	check(c.steer > 0.4 and c.drive > 0.7, "stick right+up steers right and pushes")
	check(c.trick_stick.x > 0.5 and c.trick_stick.y < -0.8, "trick stick has up = -y")
	left.stick = Vector2(0.0, -1.0)
	c = input.poll(0.014)
	check(c.drive < -0.9 and c.trick_stick.y > 0.9, "stick down brakes, and is 'down' for tricks")
	left.stick = Vector2.ZERO

	right.buttons["ax_button"] = true
	check(input.poll(0.014).jump, "right A is crouch/ollie")
	right.buttons["ax_button"] = false
	right.buttons["trigger_click"] = true
	check(input.poll(0.014).grind, "right trigger grinds")
	right.buttons["trigger_click"] = false
	right.buttons["by_button"] = true
	check(input.poll(0.014).flip, "right B is the flip button")
	right.buttons["by_button"] = false
	left.buttons["ax_button"] = true
	check(not input.poll(0.014).flip and not input.poll(0.014).jump, "left X is not a trick or an ollie")
	left.buttons["ax_button"] = false

	left.buttons["by_button"] = true
	check(input.poll(0.014).toggle_stance, "left Y switches stance once...")
	check(not input.poll(0.014).toggle_stance, "...and not again while held")
	left.buttons["by_button"] = false

	left.buttons["grip_click"] = true
	right.buttons["grip_click"] = true
	var recentred := false
	for i in 60:
		recentred = input.poll(0.014).recenter or recentred
	check(recentred, "both grips held re-centres")
	left.buttons["grip_click"] = false
	right.buttons["grip_click"] = false
	input.poll(0.014)
	input.block_recenter = true
	left.buttons["grip_click"] = true
	right.buttons["grip_click"] = true
	recentred = false
	for i in 60:
		recentred = input.poll(0.014).recenter or recentred
	check(not recentred, "...but not while blocked (in the air)")
	left.free()
	right.free()



func test_trick_controls() -> void:
	print("trick stick sectors and timing")
	var dt := 1.0 / 90.0
	# The two horizontal sectors are mirrors: 45 degrees centred on left/right.
	for y in [-0.35, 0.0, 0.35]:
		check(TrickControls.stick_direction(1.0, y) == "right", "heelflip catches straight right and both +/- 19 degree offsets (y=%.2f)" % y)
		check(TrickControls.stick_direction(-1.0, y) == "left", "kickflip mirrors the heelflip sector (y=%.2f)" % y)
	check(TrickControls.stick_direction(1.0, -0.5) == "up-right", "up-right remains its own unassigned sector")
	check(TrickControls.stick_direction(1.0, 0.5) == "down-right", "down-right remains varial-heelflip territory")

	var tc := TrickControls.new()
	tc.sample(false, 1.0, 0.0, dt, true, true)
	var trick = tc.sample(true, 1.0, 0.0, dt, true, true)
	check(trick != null and trick.name == "Heelflip", "stick held straight right BEFORE B immediately starts a heelflip")

	# B first: crossing an intermediate diagonal must not select a varial or eat the press.
	tc = TrickControls.new()
	tc.sample(true, 0.0, 0.0, dt, true, true)
	check(tc.sample(true, 0.5, 0.6, dt, true, true) == null, "passing through down-right does not immediately steal B")
	trick = null
	for i in 8:
		var attempt = tc.sample(true, 1.0, 0.0, dt, true, true)
		if attempt != null:
			trick = attempt
	check(trick != null and trick.name == "Heelflip", "B then a rightward sweep ends in a heelflip, not a varial")

	tc = TrickControls.new()
	tc.sample(true, 0.0, 0.0, dt, true, true)
	for i in 9:
		check(tc.sample(true, 0.8, -0.5, dt, true, true) == null, "unassigned up-right does not consume B")
	trick = null
	for i in 8:
		var attempt = tc.sample(true, 1.0, -0.1, dt, true, true)
		if attempt != null:
			trick = attempt
	check(trick != null and trick.name == "Heelflip", "moving from up-right back to right still triggers a heelflip")

	# Partial deflection should also work if the stick stays in its sector.
	tc = TrickControls.new()
	tc.sample(true, 0.0, 0.0, dt, true, true)
	trick = null
	for i in 12:
		var attempt = tc.sample(true, 0.55, -0.10, dt, true, true)
		if attempt != null:
			trick = attempt
	check(trick != null and trick.name == "Heelflip", "a steady partial right deflection works after a short settle")

	# Quick side flick then B is still supported (including multi-flips).
	tc = TrickControls.new()
	for i in 3:
		tc.sample(false, 1.0, 0.0, dt, true, true)
	tc.sample(false, 0.0, 0.0, dt, true, true)
	trick = tc.sample(true, 0.0, 0.0, dt, true, true)
	check(trick != null and trick.name == "Heelflip", "a recent released flick then B still starts the trick")

	tc = TrickControls.new()
	for i in 30:
		tc.sample(false, -1.0, 0.0, dt, true, true)
	tc.sample(false, 0.0, 0.0, dt, true, true)
	check(tc.sample(true, 0.0, 0.0, dt, true, true) == null, "old steering input cannot steal the next B press")
	trick = null
	for i in 8:
		var attempt = tc.sample(true, 1.0, 0.0, dt, true, true)
		if attempt != null:
			trick = attempt
	check(trick != null and trick.name == "Heelflip", "B after releasing a long-held steer still accepts the new rightward flick")

	tc = TrickControls.new()
	for i in 3:
		tc.sample(false, -1.0, 0.0, dt, true, true)
	tc.sample(false, 0.0, 0.0, dt, true, true)
	trick = tc.sample(true, 0.0, 0.0, dt, true, true)
	check(trick != null and trick.name == "Kickflip", "the opposite side still triggers kickflips")

func test_rig_geometry() -> void:
	print("headset rig")
	var holder := Node3D.new()
	root.add_child(holder)
	var rig := Node3D.new()
	var camera := Camera3D.new()
	holder.add_child(rig)
	rig.add_child(camera)
	var world := SkateWorld.new(holder.get_world_3d().direct_space_state)
	var sim := Skater.new(world)
	sim.pos = Vector3(3.0, 0.5, -2.0)
	sim.heading = 0.7
	var fade := ColorRect.new()
	var pr := PlayerRig.new(rig, camera, sim, fade, true)

	# the player stands 0.4 m off-centre in their play space, looking 30 degrees off the headset's own forward, 1.7 m tall
	camera.position = Vector3(0.4, 1.7, -0.25)
	camera.rotation = Vector3(0.0, 0.5, 0.0)
	for i in 40:
		pr.update(0.014)
	check(pr.calibrated, "calibrates once the head is up and tracking has settled")
	check(is_equal_approx(pr.yaw_cal, 0.5) and pr.anchor.is_equal_approx(Vector2(0.4, -0.25)), "remembers where the head was and which way it faced")
	var head := camera.global_position
	check(Vector2(head.x - sim.pos.x, head.z - sim.pos.z).length() < 1e-4, "head is over the board (off by %.6f m)" % Vector2(head.x - sim.pos.x, head.z - sim.pos.z).length())
	check(absf(head.y - (sim.pos.y + 1.7 + Config.Board.deckTop)) < 1e-4, "standing height above the deck")
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var stance := Skater.heading_vec(sim.heading + sim.face_offset)
	check(forward.distance_to(stance) < 1e-4, "gaze is side-on to travel, the way a regular stance faces (error %.6f)" % forward.distance_to(stance))

	# a shove-it turns the rider's stance with the board; the gaze should follow it, and the head stay over the board
	sim.face_offset = -sim.face_offset
	sim.heading += PI
	pr.update(0.014)
	head = camera.global_position
	forward = -camera.global_transform.basis.z
	forward.y = 0.0
	check(forward.normalized().distance_to(Skater.heading_vec(sim.heading + sim.face_offset)) < 1e-4, "gaze follows the stance after a shove-it")
	check(Vector2(head.x - sim.pos.x, head.z - sim.pos.z).length() < 1e-4, "head still over the board")

	pr.request_calibration()
	check(not pr.calibrated, "re-centre asks for a new calibration")
	holder.queue_free()


func test_haptics() -> void:
	print("buzzes")
	var left := FakeController.new()
	var right := FakeController.new()
	var h := Haptics.new(left, right)
	h.event("bail", {})
	check(left.buzzes.size() == 1 and right.buzzes.size() == 1, "a bail buzzes both hands")
	check(is_equal_approx(left.buzzes[0][2], 1.0) and is_equal_approx(left.buzzes[0][3], 0.24), "...at full strength for 240 ms")
	h.event("land", {"impact": 0.3})
	check(left.buzzes.size() == 1, "a soft landing is not felt")
	h.event("land", {"impact": 4.0})
	check(left.buzzes.size() == 2, "a proper landing is")
	h.pulse(0.5, 30, "left")
	check(left.buzzes.size() == 3 and right.buzzes.size() == 2, "one hand can be buzzed alone")
	left.free()
	right.free()
