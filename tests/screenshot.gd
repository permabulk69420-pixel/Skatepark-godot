# Boots the real main scene, drives it with simulated key presses and saves screenshots (software rendering is fine).
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/screenshot.gd -- <out dir>
extends SceneTree

var main: Node
var out_dir := "/tmp"


func _init() -> void:
	run.call_deferred()


func key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("saved ", name, " ", img.get_size())


func wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await process_frame
		t += 1.0 / 30.0   # frames run slowly under software rendering; count them, not wall time


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "gravesend"   # (not whichever level was left on last; `level=<id>` after -- picks another)
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	print("ready after ", guard, " frames")
	await wait(1.0)
	await shot("1_spawn")
	key(KEY_W, true)
	await wait(4.0)
	await shot("2_pushing")
	key(KEY_A, true)
	await wait(1.5)
	key(KEY_A, false)
	await shot("3_turning")
	key(KEY_SPACE, true)
	await wait(0.3)
	key(KEY_SPACE, false)
	await wait(0.25)
	await shot("4_ollie")
	await wait(2.0)
	key(KEY_W, false)
	main.rig_control.look_pitch = -0.85
	await wait(0.5)
	await shot("5_board")
	main.rig_control.look_pitch = 0.0
	print("mode ", main.sim.mode, " speed ", main.sim.speed, " pos ", main.sim.pos)
	main.queue_free()
	await process_frame
	quit()
