# Renders the hands (poses, and holding the board) to PNGs so they can be looked at. Software rendering is fine.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/hands_shot.gd -- <out dir>
extends SceneTree

class FakeController extends Node3D:
	var floats := {}
	func get_float(action: String) -> float:
		return floats.get(action, 0.0)
	func get_has_tracking_data() -> bool:
		return true

var out_dir := "/tmp"
var camera: Camera3D


func _init() -> void:
	run.call_deferred()


func snap(file: String) -> void:
	for i in 3:
		await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, file])


func aim(from: Vector3, at: Vector3) -> void:
	camera.global_position = from
	camera.look_at(at, Vector3.UP)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var holder := Node3D.new()
	root.add_child(holder)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("6d8796")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c9d6dd")
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	holder.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	holder.add_child(sun)
	sun.look_at_from_position(Vector3(1, 2, 1.5), Vector3.ZERO)
	camera = Camera3D.new()
	camera.fov = 50.0
	holder.add_child(camera)

	var left := FakeController.new()
	var right := FakeController.new()
	holder.add_child(left)
	holder.add_child(right)
	var hands := VrHands.new({"left": left, "right": right})

	# 1: the four authored poses, both hands side by side
	left.position = Vector3(-0.12, 0, 0)
	right.position = Vector3(0.12, 0, 0)
	# controllers held the way a rider holds them: grip pose pointing forward (-Z)
	aim(Vector3(0, 0.25, 0.55), Vector3(0, 0, 0))
	var poses := {"open": [0.0, 0.0], "pinch": [1.0, 0.0], "grip": [0.0, 1.0], "fist": [1.0, 1.0]}
	for pose_name in poses:
		for c in [left, right]:
			c.floats["trigger"] = poses[pose_name][0]
			c.floats["grip"] = poses[pose_name][1]
		hands.update(0.1)
		await snap("pose_" + pose_name)

	# 2: holding the board
	for c in [left, right]:
		c.floats = {}
	hands.update(0.1)
	var board := Node3D.new()
	holder.add_child(board)
	board.add_child((load("res://assets/board/skateboard.glb") as PackedScene).instantiate())
	board.global_position = Vector3(0, -0.5, -0.6)
	var sim := Skater.new(SkateWorld.new(holder.get_world_3d().direct_space_state))
	sim.mode = Skater.Mode.AIR
	sim.pos = board.global_position
	var grab := BoardGrab.new(hands, board, camera, null)
	var step := func() -> void:
		grab.update(0.014, true)
		grab.hold_board(sim, 0.014)
		hands.update(0.014)
		grab.place()
	# the controller poses are the hands' own, as the rider would hold them: palm in, fingers forward
	right.position = Vector3(0.15, -0.35, -0.95)
	right.rotation_degrees = Vector3(0, 0, 0)
	right.floats["grip"] = 1.0
	left.position = Vector3(-0.3, -0.3, -0.55)
	left.floats["grip"] = 1.0
	for i in 40:
		step.call()
	print("holding: ", grab.names())
	aim(Vector3(0.55, -0.05, -1.2), Vector3(0.05, -0.4, -0.75))
	await snap("grab_nose_right")
	aim(Vector3(-0.7, 0.05, -0.2), Vector3(-0.2, -0.4, -0.55))
	await snap("grab_left_edge")
	aim(Vector3(0.0, 0.5, -0.6), Vector3(0, -0.4, -0.7))
	await snap("grab_from_above")
	aim(Vector3(0.9, -0.2, -0.5), Vector3(0, -0.4, -0.7))
	await snap("grab_from_side")
	quit()
