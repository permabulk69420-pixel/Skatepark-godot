# Holding the menu key (L) goes home from a level and, at home, on to the next level; the TV opens on the last level played.
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


# Holds L until the scene changes, then lets go.
func hold_l() -> Node:
	key(KEY_L, true)
	var before := current_scene
	var guard := 0
	while current_scene == before and guard < 600:
		await create_timer(0.05).timeout
		guard += 1
	key(KEY_L, false)
	var main := await loaded()
	await create_timer(0.3).timeout
	return main


func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.SETTINGS))
	Levels.next_id = ""
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	var main := await loaded()
	check(main.level_id == Levels.HUB, "opens at home (now %s)" % main.level_id)
	# at home the key goes on to the level after the last one played, and from a level it comes home again
	var want: String = Levels.next_channel(Levels.saved())
	for lap in 2:
		main = await hold_l()
		check(main.level_id == want, "hold L at home -> %s (now %s)" % [want, main.level_id])
		check(Levels.saved() == want, "remembered %s" % want)
		main = await hold_l()
		check(main.level_id == Levels.HUB, "hold L in a level -> home")
		want = Levels.next_channel(want)
	# a short press does nothing
	key(KEY_L, true)
	await create_timer(0.3).timeout
	key(KEY_L, false)
	await process_frame
	check(current_scene == main and main.level_id == Levels.HUB, "a short press stays put")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.SETTINGS))
	print("\n%s" % ("all level-switch checks pass" if failures == 0 else "%d failed" % failures))
	quit(0 if failures == 0 else 1)
