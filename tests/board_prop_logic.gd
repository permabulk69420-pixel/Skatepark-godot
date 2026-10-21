# The loose board (board_prop.gd): where it ends up when it is dropped, thrown or left on a slope, and that a wall stops it.
#   godot --headless --path . -s res://tests/board_prop_logic.gd
extends SceneTree

var failures := 0


func check(ok: bool, what: String) -> void:
	print("%s %s" % ["  ok  " if ok else "  FAIL", what])
	if not ok:
		failures += 1


func box(size: Vector3, at: Vector3, rot := Basis.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	body.add_child(shape)
	body.transform = Transform3D(rot, at)
	root.add_child(body)
	return body


func run(prop: BoardProp, seconds: float) -> float:
	var lowest := INF
	var t := 0.0
	while t < seconds:
		prop.step(1.0 / 72.0)
		lowest = minf(lowest, prop.origin().y)
		t += 1.0 / 72.0
	return lowest


func _init() -> void:
	box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))                                  # the floor, top at y = 0
	box(Vector3(10, 1, 30), Vector3(40, -0.5, 0), Basis(Vector3(0, 0, 1), deg_to_rad(20)))   # a 20° slope, off to one side
	box(Vector3(1, 6, 20), Vector3(-6.5, 3, 0))                                   # a wall, its face at x = -6
	for i in 4:
		await physics_frame
	var world := SkateWorld.new(root.get_world_3d().direct_space_state)

	var prop := BoardProp.new(world)
	prop.place(Vector3(0, 0.5, 0), Quaternion.IDENTITY)
	var lowest := run(prop, 3.0)
	check(prop.asleep and prop.upright() and absf(prop.origin().y) < 0.03, "dropped wheels down it lands on its wheels and stays there (%.3f, asleep %s)" % [prop.origin().y, str(prop.asleep)])
	check(lowest > -0.05, "and never sinks into the floor (lowest %.3f)" % lowest)

	prop.place(Vector3(0, 0.6, 0), Quaternion(Vector3(1, 0, 0), PI))
	lowest = run(prop, 3.0)
	check(prop.asleep and (prop.quat * Vector3.UP).y < -0.8 and prop.origin().y > 0.08 and prop.origin().y < 0.22, "dropped upside down it rests on its deck (height %.3f)" % prop.origin().y)

	prop.place(Vector3(0, 0.8, 0), Quaternion(Vector3(0, 0, 1), deg_to_rad(80)) * Quaternion(Vector3(1, 0, 0), 0.3))
	run(prop, 4.0)
	check(prop.asleep and prop.touching >= 3 and prop.com.y > 0.0, "dropped tumbling it comes to rest (asleep %s)" % str(prop.asleep))

	prop.place(Vector3(0, 0.05, 0), Quaternion.IDENTITY, Vector3(4, 0, 0))
	run(prop, 2.0)
	check(prop.origin().x < 1.5 and prop.vel.length() < 0.1, "pushed sideways across its wheels it skids to a stop (%.2f m)" % prop.origin().x)

	prop.place(Vector3(0, 0.05, 0), Quaternion.IDENTITY, Vector3(0, 0, -3))
	run(prop, 1.0)
	check(prop.origin().z < -1.5, "pushed the way it points it rolls on (%.2f m)" % prop.origin().z)

	prop.place(Vector3(0, 0.3, 0), Quaternion.IDENTITY, Vector3(-9, 2, 0))
	run(prop, 2.0)
	check(prop.com.x > -6.0, "thrown at a wall it stays this side of it (x %.2f)" % prop.com.x)

	var hit := world.ground(38.0, 0.0, 10.0, SkateWorld.Hit.new(), 20.0)
	check(hit != null, "the test slope is there")
	if hit != null:
		var q := Quaternion(Vector3.UP, hit.normal) * Quaternion(Vector3(0, 1, 0), -PI / 2.0)
		prop.place(Vector3(38, hit.y + 0.03, 0), q)
		run(prop, 2.0)
		var moved := prop.origin().distance_to(Vector3(38, hit.y, 0))
		check(moved > 1.0, "left on a slope on its wheels, it rolls downhill (%.1f m in 2 s)" % moved)
		prop.place(Vector3(38, hit.y + 0.03, 0), Quaternion(Vector3.UP, hit.normal) * Quaternion(Vector3(1, 0, 0), PI))
		run(prop, 4.0)
		check(prop.origin().distance_to(Vector3(38, hit.y, 0)) < 3.0, "upside down on the same slope it mostly stays where it is")

	print("%s" % ("all fine" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
