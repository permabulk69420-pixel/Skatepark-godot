# The dirt bike: the one in the drive, getting on by walking up to it, throttle, gears, the brake, steering, walls, a jump, getting off,
# and in the headset the hands on the grips (the right one twisted back for throttle, the bars turned by the hands). Runs the real game
# scene on a flat screen and drives the bike directly.
#   godot --headless --path . -s res://tests/bike_logic.gd
extends SceneTree

class FakeController extends Node3D:
	var floats := {}
	func get_float(action: String) -> float:
		return floats.get(action, 0.0)
	func get_has_tracking_data() -> bool:
		return true

const DT := 1.0 / 72.0

var failures := 0
var main: Node


func _init() -> void:
	run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func ride(seconds: float, throttle: float, brake := 0.0, steer := 0.0) -> Array:
	var events: Array = []
	var t := 0.0
	while t < seconds:
		var e: String = main.ride.update(DT, brake, 0.0, throttle, steer)
		if e != "":
			events.append(e)
		t += DT
	return events


func put(bike: DirtBike, at: Vector3, yaw: float) -> void:
	bike.pos = at
	bike.yaw = yaw
	bike.speed = 0.0
	bike.vy = 0.0
	bike.air = false
	bike.pitch = 0.0
	bike.steer = 0.0
	bike.gear = 0
	bike.apply()


func run() -> void:
	HubLayout.path = "user://bike_test_layout.cfg"
	HubLayout.clear()
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	main.set_process(false)   # (the test drives it)

	var piece: Node3D = null
	for p in main.build.pieces:
		if BuildPieces.info(p).id == "bike":
			piece = p
	check(piece != null and BuildPieces.info(piece).get("rideable", false), "there is a dirt bike in the drive, and it can be ridden")
	check(piece != null and piece.global_position.distance_to(BuildPieces.DRIVEWAY_BIKE) < 0.01, "it stands in the drive (%s)" % (piece.global_position if piece else Vector3.ZERO))

	# walking up to it gets you on
	var rider: Vector3 = piece.global_transform * DirtBike.RIDER
	main.foot.place(rider + Vector3(2.0, 0.0, 0.0), PI / 2.0)
	main.foot.update(0.05, Vector2.ZERO, 0.0)
	main._walk_to_bike(0.05)
	check(main.ride == null, "standing two metres off it does not")
	var t := 0.0
	while t < 2.0 and main.ride == null:
		main.foot.update(0.05, Vector2(0, 1), 0.0)
		main._walk_to_bike(0.05)
		t += 0.05
	check(main.ride != null and not main.on_foot, "walking up to it gets you on")
	var bike: DirtBike = main.ride.bike
	check(main.camera.global_position.distance_to(bike.rider_point() + Vector3(0, BikeRide.FLAT_EYE, 0)) < 0.05, "and you see from over its pegs")

	# throttle: off down the drive, out of the gate and on to the road, changing up
	var start := bike.pos
	var events := ride(3.0, 1.0)
	check(bike.speed > 8.0 and bike.pos.z > start.z + 10.0, "full throttle pulls it away down the drive (%.1f m/s, %.1f m)" % [bike.speed, bike.pos.z - start.z])
	check(bike.gear >= 1 and "shift" in events, "the box changes up by itself (gear %d)" % (bike.gear + 1))
	check(absf(bike.pos.y - HubRoads.HEIGHT) < 0.02 and not bike.air and absf(bike.pitch) < 0.05, "it stays on the ground, level (%.3f m, pitch %.3f)" % [bike.pos.y, bike.pitch])
	check(bike.rpm > 3000.0 and bike.rpm <= DirtBike.RED_LINE, "the revs follow the back wheel (%d rpm)" % bike.rpm)
	ride(0.6, 0.0, 1.0)
	var braking_from := bike.pos
	events = ride(3.0, 0.0, 1.0)
	check(absf(bike.speed) < 0.1 and bike.pos.distance_to(braking_from) < 10.0, "the brake stops it (%.1f m more)" % bike.pos.distance_to(braking_from))
	check(bike.pos.z > 20.0, "it is out on the road in front of the house (z %.1f)" % bike.pos.z)

	# steering: left on the road
	put(bike, Vector3(30.0, HubRoads.HEIGHT, -HubRoads.MAIN_Y), PI / 2.0)   # (heading west along the road)
	ride(1.5, 0.6)
	var yaw_before := bike.yaw
	ride(1.0, 0.4, 0.0, 1.0)
	check(angle_difference(yaw_before, bike.yaw) > 0.2, "A steers it left (%.2f rad)" % angle_difference(yaw_before, bike.yaw))
	check(bike.lean > 0.05 and bike.lean <= DirtBike.MAX_LEAN + 1e-4, "it leans into the turn, gently (%.1f degrees)" % rad_to_deg(bike.lean))
	var grip_in_ride: Vector3 = bike.ride_transform().affine_inverse() * bike.grip_markers.right.global_position
	var was_lean := bike.lean
	bike.lean = 0.0
	bike.apply()
	var grip_upright: Vector3 = bike.ride_transform().affine_inverse() * bike.grip_markers.right.global_position
	bike.lean = was_lean
	bike.apply()
	check(grip_in_ride.distance_to(grip_upright) < 0.005, "you lean with it: the bars stay just where your hands are (%.3f m)" % grip_in_ride.distance_to(grip_upright))
	main.ride.update(DT, 0.0, 0.0, 0.4, 1.0)
	check(main.rig.global_basis.x.distance_to(bike.node.global_basis.x) < 0.001 and absf(main.rig.global_basis.x.y) > 0.05, "and the view leans with it, as it tilts with the board")
	var fork_ahead: Vector3 = bike.node.global_basis.inverse() * bike.pivot.global_basis.z   # (the model's +Z: the bike's forward)
	check(fork_ahead.x < -0.1, "the front wheel turns left with it (%.3f)" % fork_ahead.x)
	var spin := bike.spin_rear
	ride(0.2, 0.4)
	check(not is_equal_approx(spin, bike.spin_rear), "the wheels turn")

	# a wall: the front fence
	put(bike, Vector3(-3.0, HubRoads.HEIGHT, 21.0), 0.0)   # (heading north, at the fence beside the gate)
	events = ride(4.0, 1.0)
	check("hit" in events and bike.pos.z > 12.5, "it stops at the fence, it does not go through (z %.2f)" % bike.pos.z)

	# a jump: a kicker out on the open ground
	var ramp := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var faces := ConcavePolygonShape3D.new()
	faces.backface_collision = false
	var z0 := 120.0   # (inside the loop: the ramp rises northwards, from z0 to z0 - 4, by 1.2 m)
	var corners := [Vector3(-2, 0, z0), Vector3(-2, 1.2, z0 - 4.0), Vector3(2, 1.2, z0 - 4.0), Vector3(2, 0, z0)]
	faces.set_faces(PackedVector3Array([corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]))
	shape.shape = faces
	ramp.add_child(shape)
	main.add_child(ramp)
	await physics_frame
	await physics_frame
	put(bike, Vector3(0.0, 0.0, z0 + 25.0), 0.0)
	var flew := false
	var peak := 0.0
	var pitched_view := 0.0   # (the most the view was pitched, with the bike, on the ramp)
	var view_off := 0.0
	events = []
	t = 0.0
	while t < 6.0:
		var e: String = main.ride.update(DT, 0.0, 0.0, 1.0 if bike.pos.z > z0 else 0.0, 0.0)
		if e != "":
			events.append(e)
		flew = flew or bike.air
		peak = maxf(peak, bike.pos.y)
		var ride_frame := bike.ride_transform()
		view_off = maxf(view_off, main.rig.global_position.distance_to(ride_frame * (DirtBike.RIDER + Vector3(0, BikeRide.FLAT_EYE, 0))))
		if not bike.air and bike.pitch > 0.1:
			pitched_view = maxf(pitched_view, asin(clampf(-main.rig.global_basis.z.y, -1.0, 1.0)))
		t += DT
	check(flew and peak > 1.4, "off a kicker it flies (up to %.2f m)" % peak)
	check("land" in events and not bike.air and absf(bike.pos.y) < 0.05, "and lands again")
	check(view_off < 0.01, "the view stays on the bike the whole way (%.3f m off at most)" % view_off)
	check(pitched_view > 0.1, "and pitches up the ramp with it (%.1f degrees)" % rad_to_deg(pitched_view))
	ramp.queue_free()

	# getting off
	ride(3.0, 0.0, 1.0)
	var parked := bike.pos
	main._get_off_bike()
	check(main.ride == null and main.on_foot, "Q gets you off")
	main.foot.update(0.05, Vector2.ZERO, 0.0)
	var feet: Vector3 = main.foot.body()
	check(Vector2(feet.x - parked.x, feet.z - parked.z).length() > 0.5, "you stand beside it")
	check(piece.global_position.distance_to(parked) < 0.01, "and it stays where you left it")
	main._walk_to_bike(0.05)
	check(main.ride == null, "standing where you got off does not put you straight back on")

	# the headset: hands on the grips, the right twisted back for throttle, the bars turned by the hands
	check(BikeRide.throttle_for(0.0) == 0.0 and absf(BikeRide.throttle_for(BikeRide.TWIST_FULL) - 1.0) < 1e-6, "no twist: no throttle; a full twist: all of it")
	check(absf(BikeRide.twist_about_bar(Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, 0.5)) - 0.5) < 1e-4, "a twist about the bar is measured")
	check(absf(BikeRide.twist_about_bar(Quaternion.IDENTITY, Quaternion(Vector3.UP, 0.4))) < 1e-4, "turning the bars is not a twist")
	check(BikeRide.bar_angle_of(Vector3(0.7, 0.0, -0.15)) > 0.1, "the right hand forward of the left turns the bars left")
	check(DirtBike.hand_steer(deg_to_rad(1.0), 0.0) == 0.0, "the hands a degree off straight steer straight")
	check(absf(DirtBike.hand_steer(deg_to_rad(5.0), 10.0)) < deg_to_rad(1.0), "at speed a small turn of the hands is a very small turn of the wheel (%.2f degrees)" % rad_to_deg(DirtBike.hand_steer(deg_to_rad(5.0), 10.0)))
	check(absf(DirtBike.hand_steer(DirtBike.STEER_LIMIT, 0.0) - DirtBike.STEER_LIMIT) < 1e-4, "at a walk the hands can turn it to full lock")
	var left := FakeController.new()
	var right := FakeController.new()
	main.add_child(left)
	main.add_child(right)
	var vr_hands := VrHands.new({"left": left, "right": right})
	var fake_rig := Node3D.new()
	var fake_camera := Camera3D.new()
	fake_rig.add_child(fake_camera)
	main.add_child(fake_rig)
	fake_camera.position = Vector3(0, 1.6, 0)
	var vr_ride := BikeRide.new(bike, fake_rig, fake_camera, vr_hands, true)
	var hand_r: VrHands.HandState = vr_hands.states[1]
	var hand_l: VrHands.HandState = vr_hands.states[0]
	vr_hands.update(DT)
	# each hand brought to its grip (where the hand really holds things: its grip socket)
	for pair in [[hand_l, left, "left"], [hand_r, right, "right"]]:
		var state: VrHands.HandState = pair[0]
		var c: FakeController = pair[1]
		var marker: Node3D = bike.grip_markers[pair[2]]
		c.global_position += marker.global_position - vr_ride.hold.real_socket(state)
		c.floats["grip"] = 1.0
	vr_ride.update(DT, 0.0, 0.0)
	vr_hands.update(DT)
	vr_ride.place_hands()
	check(vr_ride.holding("left") and vr_ride.holding("right"), "squeezing a grip with a hand on it takes hold")
	var socket := hand_r.model.socket_global().origin
	check(socket.distance_to(bike.grip_markers.right.global_position) < 0.06, "the right hand closes on its grip (%.3f m off)" % socket.distance_to(bike.grip_markers.right.global_position))
	check(vr_ride.controls.throttle == 0.0, "holding it as you took it is no throttle")
	var level_basis := Basis(Vector3.UP, bike.yaw)
	right.global_basis = Basis(level_basis * Vector3.RIGHT, deg_to_rad(40.0)) * right.global_basis   # (back: the top of the grip towards you)
	vr_ride.update(DT, 0.0, 0.0)
	check(vr_ride.controls.throttle > 0.3 and vr_ride.controls.throttle < 0.6, "twisting the right grip back 40 degrees opens the throttle part way (%.2f)" % vr_ride.controls.throttle)
	right.global_position += level_basis * Vector3(0.0, 0.0, -0.15)
	left.global_position += level_basis * Vector3(0.0, 0.0, 0.15)
	vr_ride.update(DT, 0.0, 0.0)
	check(vr_ride.controls.steer_to > 0.2, "pushing the right hand forward and pulling the left back turns the bars left (%.2f)" % vr_ride.controls.steer_to)
	right.floats["grip"] = 0.0
	vr_ride.update(DT, 0.0, 0.0)
	check(not vr_ride.holding("right") and vr_ride.controls.throttle == 0.0, "letting go of the right grip shuts the throttle")
	vr_ride.end()

	# the build menu has them, and the engine makes a sound
	var added := BuildPieces.make("bike", "bike_2")
	check(BuildPieces.info(added).get("rideable", false) and BuildPieces.info(added).kind == "bike" and "bike" in BuildPieces.ADDABLE, "a dirt bike can be added from the build menu")
	added.free()
	check("add_bike" in WatchMenu.BUILD_ACTIONS, "(the build page has the button)")
	var sound := BikeSound.new()
	sound.level = 1.0
	sound.rpm = 8000.0
	sound.load_ = 1.0
	var loud := 0.0
	for v in sound.render(4410):
		loud = maxf(loud, absf(v.x))
	check(loud > 0.1 and loud <= 1.1, "the engine sounds (peak %.2f)" % loud)
	sound.free()

	HubLayout.clear()
	print("\n%s" % ("all bike checks pass" if failures == 0 else "%d failed" % failures))
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
