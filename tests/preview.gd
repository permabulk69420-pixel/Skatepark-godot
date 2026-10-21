# Takes the pictures the TV shows: each level seen from where you start, no overlay, 640 x 360. Software rendering is fine.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/preview.gd -- <level id> [<level id> …]
extends SceneTree


func _init() -> void:
	run.call_deferred()


func run() -> void:
	for id in OS.get_cmdline_user_args():
		var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		main.level_id = id
		root.add_child(main)
		var guard := 0
		while not main.ready_to_play and guard < 3000:
			await process_frame
			guard += 1
		main.hud.layer.visible = false
		for i in 6:
			await process_frame
		var image := root.get_texture().get_image()
		image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		image.save_jpg("res://assets/previews/%s.jpg" % id, 0.85)
		print("saved ", id)
		main.queue_free()
		await process_frame
	quit()
