# The watch and the menu: what counts as a tap on the glass, where a pointing ray lands on the menu, which buttons each place has,
# and that opening the menu pauses the game on a flat screen.
#   godot --headless --path . -s res://tests/watch_logic.gd
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
	# A tap on the glass
	check(Watch.poke_hit(Vector3(0, 0.005, 0)), "a fingertip just above the middle of the glass taps it")
	check(Watch.poke_hit(Vector3(0, -0.005, 0.01)), "...and so does one pressed a little into it")
	check(not Watch.poke_hit(Vector3(0, 0.03, 0)), "a fingertip hovering 3 cm above does not")
	check(not Watch.poke_hit(Vector3(0.05, 0.0, 0)), "one beside the watch does not")
	check(not Watch.poke_hit(Vector3(0, -0.05, 0)), "one on the other side of the wrist does not")
	check(Watch.poke_clear(Vector3(0, 0.05, 0)) and Watch.poke_clear(Vector3(0.07, 0.0, 0)), "lifted clear or moved off, it can tap again")
	check(not Watch.poke_clear(Vector3(0, 0.01, 0)), "resting on the glass is not clear")
	check(Watch.font_size_for("0") > Watch.font_size_for("1,234,567"), "a long score gets a smaller font")
	check(Watch.font_size_for("1,234,567") >= 36, "...but not too small to read")

	# Where a ray lands on the menu
	var face := Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -1))
	var middle := WatchMenu.ray_to_pixel(face, Vector3(0, 1.5, 0), Vector3(0, 0, -1))
	check(middle.distance_to(Vector2(WatchMenu.PIXELS) / 2.0) < 2.0, "straight at the middle lands on the middle (%s)" % middle)
	var size := WatchMenu.INNER * WatchMenu.FRAME_SCALE
	var upper_left := WatchMenu.ray_to_pixel(face, Vector3(-size.x * 0.4, 1.5 + size.y * 0.4, 0), Vector3(0, 0, -1))
	check(upper_left.x < WatchMenu.PIXELS.x * 0.2 and upper_left.y < WatchMenu.PIXELS.y * 0.2, "up and to the left lands in the top left (%s)" % upper_left)
	check(WatchMenu.ray_to_pixel(face, Vector3(1.0, 1.5, 0), Vector3(0, 0, -1)) == Vector2.INF, "past the edge lands nowhere")
	check(WatchMenu.ray_to_pixel(face, Vector3(0, 1.5, 0), Vector3(0, 0, 1)) == Vector2.INF, "pointing away lands nowhere")
	check(WatchMenu.ray_to_pixel(face, Vector3(0, 1.5, 0), Vector3(1, 0, 0)) == Vector2.INF, "pointing along the menu lands nowhere")
	var turned := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(2, 1.5, 0))   # a menu to the right, facing along -X... its +Z points to +X
	check(WatchMenu.ray_to_pixel(turned, Vector3(0, 1.5, 0), Vector3(1, 0, 0)).distance_to(Vector2(WatchMenu.PIXELS) / 2.0) < 2.0, "a turned menu is hit from the side it faces")

	# What each place offers
	check(WatchMenu.actions_for(false) == ["resume", "retry", "home", "exit"], "a level: resume, retry, return to house, exit")
	check(WatchMenu.actions_for(true) == ["resume", "exit"], "the house: only resume and exit")

	# On a flat screen: M opens it, the game stops, a button picks
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "gravesend"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	check(main.watch_menu != null and not main.watch_menu.is_open, "the menu starts shut")
	var picked := []
	main.watch_menu.chosen.connect(func(action: String) -> void: picked.append(action))
	await wait(0.5)
	key(KEY_M, true)
	await wait(0.2)
	key(KEY_M, false)
	await wait(0.2)
	check(main.watch_menu.is_open, "M opens the menu")
	check(main.watch_menu.layer.visible, "...over the game")
	var before: Vector3 = main.sim.pos
	key(KEY_W, true)
	await wait(1.0)
	key(KEY_W, false)
	check(main.sim.pos.distance_to(before) < 0.001, "the skater does not move while it is open")
	main.watch_menu.chosen.disconnect(main._on_menu_chosen)   # (Retry would reload the scene, which a test cannot do)
	(main.watch_menu.buttons["retry"] as Button).pressed.emit()
	main.watch_menu.chosen.connect(main._on_menu_chosen)
	check(picked == ["retry"], "pressing Retry says so")
	(main.watch_menu.buttons["resume"] as Button).pressed.emit()
	await wait(0.2)
	check(not main.watch_menu.is_open and not main.watch_menu.layer.visible, "Resume shuts it")
	key(KEY_W, true)
	await wait(1.0)
	key(KEY_W, false)
	check(main.sim.pos.distance_to(before) > 0.3, "and the skater moves again")
	key(KEY_M, true)
	await wait(0.2)
	key(KEY_M, false)
	await wait(0.2)
	check(main.watch_menu.is_open, "M opens it again")
	key(KEY_M, true)
	await wait(0.2)
	key(KEY_M, false)
	await wait(0.2)
	check(not main.watch_menu.is_open, "...and M shuts it")
	main.queue_free()
	await process_frame
	print("%s" % ("all fine" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
