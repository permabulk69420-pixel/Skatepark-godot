# The game: loads the level, puts the skater on it, and runs the frame loop. In a headset (OpenXR) the player stands on the board
# and the Quest controllers drive it; otherwise it plays on a flat screen with a keyboard or gamepad.
extends Node3D

const CONTROLS_HINT := "W push · S brake · A/D steer & balance · hold Space to crouch, release to ollie · G or Shift to grind · F in the air + A/D: kickflip / heelflip, S: shove-it, S+A / S+D: varial kickflip / heelflip · flick W-S for a manual · drag to look · hold R: back to the entrance · Z stance\nGamepad: left stick, A ollie, B flip, right trigger grind, Y stance, hold X entrance"
const REFRESH_RATE := 72.0   # Hz the headset is asked to run at

var level_id := Levels.DEFAULT_LEVEL
var info: Dictionary
var vr := false
var rig: Node3D
var camera: Camera3D
var left_controller: XRController3D
var right_controller: XRController3D
var level: LevelLoader
var world: SkateWorld
var sim: Skater
var rig_control: PlayerRig
var board_view: BoardView
var hud: Hud
var sfx: Sfx
var music: Music
var haptics: Haptics
var vr_gauge: VrGauge
var hand_balance := HandBalance.new()
var input := SkateInput.new()
var ready_to_play := false
var dragging := false


func _ready() -> void:
	info = Levels.LEVELS[level_id]
	vr = _start_xr()
	_build_environment(info.look)
	if vr:
		rig = XROrigin3D.new()
		camera = XRCamera3D.new()
		left_controller = _make_controller(&"left_hand")
		right_controller = _make_controller(&"right_hand")
		rig.add_child(left_controller)
		rig.add_child(right_controller)
		input.vr_left = left_controller
		input.vr_right = right_controller
		haptics = Haptics.new(left_controller, right_controller)
	else:
		rig = Node3D.new()
		camera = Camera3D.new()
	rig.name = "Rig"
	add_child(rig)
	camera.name = "Camera"
	camera.fov = 72.0
	camera.near = 0.06
	camera.far = info.camera_far
	camera.current = true
	rig.add_child(camera)

	var loading_layer := CanvasLayer.new()
	var loading := Label.new()
	loading.text = "Loading %s…" % info.name
	loading.add_theme_font_size_override("font_size", 20)
	loading.set_anchors_preset(Control.PRESET_CENTER)
	loading_layer.add_child(loading)
	add_child(loading_layer)
	await get_tree().process_frame

	level = LevelLoader.load_level(info.file, self)
	if level == null:
		loading.text = "The park could not load."
		push_error("Could not load " + info.file)
		return
	# The collision bodies are only seen by the physics server after a physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	world = SkateWorld.new(get_world_3d().direct_space_state)
	var paths := GrindPath.parse(level.grind_nodes)
	var loops := LoopPath.parse(level.loop_nodes)
	sim = Skater.new(world, paths, loops, info.bounds, true)
	sim.set_spawn(level.spawn_pos, level.spawn_heading)
	sim.event.connect(_on_sim_event)

	hud = Hud.new(self, sim, info.name, CONTROLS_HINT + "\n\n" + info.blurb)
	rig_control = PlayerRig.new(rig, camera, sim, hud.fade_rect, vr)
	if vr:
		vr_gauge = VrGauge.new(rig)
	var model := (load("res://assets/board/skateboard.glb") as PackedScene).instantiate() as Node3D
	board_view = BoardView.new(self, model)
	sfx = Sfx.new(world)
	sfx.name = "Sfx"
	add_child(sfx)
	music = Music.new()
	music.name = "Music"
	add_child(music)
	music.start()

	loading_layer.queue_free()
	hud.set_status("")
	level.lods.update(level.spawn_pos)
	ready_to_play = true
	print("%s ready · %d grindable lines%s" % [info.name, paths.size(), " · headset" if vr else ""])


# Starts OpenXR if there is a headset to talk to. Returns false (and the game plays on a flat screen) if there is not.
func _start_xr() -> bool:
	var xr := XRServer.find_interface("OpenXR")
	if xr == null:
		return false
	if not xr.is_initialized() and not xr.initialize():
		return false
	get_viewport().use_xr = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # the headset sets the pace
	if xr.has_method("get_available_display_refresh_rates"):
		var rates = xr.call("get_available_display_refresh_rates")
		if rates is Array and REFRESH_RATE in rates:
			xr.set("display_refresh_rate", REFRESH_RATE)
	return true


static func _make_controller(tracker: StringName) -> XRController3D:
	var controller := XRController3D.new()
	controller.tracker = tracker
	controller.name = String(tracker)
	return controller


func _process(delta: float) -> void:
	if not ready_to_play:
		return
	var dt := minf(delta, 0.05)
	# Holding both grips must not re-centre you while you are in the air.
	input.block_recenter = sim.mode == Skater.Mode.AIR
	var command := input.poll(dt)
	if vr:
		command.body_y = camera.position.y if rig_control.calibrated else NAN
		# In the headset the hands balance grinds and manuals: right hand up pushes the meter right, left hand up pushes it left. The
		# neutral hand position is only learned while rolling relaxed on the ground, not through a crouch, pop or flight.
		var relaxed := sim.mode == Skater.Mode.GROUND and sim.manual == null and sim.grounded_time > 0.4 and absf(sim.crouch) < 0.06 and not command.jump
		var left = left_controller.position if left_controller.get_has_tracking_data() else null
		var right = right_controller.position if right_controller.get_has_tracking_data() else null
		command.lean = hand_balance.update(dt, left, right, sim.balance != null, relaxed)
		# On rails, reverse the hand tilt: raising the right hand corrects left, and vice versa.
		if sim.mode == Skater.Mode.GRIND:
			command.lean *= -1.0
	if command.toggle_stance and sim.mode == Skater.Mode.GROUND and sim.speed < 2.0:
		sim.face_offset = -sim.face_offset
		hud.say("Goofy" if sim.goofy else "Regular", 1.0)
		if haptics:
			haptics.pulse(0.3, 25)
	if command.recenter:
		rig_control.request_calibration()
		hud.say("Recentred", 1.0)
		if haptics:
			haptics.pulse(0.4, 40)
	if command.to_spawn:
		sim.respawn(sim.spawn)
	sim.update(command, dt)
	rig_control.update(dt)
	level.lods.update(camera.global_position)
	board_view.update(sim, dt)
	hud.update(dt)
	if vr_gauge:
		vr_gauge.update(sim, hud.message, hud.message_time, rig_control.anchor, rig_control.yaw_cal)
	sfx.update(sim, dt)
	if haptics:
		haptics.continuous(sim)


func _unhandled_input(event: InputEvent) -> void:
	# Flat-screen look-around: drag the mouse (or a finger).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
	elif event is InputEventMouseMotion and dragging and rig_control != null:
		rig_control.turn_view(event.relative.x, event.relative.y)
	elif event is InputEventScreenDrag and rig_control != null:
		rig_control.turn_view(event.relative.x, event.relative.y)


# What the skater just did: sounds, buzzes in the hands, and the trick names on the screen.
func _on_sim_event(type: String, data: Dictionary) -> void:
	sfx.event(type, data)
	if haptics:
		haptics.event(type, data)
	match type:
		"flipStart":
			hud.say(data.name, 1.6)
		"flip":
			hud.say(data.name, 1.1)
		"sketchy":
			hud.say("Sketchy", 0.9)
		"manualEnd":
			if data.reason != "bail" and data.time > 0.5:
				hud.say("%s  %.1fs" % [data.name, data.time])
		"grindEnd":
			if data.reason != "bail" and data.time > 0.3:
				hud.say("%s  %.1fs" % [data.name, data.time])
		"bail":
			hud.say("BAIL", 1.2)
		"loopEnd":
			if data.completed:
				hud.say("LOOP!", 1.6)
		"detach":
			hud.say("Board off", 0.7)
		"catch":
			if data.quality == "sketchy":
				hud.say("Sketchy catch", 0.8)


# Sky, sun, fog and exposure for the level (its `look` in levels.gd).
func _build_environment(look: Dictionary) -> void:
	var sun_dir := Vector3(look.sunDirection[0], look.sunDirection[1], look.sunDirection[2]).normalized()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("2f6fbf")
	sky_material.sky_horizon_color = Color(look.fog)
	sky_material.ground_horizon_color = Color(look.fog)
	sky_material.ground_bottom_color = Color("a9b5b5")
	sky_material.sky_curve = 0.18
	sky_material.sun_angle_max = 32.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2 * float(look.hemisphere) + 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = look.exposure
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(look.fog)
	env.fog_depth_begin = look.fogNear
	env.fog_depth_end = look.fogFar
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(look.sunColor)
	sun.light_energy = 1.5
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO)
