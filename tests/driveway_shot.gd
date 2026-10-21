# Render the driveway in the real hub lighting, without moving the player.
# Run with a graphical display: godot --xr-mode off --audio-driver Dummy \
# --path . -s res://tests/driveway_shot.gd -- <output directory>
extends SceneTree

func _init() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 960)
	var out := OS.get_cmdline_user_args()[0]
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	if not main.ready_to_play:
		quit(1)
		return
	main.set_process(false)
	main.hud.layer.visible = false
	var camera := Camera3D.new()
	camera.fov = 72
	main.add_child(camera)
	camera.make_current()
	for spot in [
		["gate", Vector3(-17.5, 2.3, 19), Vector3(-11, 0.9, 5)],
		["driveway_to_ramp", Vector3(-14, 1.8, 4), Vector3(-7, 1, -19)],
		["overview", Vector3(-28, 28, 29), Vector3(-4, 0, -4)],
		["ramp_connection", Vector3(-11.5, 2, -10), Vector3(-3, 0.7, -18)],
	]:
		camera.look_at_from_position(spot[1], spot[2])
		for frame in 8: await process_frame
		root.get_texture().get_image().save_png(out.path_join(spot[0] + ".png"))
		print("SAVED ", spot[0])
	main.queue_free()
	await process_frame
	quit()
