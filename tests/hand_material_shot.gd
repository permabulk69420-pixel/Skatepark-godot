# Render the actual hand material in the Compatibility renderer, from both sides.
# godot --path . --xr-mode off --audio-driver Dummy --rendering-driver opengl3 \
#   --rendering-method gl_compatibility -s res://tests/hand_material_shot.gd -- <output directory>
extends SceneTree

var camera: Camera3D
var out_dir := "/tmp"

func _init() -> void:
	run.call_deferred()

func snap(file: String) -> void:
	for frame in 5: await process_frame
	root.get_texture().get_image().save_png(out_dir.path_join(file+".png"))
	print("SAVED ",file)

func run() -> void:
	root.size = Vector2i(1280, 960)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: out_dir = args[0]
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("273332")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d6dfdf")
	environment.ambient_light_energy = .42
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.light_color = Color("fff0df")
	stage.add_child(sun)
	sun.look_at_from_position(Vector3(-1,2,1),Vector3.ZERO)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = .37
	stage.add_child(camera)
	var left := HandModel.create("left")
	var right := HandModel.create("right")
	stage.add_child(left.root)
	stage.add_child(right.root)
	left.root.position.x = -.085
	right.root.position.x = .085
	camera.look_at_from_position(Vector3(0,.38,-.08),Vector3(0,-.01,-.08),Vector3.FORWARD)
	await snap("dorsal")
	camera.look_at_from_position(Vector3(0,-.38,-.08),Vector3(0,-.01,-.08),Vector3.FORWARD)
	sun.look_at_from_position(Vector3(-1,-2,1),Vector3.ZERO)
	await snap("palms")
	left.set_pose("Grip",.86)
	right.set_pose("Fist",1.0)
	camera.look_at_from_position(Vector3(0,.26,.27),Vector3(0,-.01,-.06))
	sun.look_at_from_position(Vector3(-1,2,1),Vector3.ZERO)
	await snap("grip_and_fist")
	stage.queue_free()
	await process_frame
	# Same material in the real photogrammetry level and its own lighting.
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "gravesend"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	if not main.ready_to_play:
		push_error("Photogrammetry level did not become ready")
		quit(1)
		return
	main.set_process(false)
	main.hud.layer.visible = false
	camera = main.camera
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(Vector3(0,30,8),Vector3(0,-30,8))
	var ground: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	if ground.is_empty():
		push_error("No scan surface found for the hand preview")
		quit(1)
		return
	var eye: Vector3 = ground.position + Vector3(0,1.65,0)
	camera.look_at_from_position(eye,eye+Vector3(0,-.28,-1))
	var left_in_game := HandModel.create("left")
	var right_in_game := HandModel.create("right")
	camera.add_child(left_in_game.root)
	camera.add_child(right_in_game.root)
	left_in_game.root.position = Vector3(-.15,-.16,-.36)
	right_in_game.root.position = Vector3(.15,-.16,-.36)
	left_in_game.set_pose("Open",0)
	right_in_game.set_pose("Open",0)
	await snap("gravesend")
	main.queue_free()
	await process_frame
	quit()
