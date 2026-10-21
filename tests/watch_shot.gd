# Renders the watch on the wrist, a tap on its glass, and the menu (with the laser on a button) to PNGs so they can be looked at.
#   xvfb-run -a godot --path . --rendering-driver opengl3 --rendering-method gl_compatibility -s res://tests/watch_shot.gd -- <out dir>
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
	for i in 4:
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
	camera.fov = 60.0
	camera.near = 0.02
	holder.add_child(camera)

	var left := FakeController.new()
	var right := FakeController.new()
	holder.add_child(left)
	holder.add_child(right)
	var hands := VrHands.new({"left": left, "right": right})
	var watch := Watch.new(hands.states[0].model)
	left.position = Vector3(0, 0, 0)
	hands.update(0.1)
	watch.set_score(12450)
	# the back of the left hand faces -X: look at it from there
	aim(Vector3(-0.32, 0.05, -0.08), Vector3(0, 0, -0.02))
	await snap("watch_wrist")
	aim(Vector3(-0.2, 0.2, -0.3), Vector3(0, 0, -0.04))
	await snap("watch_wrist_high")
	watch.set_score(1234567)
	aim(Vector3(-0.12, 0.0, 0.0), Vector3(0, 0, 0))
	await snap("watch_close")

	# a tap: the right hand's index fingertip on the glass
	watch.set_score(900)
	var face := watch.face.global_position
	right.rotation = Vector3(0, PI / 2.0, 0)   # the right hand points its fingers along -Z; turn it to come at the glass from -X
	hands.update(0.1)
	var tip := hands.states[1].model.index_tip()
	right.position += (face + Vector3(-0.05, 0, 0)) - tip
	hands.update(0.1)
	print("tap before: ", watch.update(hands.states[1].model.index_tip()))
	right.position += watch.face.global_transform.basis.y * -0.0   # (stays above the glass)
	aim(Vector3(-0.35, 0.15, 0.1), face)
	await snap("watch_tap_approach")
	var local := watch.face.global_transform.affine_inverse() * hands.states[1].model.index_tip()
	print("tip in glass frame: ", local)

	# the menu
	for c in [left, right]:
		c.queue_free()
	var menu := WatchMenu.new(holder, true, false, "Gravesend")
	camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	menu.open(camera.global_transform)
	menu.update(Vector3(0.25, 1.35, 0.2), Vector3(0, 0, -1), false)
	await snap("menu_plain")
	# point at the Retry button
	var retry: Button = menu.buttons["retry"]
	var centre := retry.get_global_rect().get_center()
	var size := WatchMenu.INNER * WatchMenu.FRAME_SCALE
	var target := menu.root.global_transform * Vector3((centre.x / WatchMenu.PIXELS.x - 0.5) * size.x, (0.5 - centre.y / WatchMenu.PIXELS.y) * size.y, WatchMenu.FACE_Z * WatchMenu.FRAME_SCALE)
	var from := Vector3(0.3, 1.25, -0.1)
	menu.update(from, (target - from).normalized(), false)
	await process_frame
	menu.update(from, (target - from).normalized(), false)
	await snap("menu_hover")
	print("hovering: ", menu.over.text if menu.over != null else "nothing")
	camera.global_transform = Transform3D(Basis.looking_at(Vector3(0.3, -0.1, -1)), Vector3(0.0, 1.6, 0.3))
	await snap("menu_side")
	quit()
