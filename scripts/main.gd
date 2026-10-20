# The game: loads the level, puts the skater on it, and runs the frame loop. In a headset (OpenXR) the player stands on the board
# and the Quest controllers drive it; otherwise it plays on a flat screen with a keyboard or gamepad.
extends Node3D

const CONTROLS_HINT := "W push · S brake · A/D steer & balance · hold Space to crouch, release to ollie · G or Shift to grind · F in the air + A/D: kickflip / heelflip, S: shove-it, S+A / S+D: varial kickflip / heelflip · flick W-S for a manual · drag to look · hold R: back to the entrance · Z stance · hold L: back home\nGamepad: left stick, A ollie, B flip, right trigger grind, Y stance, hold X entrance\nHeadset: hold the left menu button to go back home"
const REFRESH_RATE := 72.0   # Hz the headset is asked to run at
const LEVEL_SWITCH_HOLD := 0.8   # seconds the menu button (L on a keyboard) is held to go home (or, at home, to the next level)
const STEP_OFF_HOLD := 0.6       # seconds the right stick is held down (Q on a keyboard: a tap) to step off the board
const HUB_HINT := "W A S D walk · drag to look · near the TV: E picks up the remote, left / right change the level, Enter plays · Q steps on the board (and off it again) · hold L: next level\nHeadset: left stick walks, right stick turns smoothly, squeeze a grip by the remote, stick left / right changes the level, trigger plays · right A steps on the board · hold the right stick down to step off · hold the left menu button for the next level"

var level_id := ""               # a test can set it before the scene is added; `-- level=<id>` on the command line does too; empty: the house
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
var score := Score.new()
var sfx: Sfx
var music: Music
var haptics: Haptics
var vr_gauge: VrGauge
var hands: VrHands
var grab: BoardGrab
var run: Run                     # a timed run (null in a level without one)
var face_card: FaceCard
var watch: Watch                 # on the left wrist (headset only)
var watch_menu: WatchMenu
var aim_controller: XRController3D   # the right hand's pointing pose, for the menu's laser
var menu_key_was := false
var menu_escape_was := false
var detach_was := false
var hand_balance := HandBalance.new()
var input := SkateInput.new()
var ready_to_play := false
var dragging := false
var held_level_switch := 0.0
var switching := false
var hub: Hub                     # the house (null in every other level)
var foot: FootMode
var on_foot := false
var flat_remote_held := false
var held_step_off := 0.0
var step_key_was := false
var remote_key_was := false
var step_on_guard := false       # right A stepped you on: it must be let go before it can mean "jump"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("level=") and Levels.LEVELS.has(arg.substr(6)):
			level_id = arg.substr(6)
	if level_id == "":
		level_id = Levels.take_next()
	info = Levels.LEVELS[level_id]
	vr = _start_xr()
	_build_environment(info.look, info.get("night", {}))
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

	if level_id == Levels.HUB:
		level = LevelLoader.from_root(Hub.build_root(), self)
	else:
		level = LevelLoader.load_level(info.file, self, info.get("decals", ""))
	if level == null:
		loading.text = "The park could not load."
		push_error("Could not load " + info.file)
		return
	if info.has("night"):
		Night.apply(self, level, info.night)
	# The collision bodies are only seen by the physics server after a physics step.
	await get_tree().physics_frame
	await get_tree().physics_frame
	world = SkateWorld.new(get_world_3d().direct_space_state)
	var paths := GrindPath.parse(level.grind_nodes)
	var loops := LoopPath.parse(level.loop_nodes)
	sim = Skater.new(world, paths, loops, info.bounds, true)
	sim.set_spawn(level.spawn_pos, level.spawn_heading)
	sim.event.connect(_on_sim_event)

	hud = Hud.new(self, sim, info.name, (HUB_HINT if level_id == Levels.HUB else CONTROLS_HINT) + "\n\n" + info.blurb)
	score.chain_changed.connect(_on_chain_changed)
	score.banked.connect(_on_banked)
	rig_control = PlayerRig.new(rig, camera, sim, hud.fade_rect, vr)
	if vr:
		vr_gauge = VrGauge.new(rig)
	var model := (load("res://assets/board/skateboard.glb") as PackedScene).instantiate() as Node3D
	board_view = BoardView.new(self, model)
	hands = VrHands.new({"left": left_controller, "right": right_controller} if vr else {})
	grab = BoardGrab.new(hands, board_view.root, camera, haptics)
	grab.event.connect(_on_sim_event)
	watch_menu = WatchMenu.new(self, vr, level_id == Levels.HUB, info.name)
	watch_menu.chosen.connect(_on_menu_chosen)
	watch_menu.hovered.connect(func() -> void:
		if haptics:
			haptics.pulse(0.15, 12, "right"))
	if vr:
		var left_hand := _hand_state("left")
		if left_hand != null:
			watch = Watch.new(left_hand.model)
		aim_controller = _make_controller(&"right_hand")
		aim_controller.pose = &"aim"
		aim_controller.name = "right_aim"
		rig.add_child(aim_controller)
	if info.has("run"):
		run = Run.new(info.run)
		run.build_gates(self)
		face_card = FaceCard.new(vr, camera, hud.layer)
		sim.bail_to_spawn = true   # (a bail in a run starts it all again from the top: the clock, the score and you)
		_show_time()
	sfx = Sfx.new(world)
	sfx.name = "Sfx"
	add_child(sfx)
	music = Music.new()
	music.name = "Music"
	add_child(music)
	music.start()

	if level_id == Levels.HUB:
		hub = Hub.new(level, self, vr)
		if hub.tv != null:
			hub.tv.chosen.connect(_go_to)
		foot = FootMode.new(rig, camera, world, vr)
		_stand_up(level.spawn_pos, level.spawn_heading)

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
	if not ready_to_play or switching:
		return
	var dt := minf(delta, 0.05)
	# Hold the left menu button (L on a keyboard) to go home; at home, on to the next level.
	var level_key := Input.is_key_pressed(KEY_L) or (vr and left_controller.is_button_pressed("menu_button"))
	held_level_switch = held_level_switch + dt if level_key else 0.0
	if held_level_switch > LEVEL_SWITCH_HOLD:
		_go_to(Levels.next_channel(Levels.saved()) if hub != null else Levels.HUB)
		return
	if _menu_asked():
		_set_menu(not watch_menu.is_open)
	if watch_menu.is_open:
		_process_menu(dt)
		return
	if on_foot:
		_process_foot(dt)
		return
	# Holding both grips must not re-centre you while you are in the air.
	input.block_recenter = sim.mode == Skater.Mode.AIR or grab.holding()
	var command := input.poll(dt)
	command.grabbing = grab.holding()   # grabbing lets the stick flip you over (backflip / frontflip)
	if vr:
		command.body_y = camera.position.y if rig_control.calibrated else NAN
		# In the headset the hands balance grinds and manuals: right hand up pushes the meter right, left hand up pushes it left. The
		# neutral hand position is only learned while rolling relaxed on the ground, not through a crouch, pop or flight.
		var relaxed := sim.mode == Skater.Mode.GROUND and sim.manual == null and sim.grounded_time > 0.4 and absf(sim.crouch) < 0.06 and not command.jump
		var grips := hands.grip_positions()
		command.lean = hand_balance.update(dt, grips.left, grips.right, sim.balance != null, relaxed)
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
	if hub != null:
		_hub_step_off(dt, command)
		if on_foot:
			return
	if step_on_guard:
		if command.jump:
			command.jump = false
		else:
			step_on_guard = false
	if command.to_spawn:
		if hub != null:
			_stand_up(level.spawn_pos, level.spawn_heading)
			return
		sim.respawn(sim.spawn)
	var before := sim.pos
	sim.update(command, dt)
	if run != null:
		_update_run(dt, before)
	rig_control.update(dt)
	level.lods.update(camera.global_position)
	board_view.update(sim, dt)
	var airborne := sim.mode == Skater.Mode.AIR and sim.flip == null and sim.shuv == null
	grab.update(dt, airborne)      # the board comes up to a squeezing hand once the current trick has finished...
	grab.hold_board(sim, dt)       # ...or, taken off your feet, is wherever your hand has it
	# Left trigger: squeeze it to take the board off your feet, let go to catch it (a miss leaves it in your hand: squeeze and let go again).
	if command.detach and not detach_was and grab.off == null:
		grab.toggle_off(sim, vr)
	if not command.detach and detach_was and grab.off != null:
		grab.toggle_off(sim, vr)
	detach_was = command.detach
	hands.update(dt)
	grab.place()                   # ...then each holding hand is fitted onto its edge (after the hands have posed)
	hud.update(dt)
	if face_card != null:
		face_card.update(dt)
	score.update(dt, sim.mode == Skater.Mode.GROUND and sim.balance == null, sim.mode == Skater.Mode.BAIL)
	if vr_gauge:
		vr_gauge.update(sim, hud.message, hud.message_time, rig_control.anchor, rig_control.yaw_cal)
	sfx.update(sim, dt)
	if haptics:
		haptics.continuous(sim)


# The run's clock, and what happens at its gates.
func _update_run(dt: float, before: Vector3) -> void:
	var happened := run.update(dt, before, sim.pos)
	if happened == "start":
		score.reset()
		_show_score()
		face_card.show_card("GO!", [], 1.0)
		if haptics:
			haptics.pulse(0.6, 80)
	elif happened == "finish":
		run.final_score = score.total + score.chain_points()   # (a trick still in the air as you go over counts)
		face_card.show_card("FINISH", ["TIME  " + Run.format_time(run.time), "SCORE  " + Score.format(run.final_score)], 12.0)
		_show_score(run.final_score)
		if haptics:
			haptics.pulse(0.8, 150)
	_show_time()


func _restart_run() -> void:
	run.reset()
	score.reset()
	face_card.hide_card()
	_show_score()


func _show_time() -> void:
	var text := Run.format_time(run.time)
	hud.set_time(text)
	if watch != null:
		watch.set_time(text)


func _show_score(total := -1) -> void:
	var shown := score.total if total < 0 else total
	hud.set_score(shown)
	if watch != null:
		watch.set_score(shown)


# M on a keyboard, or a tap of the right index finger on the watch's glass.
func _menu_asked() -> bool:
	var key := Input.is_key_pressed(KEY_M)
	var asked := key and not menu_key_was
	menu_key_was = key
	if watch_menu.is_open and not vr:
		var escape := Input.is_key_pressed(KEY_ESCAPE)
		asked = asked or (escape and not menu_escape_was)
		menu_escape_was = escape
	var right := _hand_state("right")
	if watch != null and right != null:
		# (a hand that is holding the board, or squeezing, is not tapping anything)
		var open_hand := right.trigger() < 0.3 and right.squeeze() < 0.3 and not grab.holding()
		if watch.update(right.model.index_tip()) and (open_hand or watch_menu.is_open):
			asked = true
	return asked


func _set_menu(open: bool) -> void:
	if open == watch_menu.is_open:
		return
	if open:
		watch_menu.open(camera.global_transform)
	else:
		watch_menu.close()
	var right := _hand_state("right")
	if right != null:
		right.pointing = open
	if haptics:
		haptics.pulse(0.35, 30)


# The game is paused while the menu is up: the hands still move, so you can point.
func _process_menu(dt: float) -> void:
	hands.update(dt)
	sfx.hush(dt)
	if vr:
		var pointer: Node3D = aim_controller if aim_controller.get_has_tracking_data() else right_controller
		watch_menu.update(pointer.global_position, -pointer.global_basis.z, right_controller.is_button_pressed("trigger_click"))


func _on_menu_chosen(action: String) -> void:
	match action:
		"resume":
			_set_menu(false)
		"retry":
			_go_to(level_id)
		"home":
			_go_to(Levels.HUB)
		"exit":
			get_tree().quit()


func _turn_view(dx: float, dy: float) -> void:
	if on_foot:
		foot.turn_view(dx, dy)
	else:
		rig_control.turn_view(dx, dy)


# Off to another scene (a level, or home): remembered, then the whole scene is loaded again.
func _go_to(id: String) -> void:
	if switching:
		return
	switching = true
	Levels.go_to(id)
	get_tree().reload_current_scene()


# Stand up in the house at `pos` facing `yaw` (a sim heading), the board put away.
func _stand_up(pos: Vector3, yaw: float) -> void:
	on_foot = true
	flat_remote_held = false
	foot.place(pos, yaw)
	board_view.root.visible = false
	board_view.shadow.visible = false
	grab.release_all()
	hud.speed_label.visible = false


# Drop the board in front of you and step on it.
func _step_on() -> void:
	var yaw := foot.facing()
	var at := foot.body() + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.7
	var hit := world.ground(at.x, at.z, foot.floor_y + 0.4, SkateWorld.Hit.new(), 3.0)
	at = foot.body() if hit == null else Vector3(at.x, hit.y, at.z)
	var where := Skater.SpawnPoint.new()
	where.pos = at
	where.heading = yaw
	sim.respawn(where)
	on_foot = false
	step_on_guard = true
	board_view.root.visible = true
	hud.speed_label.visible = true
	rig_control.request_calibration()


# While riding in the house: step off (a tap of Q, or the right stick held down) once you are rolling slowly on the ground.
func _hub_step_off(dt: float, command: Skater.Command) -> void:
	var held := false
	var tapped := Input.is_key_pressed(KEY_Q) and not step_key_was
	step_key_was = Input.is_key_pressed(KEY_Q)
	if vr:
		held = right_controller.is_button_pressed("primary_click")
	held_step_off = held_step_off + dt if held else 0.0
	if (tapped or held_step_off > STEP_OFF_HOLD) and sim.mode == Skater.Mode.GROUND and sim.speed < 2.0:
		held_step_off = -1e9
		_stand_up(sim.pos, sim.heading)


func _hand_state(handedness: String) -> VrHands.HandState:
	for s in hands.states:
		if s.handedness == handedness:
			return s
	return null


# Walking about the house: the TV and its remote, and stepping onto the board.
func _process_foot(dt: float) -> void:
	var move := Vector2.ZERO
	var turn := 0.0
	var pointers: Array = []
	var step_on := false
	var q_pressed := Input.is_key_pressed(KEY_Q)
	if vr:
		var left_stick := left_controller.get_vector2("primary")
		var right_stick := right_controller.get_vector2("primary")
		var holder: String = hub.tv.holder if hub.tv != null else ""
		move = Vector2.ZERO if holder == "left" else left_stick
		turn = 0.0 if holder == "right" else right_stick.x
		for pair in [["left", left_controller], ["right", right_controller]]:
			var c: XRController3D = pair[1]
			pointers.append({"id": pair[0], "node": c, "state": _hand_state(pair[0]), "pos": c.global_position, "squeeze": c.is_button_pressed("grip_click"),
				"stick_x": c.get_vector2("primary").x, "trigger": c.is_button_pressed("trigger_click")})
		step_on = right_controller.is_button_pressed("ax_button") and holder != "right" and not step_on_guard
		if not right_controller.is_button_pressed("ax_button"):
			step_on_guard = false
	else:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
		var e_pressed := Input.is_key_pressed(KEY_E)
		if e_pressed and not remote_key_was:
			flat_remote_held = not flat_remote_held
		remote_key_was = e_pressed
		step_on = q_pressed and not step_key_was
		step_key_was = q_pressed
		pointers.append({"id": "key", "node": camera, "pos": camera.global_position, "squeeze": flat_remote_held,
			"stick_x": float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
			"trigger": Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)})
	foot.update(dt, move, turn)
	hands.update(dt)               # (the hands first: the remote follows the one that holds it)
	if hub.tv != null:
		hub.tv.update(pointers)
		if hub.tv.holder == "":
			flat_remote_held = false
		elif not vr:
			hud.say("Remote: left / right change the level · Enter plays · E puts it down", 0.3)
	hud.update(dt)
	if step_on and foot.placed:
		_step_on()


func _unhandled_input(event: InputEvent) -> void:
	# Flat-screen look-around: drag the mouse (or a finger).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
	elif event is InputEventMouseMotion and dragging and rig_control != null:
		_turn_view(event.relative.x, event.relative.y)
	elif event is InputEventScreenDrag and rig_control != null:
		_turn_view(event.relative.x, event.relative.y)


# What the skater just did: sounds, buzzes in the hands, and the trick names on the screen.
func _on_sim_event(type: String, data: Dictionary) -> void:
	sfx.event(type, data)
	if haptics:
		haptics.event(type, data)
	if type == "respawn" and run != null and face_card != null and sim.pos.distance_to(sim.spawn.pos) < 1.0:
		_restart_run()   # (back on the start spot: the run begins again from nothing)
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
		"catchMiss":
			hud.say("Missed it", 0.6)
		"dropBoard":
			hud.say("Dropped it", 0.9)
		"grabEnd":
			if data.time > 0.3:
				hud.say("%s  %.1fs" % [data.name, data.time])
		"catch":
			if data.quality == "sketchy":
				hud.say("Sketchy catch", 0.8)
	score.event(type, data)   # (after the names above: when a trick scores, its points replace the flash)


# A trick joined the chain: the chain so far and what it is worth.
func _on_chain_changed(text: String, points: int) -> void:
	hud.say("%s   %s" % [text, Score.format(points)], 2.0)


# The chain was landed and rolled out.
func _on_banked(points: int, total: int) -> void:
	if run == null or run.state != Run.State.DONE:
		_show_score()   # (the finished run's score stays put)
	hud.say("+%s   Total %s" % [Score.format(points), Score.format(total)], 2.0)


# Sky, sun, fog and exposure for the level (its `look` in levels.gd). `night` is the level's night settings, if it has them.
func _build_environment(look: Dictionary, night := {}) -> void:
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
	if not night.is_empty():
		sky = Night.make_sky(look, night)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2 * float(look.hemisphere) + 0.3
	if look.has("ambient"):   # a colour mixed into the sky's light (the house: warmer than the blue sky)
		env.ambient_light_color = Color(look.ambient)
		env.ambient_light_sky_contribution = look.get("ambientSky", 0.5)
	if not night.is_empty():
		Night.light_environment(env)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES if look.get("toneMapping", "") == "aces" else Environment.TONE_MAPPER_LINEAR
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
	sun.light_energy = float(look.sun) * 1.5 / 3.4   # (3.4 is the sun the first levels were tuned with)
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at_from_position(sun_dir * 100.0, Vector3.ZERO)
