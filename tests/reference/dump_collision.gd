# Writes the level's collision triangles exactly as the sim collides with them (world space, float32 x y z per vertex, three per
# triangle) so the web build's sim can be pointed at the identical geometry for a like-for-like comparison.
#   godot --headless --path . -s res://tests/reference/dump_collision.gd -- <out.bin>
extends SceneTree

func _init() -> void:
	run.call_deferred()


func run() -> void:
	await process_frame
	var holder := Node3D.new()
	root.add_child(holder)
	var level := LevelLoader.load_level("res://assets/levels/gravesend.glb", holder)
	await process_frame
	var shape: ConcavePolygonShape3D = level.collision_bodies[0].get_child(0).shape
	var faces := shape.get_faces()
	var out := PackedFloat32Array()
	out.resize(faces.size() * 3)
	for i in faces.size():
		out[i * 3] = faces[i].x
		out[i * 3 + 1] = faces[i].y
		out[i * 3 + 2] = faces[i].z
	var f := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	f.store_buffer(out.to_byte_array())
	f.close()
	print("wrote %d triangles" % (faces.size() / 3))
	quit()
