# Pictures of the house from a few spots (software rendering is fine), to look at.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/hub_shot.gd -- <out dir>
extends SceneTree


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	main.hud.layer.visible = false
	# [name, x east, y north, height, facing (0 north, PI/2 west, PI south, -PI/2 east), look pitch]
	var spots := [
		["1_start", 0.0, -3.0, 0.30, 0.0, 0.0],
		["2_tv", -0.5, 0.0, 0.30, PI / 2.0, 0.05],
		["3_shop", 4.6, -2.5, 0.30, -PI / 2.0, 0.1],
		["4_back", 1.0, 6.4, 0.30, 0.0, -0.05],
		["5_house", 1.0, 14.0, 0.0, PI, 0.12],
		["6_pad", 9.0, 19.5, 0.0, PI / 2.0, 0.0],
		["7_couch", -5.6, -1.6, 0.30, -PI / 2.0 - 0.5, -0.3],
		["8_ramp", 3.5, 15.5, 0.0, -0.6, -0.15],
	]
	for s in spots:
		main.foot.place(Vector3(s[1], s[3], -s[2]), s[4])
		main.foot.update(0.05, Vector2.ZERO, 0.0)
		main.foot.look_pitch = s[5]
		main.foot.update(0.05, Vector2.ZERO, 0.0)
		for i in 5:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [out, s[0]])
		print("saved ", s[0])
	quit()
