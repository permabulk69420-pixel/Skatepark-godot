# Holding the next-level key (L) goes on to the next level, wraps round, and the game remembers where it was left.
#   godot --headless --path . -s res://tests/level_switch.gd
extends SceneTree

var failures := 0


func _init() -> void:
	run.call_deferred()


func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


# Waits until the scene that is current now has loaded its level.
func loaded() -> Node:
	var guard := 0
	while (current_scene == null or not current_scene.get("ready_to_play")) and guard < 3000:
		await process_frame
		guard += 1
	return current_scene


func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.SETTINGS))
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	var main := await loaded()
	check(main.level_id == "gravesend", "opens on %s by default" % main.level_id)
	var expected := ["megaramp", "flightline", "gravesend"]
	for want in expected:
		key(KEY_L, true)
		var before := current_scene
		var guard := 0
		while current_scene == before and guard < 600:
			await create_timer(0.05).timeout
			guard += 1
		key(KEY_L, false)
		main = await loaded()
		check(main.level_id == want, "hold L -> %s (now %s)" % [want, main.level_id])
		check(Levels.saved() == want, "remembered %s" % want)
		await create_timer(0.3).timeout
	# a short press does nothing
	key(KEY_L, true)
	await create_timer(0.3).timeout
	key(KEY_L, false)
	await process_frame
	check(current_scene == main and main.level_id == "gravesend", "a short press stays put")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.SETTINGS))
	print("\n%s" % ("all level-switch checks pass" if failures == 0 else "%d failed" % failures))
	quit(0 if failures == 0 else 1)
