# The remote in a hand, from a few sides. Software rendering is fine.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/remote_shot.gd -- <out dir> <mode>
extends SceneTree

class FakeController extends Node3D:
	var floats := {}
	func get_float(action: String) -> float:
		return floats.get(action, 0.0)
	func get_has_tracking_data() -> bool:
		return true


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var mode := int(args[1]) if args.size() > 1 else 0
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
	var camera := Camera3D.new()
	camera.fov = 45.0
	holder.add_child(camera)
	var right := FakeController.new()
	holder.add_child(right)
	var hands := VrHands.new({"right": right})
	var remote := HubRemote.build()
	holder.add_child(remote)
	var state: VrHands.HandState = hands.states[0]
	state.held = true
	state.held_pose = VrHands.GRIP_POSES["medium"]
	right.floats["grip"] = 1.0
	for i in 20:
		hands.update(0.02)
	remote.global_transform = state.model.socket_global() * HubRemote.in_hand("right", mode)
	var views := {"front": Vector3(0, 0.05, -0.45), "back": Vector3(0, 0.05, 0.45), "above": Vector3(0, 0.45, 0.05), "side": Vector3(0.45, 0.05, 0)}
	for v in views:
		camera.global_position = right.global_position + views[v]
		camera.look_at(right.global_position, Vector3.UP if v != "above" else Vector3.FORWARD)
		for i in 3:
			await process_frame
		root.get_texture().get_image().save_png("%s/remote_%d_%s.png" % [out, mode, v])
	quit()
