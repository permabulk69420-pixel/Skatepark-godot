# A timed run: the start and finish lines, the clock, and what the game does at each (on a flat screen, in Flightline).
#   godot --headless --path . -s res://tests/run_logic.gd
extends SceneTree

var failures := 0


func _init() -> void:
	run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += 1.0 / 30.0


func run() -> void:
	var info := Levels.LEVELS["flightline"].run
	var r := Run.new(info)
	var up := Vector3(0, 200, 40)
	check(r.update(0.1, up, Vector3(0, 200, 35)) == "" and r.state == Run.State.WAITING, "riding up to the start line does nothing")
	check(r.update(0.1, Vector3(0, 186, 31), Vector3(0, 186, 28)) == "start" and r.state == Run.State.RUNNING, "riding over the start line starts the run")
	r.update(0.5, Vector3(0, 100, 0), Vector3(0, 100, -1))
	r.update(0.25, Vector3(0, 100, -1), Vector3(0, 100, -2))
	check(absf(r.time - 0.75) < 1e-6, "the clock counts the frames since (%.2f)" % r.time)
	check(r.update(0.1, Vector3(0, 21, -940), Vector3(0, 21, -943)) == "", "short of the finish line: nothing")
	check(r.update(0.1, Vector3(20, 22, -943), Vector3(20, 22, -946)) == "", "going past the end of the line, beside it: nothing")
	check(r.update(0.1, Vector3(0, 12, -943), Vector3(0, 12, -946)) == "", "going under it, too low: nothing")
	check(r.update(0.1, Vector3(0, 22, -946), Vector3(0, 22, -943)) == "", "going back over it the wrong way: nothing")
	check(r.update(0.1, Vector3(0, 22, -943), Vector3(0, 22, -946)) == "finish" and r.state == Run.State.DONE, "going over the vert's coping finishes the run")
	var frozen := r.time
	r.update(1.0, Vector3(0, 22, -950), Vector3(0, 22, -951))
	check(r.time == frozen, "the clock stops")
	r.reset()
	check(r.state == Run.State.WAITING and r.time == 0.0, "reset puts it back at the start")
	check(r.update(0.1, Vector3(0, 186, 80), Vector3(0, 186, -80)) == "" and r.state == Run.State.WAITING, "a respawn (a jump across the line) is not riding over it")
	check(Run.format_time(0.0) == "0:00.0" and Run.format_time(72.46) == "1:12.4" and Run.format_time(605.0) == "10:05.0", "times read m:ss.t")

	# In the game
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "flightline"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	check(main.run != null and main.run.state == Run.State.WAITING, "Flightline has a run, waiting at the start")
	check(main.get_node_or_null("StartLine") != null and main.get_node_or_null("FinishLine") != null, "both lines are there to see")
	await wait(0.5)
	check(main.run.time == 0.0, "the clock does not run while you stand on the start")
	key(KEY_W, true)
	var waited := 0.0
	while main.run.state == Run.State.WAITING and waited < 15.0:
		await wait(0.2)
		waited += 0.2
	key(KEY_W, false)
	check(main.run.state == Run.State.RUNNING, "riding off the top starts the run (after %.1fs)" % waited)
	check(main.face_card.seconds_left > 0.0 and main.face_card.title.text == "GO!", "and GO! comes up")
	guard = 0
	while main.run.time < 0.5 and guard < 600:   # (a headless frame is quicker than a real one, so wait on the clock itself)
		await process_frame
		guard += 1
	check(main.run.time >= 0.5, "the clock is running (%.1fs)" % main.run.time)
	# the finish: put the skater over the coping
	main.score.total = 4200
	var before: Vector3 = Vector3(0, 22, -943)
	main.sim.pos = Vector3(0, 22, -946)
	main._update_run(0.0, before)
	check(main.run.state == Run.State.DONE and main.run.final_score == 4200, "going over the coping finishes it, worth the score (%d)" % main.run.final_score)
	check(main.face_card.title.text == "FINISH" and main.face_card.lines.text.contains("4,200") and main.face_card.lines.text.contains(":"), "the card gives the time and the score (%s)" % main.face_card.lines.text.replace("\n", " / "))
	check(main.hud.time_label.text.begins_with("TIME"), "the flat screen shows the time")
	# riding back to the start spot begins again
	main.sim.respawn(main.sim.spawn)
	check(main.run.state == Run.State.WAITING and main.score.total == 0 and main.run.time == 0.0, "back on the start spot, the run and the score begin again")
	main.queue_free()
	await process_frame
	print("%s" % ("all fine" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
