# The house: walking on foot (floors, steps, the ramp down the back, walls, windows, furniture), stepping on and off the board, the
# half pipe, and the TV and its remote. Runs the real game scene on a flat screen and drives its parts directly.
#   godot --headless --path . -s res://tests/hub_logic.gd
extends SceneTree

class FakeController extends Node3D:
	var floats := {}
	func get_float(action: String) -> float:
		return floats.get(action, 0.0)
	func get_has_tracking_data() -> bool:
		return true

var failures := 0
var main: Node


func _init() -> void:
	run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


# Walks the player `seconds` with the stick held as given.
func walk(move: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		main.foot.update(0.05, move, 0.0)
		t += 0.05


# Stands the player at a spot given in the brief's coordinates (x east, y north) on the floor, facing a sim heading.
func stand(x: float, y: float, z: float, yaw: float) -> void:
	main.foot.place(Vector3(x, z, -y), yaw)
	main.foot.update(0.05, Vector2.ZERO, 0.0)


func spot() -> Vector3:   # the player's position in the brief's coordinates
	var b: Vector3 = main.foot.body()
	return Vector3(b.x, -b.z, b.y)


func run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	check(main.hub != null and main.on_foot, "the house opens with you on foot")
	check(main.level.markers_with("board_slot").size() == 12, "twelve board slots on the shop wall")
	check(main.hub.lamps.size() == 6, "six lamps")
	check(main.hub.tv != null, "a TV with a remote")
	check(main.level.root.find_child("HalfPipe", true, false) != null and main.level.grind_nodes.size() == 2, "the half pipe is on the slab, coping on both lips")

	# the start: inside the front door, on the raised floor
	main.foot.update(0.05, Vector2.ZERO, 0.0)
	var s := spot()
	check(absf(s.z - 0.30) < 0.02 and absf(s.y + 3.0) < 0.05, "starts inside the front door on the raised floor (%s)" % s)

	# straight on through the house, out the back opening and down the ramp
	walk(Vector2(0, 1), 12.0)
	s = spot()
	check(s.y > 8.0, "walks the length of the room and out onto the veranda (y %.1f)" % s.y)
	walk(Vector2(0, 1), 6.0)
	s = spot()
	check(s.y > 11.0 and absf(s.z) < 0.05, "down the ramp to the yard (y %.1f, height %.2f)" % [s.y, s.z])

	# walls stop you: the west wall, a window, the coffee table, the counter
	stand(0, -3.0, 0.30, PI / 2.0)
	walk(Vector2(0, 1), 6.0)
	s = spot()
	check(s.x > -7.0 and s.x < -6.5, "stops at the west wall (x %.2f)" % s.x)
	stand(-4.5, -3.0, 0.30, PI)
	walk(Vector2(0, 1), 3.0)
	s = spot()
	check(s.y > -4.6 and s.y < -4.0, "a window is a wall (y %.2f)" % s.y)
	stand(-6.0, 0.0, 0.30, -PI / 2.0)
	walk(Vector2(0, 1), 3.0)
	s = spot()
	check(s.x < -4.4, "the coffee table is in the way (x %.2f)" % s.x)
	stand(0.5, 0.0, 0.30, -PI / 2.0)
	walk(Vector2(0, 1), 3.0)
	s = spot()
	check(s.x > 1.5 and s.x < 2.5, "the counter is in the way (x %.2f)" % s.x)

	# out of the front door and down the two steps
	stand(0, -3.0, 0.30, PI)
	walk(Vector2(0, 1), 8.0)
	s = spot()
	check(s.y < -8.0 and absf(s.z) < 0.05, "out the front door and down the steps (y %.1f, height %.2f)" % [s.y, s.z])

	# the board: step on, it settles on the floor, step off again
	stand(0, -3.0, 0.30, 0.0)
	main._step_on()
	check(not main.on_foot, "stepping on puts you on the board")
	var cmd := Skater.Command.new()
	for i in 90:
		main.sim.update(cmd, 1.0 / 72.0)
	check(main.sim.mode == Skater.Mode.GROUND and absf(main.sim.pos.y - 0.30) < 0.05, "the board stands on the house floor")
	main._stand_up(main.sim.pos, main.sim.heading)
	check(main.on_foot and not main.board_view.root.visible, "stepping off puts the board away")

	# the half pipe: roll along the slab into the east transition and up it
	var where := Skater.SpawnPoint.new()
	where.pos = Vector3(1.0, 0.0, -19.5)
	where.heading = -PI / 2.0
	main.sim.respawn(where)
	var top := 0.0
	var lowest := 0.0
	cmd.drive = 1.0
	for i in 72 * 8:
		main.sim.update(cmd, 1.0 / 72.0)
		top = maxf(top, main.sim.pos.y)
		lowest = minf(lowest, main.sim.pos.y)
	check(top > 0.3 and lowest > -0.05, "rolls up the half pipe's transition and does not fall through (up %.2f, lowest %.2f)" % [top, lowest])

	# ollies on the transition: the deck must have nothing standing inside the ramp behind the curve for the front wheels to slam into
	var slams := []
	var on_bail := func(type: String, data: Dictionary):
		if type == "bail":
			slams.append(data.reason)
	main.sim.event.connect(on_bail)
	for pop_frame in range(100, 200):
		where.pos = Vector3(0.0, 0.05, -19.5)
		main.sim.respawn(where)
		for i in 72 * 4:
			cmd.drive = 1.0 if i < 144 else 0.0
			cmd.jump = i >= pop_frame - 18 and i < pop_frame
			main.sim.update(cmd, 1.0 / 72.0)
	cmd.jump = false
	main.sim.event.disconnect(on_bail)
	check(slams.is_empty(), "ollies up the half pipe's transition land (bails: %s)" % [slams])

	# the TV: pick up the remote, change channel, play
	var tv = main.hub.tv
	var picked: Array = []
	tv.chosen.disconnect(main._go_to)   # (it would reload the scene)
	tv.chosen.connect(func(id: String): picked.append(id))
	var first: String = tv.level_id()
	var near: Vector3 = tv.remote.global_position
	var pointer := {"id": "key", "node": main.camera, "pos": near, "squeeze": false, "stick_x": 0.0, "trigger": false}
	tv.update([pointer])
	pointer.squeeze = true
	tv.update([pointer])
	check(tv.holder == "key", "squeezing next to the remote picks it up")
	pointer.stick_x = 1.0
	tv.update([pointer])
	check(tv.level_id() == Levels.next_channel(first), "stick right: the next level")
	tv.update([pointer])
	check(tv.level_id() == Levels.next_channel(first), "holding the stick over does not skip on")
	pointer.stick_x = 0.0
	tv.update([pointer])
	pointer.stick_x = -1.0
	tv.update([pointer])
	check(tv.level_id() == first, "stick left: back")
	pointer.stick_x = 0.0
	pointer.trigger = true
	tv.update([pointer])
	check(picked == [first], "trigger plays it")
	pointer.squeeze = false
	tv.update([pointer])
	check(tv.holder == "" and tv.remote.get_parent() == tv.spot, "letting go puts the remote back on the table")
	pointer.pos = Vector3(0, 0, 30)
	pointer.squeeze = true
	tv.update([pointer])
	check(tv.holder == "", "a remote out of reach stays put")

	# in a hand (the headset): the fingers close on it and it goes where the hand goes
	var fake := FakeController.new()
	main.add_child(fake)
	var vr_hands := VrHands.new({"right": fake})
	var hand: VrHands.HandState = vr_hands.states[0]
	fake.global_position = tv.remote.global_position
	var vr_pointer := {"id": "right", "node": fake, "state": hand, "pos": fake.global_position, "squeeze": true, "stick_x": 0.0, "trigger": false}
	fake.floats["grip"] = 1.0
	tv.update([vr_pointer])
	check(tv.holder == "right" and hand.held, "a hand picks the remote up and closes on it")
	fake.global_position += Vector3(0.0, 0.3, -0.2)
	vr_hands.update(0.1)
	tv.update([vr_pointer])
	var socket: Vector3 = hand.model.socket_global().origin
	check(tv.remote.global_position.distance_to(socket) < 0.1, "the remote goes where the hand goes")
	vr_pointer.squeeze = false
	tv.update([vr_pointer])
	check(tv.holder == "" and not hand.held and tv.remote.get_parent() == tv.spot, "letting go opens the hand and puts the remote down")

	# where levels send you
	Levels.go_to("megaramp")
	check(Levels.take_next() == "megaramp" and Levels.take_next() == Levels.HUB, "go_to is used once, then it is home again")

	print("\n%s" % ("all house checks pass" if failures == 0 else "%d failed" % failures))
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
