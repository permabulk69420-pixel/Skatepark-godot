# Landing on a little bump: a short hop with no trick on it never bails for the landing angle or hardness; a real landing still does.
#   godot --headless --path . -s res://tests/bump_logic.gd
extends SceneTree

var failures := 0


func _init() -> void:
	run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


# Land a skater that has been in the air for `air` seconds, travelling `vel`, board pointing straight ahead. What did it do?
func land_with(main: Node, air: float, vel: Vector3, trick := "") -> String:
	var sim = main.sim
	var reasons: Array = []
	var on_event := func(type: String, data: Dictionary) -> void:
		if type == "bail":
			reasons.append(data.reason)
	sim.event.connect(on_event)
	sim.pos = Vector3(0, 224.0, 5.0)
	sim.heading = 0.0
	sim.mode = Skater.Mode.AIR
	sim.air_time = air
	sim.vel = vel
	sim.board_off = false
	sim.flip = null
	sim.shuv = null
	sim.off_trick = null if trick == "" else {"name": trick, "far": 0.0, "tpose": 0.0}
	sim.land(true, Vector3.UP)
	sim.event.disconnect(on_event)
	return reasons[0] if reasons.size() > 0 else ""


func run() -> void:
	var main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "flightline"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	var T = Config.Tuning
	var hard := Vector3(0, -20.0, -10.0)    # 20 m/s into the ground, well past the 13 m/s limit
	var sideways := Vector3(12.0, -1.0, 0.0)  # travelling 90 degrees off where the board points
	check(land_with(main, 1.2, hard) == "impact", "a long fall onto hard ground still bails")
	check(land_with(main, 0.1, hard) == "", "a short hop onto the same ground does not")
	check(land_with(main, 1.2, sideways) == "landing", "landing sideways after a long hop still bails")
	check(land_with(main, 0.1, sideways) == "", "landing sideways after a short hop does not")
	check(land_with(main, T.bumpHopTime + 0.05, hard) == "impact", "just over the hop time counts as a real landing")
	check(land_with(main, 0.1, hard, "Board Off") == "impact", "a short hop with a trick on it is still judged as a landing")
	check(land_with(main, 0.1, Vector3(0, -2.0, -10.0)) == "", "an ordinary gentle landing is fine, as before")
	print("all bump checks pass" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
