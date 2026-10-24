# The game: loads the level, puts the skater on it, and runs the frame loop. In a headset (OpenXR) the player stands on the board
# and the Quest controllers drive it; otherwise it plays on a flat screen with a keyboard or gamepad.
extends Node3D

const CONTROLS_HINT := "W push · S brake · A/D steer & balance · hold Space to crouch, release to ollie · G or Shift to grind · F in the air + A/D: kickflip / heelflip, S: shove-it, S+A / S+D: varial kickflip / heelflip · flick W-S for a manual · drag to look · Z stance · Q step off the board (walk over it to step back on; Space jumps) · hold L: back home\nGamepad: left stick, A ollie, B flip, right trigger grind, Y stance\nHeadset: hold the left menu button to go back home · hold the right stick down to step off the board"
const REFRESH_RATE := 72.0   # Hz the headset is asked to run at
const LEVEL_SWITCH_HOLD := 0.8   # seconds the menu button (L on a keyboard) is held to go home (or, at home, to the next level)
const STEP_OFF_HOLD := 0.6       # seconds the right stick is held down (Q on a keyboard: a tap) to step off the board
const HUB_HINT := "W A S D walk · drag to look · near the TV: E picks up the remote, left / right change the level, Enter plays · Q steps off the board (walk over it to step back on), Space jumps · hold L: next level · M menu: build mode · walk up to the dirt bike to get on it: W throttle, S brake, A / D steer, Q off\nHeadset: left stick walks, right stick turns smoothly, squeeze a grip by the remote, stick left / right changes the level, trigger plays · right A jumps · squeeze a grip next to the board to pick it up · hold the right stick down to step off the board, walk over it to step on · walk up to the dirt bike to get on: squeeze the grips, twist the right one back for throttle, right trigger brakes, turn the bars or lean your body to steer, hold the right stick down to get off · hold the left menu button for the next level"

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
var park: ParkTimer               # a park level's two-minute round (null in a level without one)
var goals: Goals                  # the park level's goals (null in a level without any)
var grind_hand := "left"     # the hand that, raised, pushes the balance meter right (set in the menu)
var manual_hand := "left"
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
var build: BuildMode             # moving things about the house, or the Slab (null in every other level)
var ride: BikeRide               # riding a dirt bike (null when not)
var bike_sound: BikeSound
var bike_armed := true           # walking up to a bike gets you on, but only once you have been away from one since you got off
var bike_apart := 0.0
var foot: FootMode
var on_foot := false
var flat_remote_held := false
var held_step_off := 0.0
var step_key_was := false
var remote_key_was := false
var step_on_guard := false       # right A stepped you on: it must be let go before it can mean "jump"
var prop: BoardProp              # the board when it is not under you: lying about, or in a hand
var carry: BoardCarry
var prop_armed := true           # walking over the board steps you on, but only once you have been off it since you got off
var prop_apart := 0.0            # seconds you have been away from it
var jump_was := false
var detach_foot_was := false

const STEP_ON_HALF_WIDTH := 0.13    # metres: the middle of your body has to be this close to the board's middle line...
const STEP_ON_HALF_LENGTH := 0.42   # ...and this close to its middle,
const STEP_ON_HEIGHT := 0.3         # at about the board's height,
const STEP_ON_MAX_SPEED := 1.5      # with the board wheels down and not rolling away faster than this
const STEP_ON_REARM := 0.25         # and you have to have been off it this long since you got off or put it down


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
	elif level_id == Levels.SLAB:
		level = LevelLoader.from_root(Slab.build_root(), self)
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
		vr_gauge = VrGauge.new(camera)
	var model := (load("res://assets/board/skateboard.glb") as PackedScene).instantiate() as Node3D
	board_view = BoardView.new(self, model)
	hands = VrHands.new({"left": left_controller, "right": right_controller} if vr else {})
	grab = BoardGrab.new(hands, board_view.root, camera, haptics)
	grab.event.connect(_on_sim_event)
	foot = FootMode.new(rig, camera, world, vr)
	prop = BoardProp.new(world)
	carry = BoardCarry.new(hands, grab, board_view.root)
	carry.released.connect(_on_board_released)
	if info.has("goals"):
		goals = Goals.new(level_id, info.goals)
		goals.completed.connect(func(text: String) -> void: hud.say("Goal done: " + text, 3.5))
	watch_menu = WatchMenu.new(self, vr, level_id == Levels.HUB, info.name, goals != null, info.get("build", false))
	grind_hand = HandBalance.pushing_hand("grind")
	manual_hand = HandBalance.pushing_hand("manual")
	watch_menu.set_hands(grind_hand, manual_hand)
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
	if info.has("bail_ground"):
		sim.bail_ground = PackedStringArray(info.bail_ground)
	if info.has("run"):
		run = Run.new(info.run)
		run.build_gates(self, world)
		face_card = FaceCard.new(vr, camera, hud.layer)
		sim.bail_to_spawn = true   # (a bail in a run starts it all again from the top: the clock, the score and you)
		_show_time()
	if info.has("timer"):
		park = ParkTimer.new(float(info.timer))
		face_card = FaceCard.new(vr, camera, hud.layer)
		_show_park_time()
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
	if level_id == Levels.HUB or info.get("build", false):   # (you start on foot in a level you can build in)
		build = BuildMode.new(level, get_world_3d().direct_space_state, self, vr)
		bike_sound = BikeSound.new()
		bike_sound.name = "BikeSound"
		add_child(bike_sound)
		var back := BuildMode.take_come_back()   # (the level was loaded again by build mode: you stay where you were)
		if back.is_empty():
			_stand_up(level.spawn_pos, level.spawn_heading)
		else:
			_stand_up(back.pos, back.yaw)
			if back.get("building", false):
				_start_building()
				_set_menu(true)

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
	if bike_sound != null:
		bike_sound.update(dt, ride.bike if ride != null else null)
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
	if build != null and build.active:
		_process_build(dt)
		return
	if ride != null:
		_process_bike(dt)
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
		# In the headset the hands balance grinds and manuals: the hand chosen in the menu (for each) pushes the meter right when it
		# is raised, the other pushes it left. The neutral is wherever the hands are when the grind or manual starts.
		var grips := hands.grip_positions()
		var hand: String = grind_hand if sim.mode == Skater.Mode.GRIND else manual_hand
		command.lean = hand_balance.update(dt, grips.left, grips.right, sim.balance != null) * HandBalance.sign_for(hand)
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
	_step_off(dt)
	if on_foot:
		return
	if step_on_guard:
		if command.jump:
			command.jump = false
		else:
			step_on_guard = false
	var before := sim.pos
	sim.update(command, dt)
	if run != null:
		_update_run(dt, before)
	if park != null:
		_update_park(dt)
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
		vr_gauge.update(sim, hud.message, hud.message_time)
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
		var lines := ["TIME  " + Run.format_time(run.time), "SCORE  " + Score.format(run.final_score)]
		if run.has_marks():   # (with pass marks, each line shows what you did / what was needed)
			lines = ["TIME  %s / %s" % [Run.format_time(run.time), Run.format_time(run.pass_time)],
				"SCORE  %s / %s" % [Score.format(run.final_score), Score.format(run.pass_score)]]
		face_card.show_card("PASSED" if run.passed() else "FINISH", lines, 12.0)
		_show_score(run.final_score)
		if haptics:
			haptics.pulse(0.8, 150)
	_show_time()


# The park round's clock, and what happens as it starts and ends.
func _update_park(dt: float) -> void:
	var moving := sim.speed > 1.0 or sim.mode != Skater.Mode.GROUND
	var happened := park.update(dt, moving)
	if happened == "start":
		score.reset()
		_show_score()
		face_card.show_card("GO!", [], 1.0)
		if haptics:
			haptics.pulse(0.6, 80)
	elif happened == "end":
		var final_score := score.total + score.chain_points()   # (a trick still in the air as time runs out counts)
		if goals != null:
			goals.check_total(final_score)
		var lines := ["SCORE  " + Score.format(final_score)]
		if goals != null:
			lines.append("GOALS  %d / %d" % [goals.done_count(), goals.list.size()])
		face_card.show_card("TIME UP", lines, ParkTimer.RESULT_SECONDS)
		_show_score(final_score)
		if haptics:
			haptics.pulse(0.8, 150)
	elif happened == "again":
		face_card.hide_card()
		score.reset()
		_show_score()
	_show_park_time()


func _show_park_time() -> void:
	var text := park.text()
	hud.set_time(text)
	if watch != null:
		watch.set_time(text)


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
		if goals != null:
			watch_menu.set_goals(goals.lines())
		if build != null:
			build.hide()
		watch_menu.open(camera.global_transform)
	else:
		watch_menu.close()
	var right := _hand_state("right")
	if right != null:
		right.pointing = open or (build != null and build.active)   # (building, the right hand points too)
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
		"grind_hand":
			grind_hand = HandBalance.other_hand(grind_hand)
			HandBalance.set_pushing_hand("grind", grind_hand)
			watch_menu.set_hands(grind_hand, manual_hand)
		"manual_hand":
			manual_hand = HandBalance.other_hand(manual_hand)
			HandBalance.set_pushing_hand("manual", manual_hand)
			watch_menu.set_hands(grind_hand, manual_hand)
		"exit":
			get_tree().quit()
		"build":
			_start_building()
		"build_resume":
			_set_menu(false)
		"add_arcade", "add_rail", "add_bike", "add_funbox", "add_quarter_pipe", "add_manual_pad", "add_flat_bar":
			_set_menu(false)
			var facing := foot.facing()
			build.add(action.substr(4), foot.body() + Vector3(-sin(facing), 0.0, -cos(facing)) * 1.5, facing)
		"build_done":
			HubLayout.write(build.layout(), level_id)
			_reload_house(false)
		"build_cancel":
			_reload_house(false)
		"build_reset":
			HubLayout.clear(level_id)
			_reload_house(true)


# Into build mode (from the menu, in the house or on the Slab): on foot, the menu turned to the build page.
func _start_building() -> void:
	if ride != null:
		_get_off_bike()
	if not on_foot:
		_stand_up(sim.pos, sim.heading, Transform3D(Basis(sim.board_quaternion(false)), sim.pos), sim.vel, true)
	build.start()
	watch_menu.set_building(true)


# Build mode is over (or starts again from the level as it was): the level is loaded again with you standing where you are.
func _reload_house(keep_building: bool) -> void:
	if ride != null:
		_get_off_bike()
	BuildMode.come_back = {"pos": foot.body(), "yaw": foot.facing(), "building": keep_building}
	_go_to(level_id)


# Building: walk about as on foot, and point to pick things up, carry them, turn them and put them down.
func _process_build(dt: float) -> void:
	var move := Vector2.ZERO
	var turn := 0.0
	var pointer: Node3D = camera
	var grab_down := false
	var turn_axis := 0.0
	var remove_down := false
	var fine := false
	if vr:
		move = left_controller.get_vector2("primary")
		turn_axis = right_controller.get_vector2("primary").x
		turn = turn_axis if build.held == null else 0.0   # (holding a piece, the stick turns it instead of you)
		pointer = aim_controller if aim_controller.get_has_tracking_data() else right_controller
		grab_down = right_controller.is_button_pressed("trigger_click")
		remove_down = right_controller.is_button_pressed("by_button")
		fine = right_controller.is_button_pressed("grip_click")
	else:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
		grab_down = Input.is_key_pressed(KEY_E)
		turn_axis = float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		remove_down = Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_DELETE)
		fine = Input.is_key_pressed(KEY_SHIFT)
	foot.update(dt, move, turn)
	hands.update(dt)
	var happened := build.update(pointer.global_position, -pointer.global_basis.z, grab_down, turn_axis, remove_down, fine, dt)
	var target := build.held if build.held != null else build.hovered
	match happened:
		"picked":
			hud.say("Carrying the %s · E puts it down · arrows turn it · hold Shift for fine control · X removes it" % build.piece_name(target).to_lower(), 2.5)
		"placed":
			hud.say("Put down · M: Done saves it", 2.0)
		"removed":
			hud.say("Removed", 1.2)
		"kept":
			hud.say("The house's own pieces can be moved, not removed", 2.0)
	if haptics and happened != "":
		haptics.pulse(0.2 if happened == "turned" else 0.45, 25, "right")
	if happened == "" and target != null and build.held == null and hud.message_time <= 0.0:
		hud.say("%s · E picks it up" % build.piece_name(target), 0.2)
	_board_on_foot(dt, false)
	level.lods.update(camera.global_position)
	sfx.hush(dt)
	hud.update(dt)


func _turn_view(dx: float, dy: float) -> void:
	if ride != null:
		ride.turn_view(dx, dy)
	elif on_foot:
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


# Stand up at `pos` facing `yaw` (a sim heading). With `put_board` the board is left where it was (its pose and how fast it was moving);
# without, it is put on the floor in front of you.
func _stand_up(pos: Vector3, yaw: float, board := Transform3D.IDENTITY, board_vel := Vector3.ZERO, put_board := false) -> void:
	on_foot = true
	flat_remote_held = false
	foot.place(pos, yaw)
	grab.release_all()
	hud.speed_label.visible = false
	if vr_gauge:
		vr_gauge.quad.visible = false
	if put_board:
		prop.place(board.origin, board.basis.orthonormalized().get_rotation_quaternion(), board_vel)
	else:
		_drop_board_in_front(pos, yaw)
	prop_armed = false
	prop_apart = 0.0
	jump_was = true   # (a button still down from before is not a jump)


# The board on the floor ahead of you, pointing the way you face.
func _drop_board_in_front(pos: Vector3, yaw: float) -> void:
	var at := pos + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.7
	var hit := world.ground(at.x, at.z, pos.y + 0.4, SkateWorld.Hit.new(), 3.0)
	at = pos if hit == null else Vector3(at.x, hit.y, at.z)
	prop.place(at + Vector3(0.0, 0.02, 0.0), Quaternion(Vector3.UP, yaw))


# Is the middle of your body over the board?
func _board_underfoot() -> bool:
	var body := foot.body()
	var local := prop.transform().affine_inverse() * body
	return absf(local.x) < STEP_ON_HALF_WIDTH and absf(local.z) < STEP_ON_HALF_LENGTH and absf(body.y - prop.origin().y) < STEP_ON_HEIGHT


# Walking over the board steps you on.
func _walk_over_board(dt: float) -> void:
	if carry.holding() or foot.air or not foot.placed:
		return
	if not _board_underfoot():
		prop_apart += dt
		if prop_apart > STEP_ON_REARM:
			prop_armed = true
		return
	prop_apart = 0.0
	if prop_armed and prop.upright() and prop.speed() < STEP_ON_MAX_SPEED:
		_step_on()


# Stand on the board where it lies, pointing the way it points.
func _step_on() -> void:
	var forward := prop.quat * Vector3(0, 0, -1)
	var where := Skater.SpawnPoint.new()
	where.pos = prop.origin()
	where.heading = Skater.yaw_of(forward.x, forward.z)
	sim.respawn(where)
	carry.drop_quietly()
	on_foot = false
	step_on_guard = true
	hud.speed_label.visible = true
	rig_control.request_calibration()


# In the air on foot with the board in your hand, the left trigger puts it under your feet: skating again, in mid-air, going the way you
# were. It has to be close enough to your feet and the right way up (the same test as catching a board you took off in the air).
func _catch_from_foot(pose: Transform3D) -> void:
	var feet := foot.body() - Vector3(0.0, Config.Board.deckTop, 0.0)
	var heading := foot.facing() - sim.face_offset   # (you face along the stance: the heading is a quarter turn from your gaze)
	var q := pose.basis.orthonormalized().get_rotation_quaternion()
	var verdict := BoardOff.judge_catch(pose.origin, q, feet, Quaternion(Vector3.UP, heading))
	if verdict.quality == "miss":
		if haptics:
			haptics.pulse(0.15, 20, carry.hand_name())
		return
	var velocity := foot.velocity()
	for state in hands.states:
		state.was_squeezed = state.squeeze() > 0.6   # (a grip still held is not a fresh grab)
	carry.drop_quietly()
	on_foot = false
	hud.speed_label.visible = true
	sim.start_from_foot(feet, velocity, heading, verdict.quality, verdict.reversed)
	rig_control.up = Vector3.UP
	rig_control.calibrate()
	if haptics:
		haptics.pulse(0.7, 60)


# The hand that held the board let go: it carries on with the hand's speed and spin.
func _on_board_released(pose: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	prop.place(pose.origin, pose.basis.orthonormalized().get_rotation_quaternion(), velocity, spin)
	prop_armed = not _board_underfoot()
	prop_apart = 0.0


# May this hand pick up the board? Not if it is holding the remote, or is by the remote and about to, or while building (the grip is
# fine control there).
func _may_carry(state: VrHands.HandState) -> bool:
	if build != null and build.active:
		return false
	if hub != null and hub.tv != null:
		if hub.tv.holder == state.handedness:
			return false
		if hub.tv.holder == "" and state.controller.global_position.distance_to(hub.tv.remote.global_position) < HubTv.PICK_DISTANCE:
			return false
	return true


# While riding: step off (a tap of Q, or the right stick held down) once you are rolling slowly on the ground. The board stays where it
# was, loose. Not in the middle of a timed run.
func _step_off(dt: float) -> void:
	var held := false
	var tapped := Input.is_key_pressed(KEY_Q) and not step_key_was
	step_key_was = Input.is_key_pressed(KEY_Q)
	if vr:
		held = right_controller.is_button_pressed("primary_click")
	held_step_off = held_step_off + dt if held else 0.0
	if not (tapped or held_step_off > STEP_OFF_HOLD):
		return
	if sim.mode == Skater.Mode.GROUND and sim.speed < 2.0 and sim.balance == null and not (run != null and run.state == Run.State.RUNNING):
		held_step_off = -1e9
		_stand_up(sim.pos, sim.heading, Transform3D(Basis(sim.board_quaternion(false)), sim.pos), sim.vel, true)


func _hand_state(handedness: String) -> VrHands.HandState:
	for s in hands.states:
		if s.handedness == handedness:
			return s
	return null


# Walking about on foot: the board, the TV and its remote (in the house), jumping, and the board in your hand.
func _process_foot(dt: float) -> void:
	var move := Vector2.ZERO
	var turn := 0.0
	var pointers: Array = []
	var jump := false
	var catch_pressed := false
	var holder: String = hub.tv.holder if hub != null and hub.tv != null else ""
	if vr:
		var left_stick := left_controller.get_vector2("primary")
		var right_stick := right_controller.get_vector2("primary")
		move = Vector2.ZERO if holder == "left" else left_stick
		turn = 0.0 if holder == "right" else right_stick.x
		for pair in [["left", left_controller], ["right", right_controller]]:
			var c: XRController3D = pair[1]
			pointers.append({"id": pair[0], "node": c, "state": _hand_state(pair[0]), "pos": c.global_position, "squeeze": c.is_button_pressed("grip_click"),
				"stick_x": c.get_vector2("primary").x, "trigger": c.is_button_pressed("trigger_click")})
		var a_pressed := right_controller.is_button_pressed("ax_button")
		jump = a_pressed and not step_on_guard
		if not a_pressed:
			step_on_guard = false
		catch_pressed = left_controller.is_button_pressed("trigger_click")
	else:
		move = Vector2(float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)), float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S)))
		var e_pressed := Input.is_key_pressed(KEY_E)
		if e_pressed and not remote_key_was:
			flat_remote_held = not flat_remote_held
		remote_key_was = e_pressed
		jump = Input.is_key_pressed(KEY_SPACE)
		pointers.append({"id": "key", "node": camera, "pos": camera.global_position, "squeeze": flat_remote_held,
			"stick_x": float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
			"trigger": Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER)})
	foot.update(dt, move, turn)
	if jump and not jump_was:
		foot.jump()
	jump_was = jump
	hands.update(dt)               # (the hands first: the remote follows the one that holds it)
	if hub != null and hub.tv != null:
		hub.tv.update(pointers)
		if hub.tv.holder == "":
			flat_remote_held = false
		elif not vr:
			hud.say("Remote: left / right change the level · Enter plays · E puts it down", 0.3)
	_board_on_foot(dt, catch_pressed)
	level.lods.update(camera.global_position)
	sfx.hush(dt)
	hud.update(dt)
	if on_foot:
		_walk_over_board(dt)
	if on_foot:
		_walk_to_bike(dt)


# Walking up to a bike (on foot, not carrying the board) gets you on it.
func _walk_to_bike(dt: float) -> void:
	if build == null or carry.holding() or foot.air or not foot.placed:
		return
	var near: Node3D = null
	for piece in build.pieces:
		if BuildPieces.info(piece).get("rideable", false) and BikeRide.reaches(piece, foot.body()):
			near = piece
	if near == null:
		bike_apart += dt
		if bike_apart > 0.3:
			bike_armed = true
		return
	bike_apart = 0.0
	if bike_armed:
		_get_on_bike(near)


func _get_on_bike(piece: Node3D) -> void:
	ride = BikeRide.new(DirtBike.new(piece, world, info.bounds), rig, camera, hands, vr)
	on_foot = false
	flat_remote_held = false
	held_step_off = 0.0
	step_key_was = Input.is_key_pressed(KEY_Q)
	bike_sound.start()
	hud.say("On the bike · W throttle · S brake · A / D steer · Q gets off" if not vr else "On the bike", 3.0)
	if haptics:
		haptics.pulse(0.5, 60)


func _get_off_bike() -> void:
	var spot := ride.end()
	ride = null
	bike_sound.stop()
	bike_armed = false
	bike_apart = 0.0
	foot.place(spot.pos, spot.yaw)
	on_foot = true
	jump_was = true
	hud.speed_label.visible = false


# Riding: the bike under you, your hands on its bars (headset), and getting off (as stepping off the board: the right stick held down,
# Q on a flat screen) once it has all but stopped.
func _process_bike(dt: float) -> void:
	var brake := 0.0
	var paddle := 0.0
	var throttle := 0.0
	var steer := 0.0
	if vr:
		brake = right_controller.get_float("trigger")
		paddle = left_controller.get_vector2("primary").y
	else:
		throttle = float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
		brake = float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
		steer = float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)) - float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
		if brake > 0.0 and absf(ride.bike.speed) < 0.3:
			paddle = -1.0   # (stopped, S walks it back)
			brake = 0.0
	var happened := ride.update(dt, brake, paddle, throttle, steer)
	hands.update(dt)
	ride.place_hands()
	if happened == "bail":
		hud.say("BAIL", 1.5)
		bike_sound.knock(9.0)
		if haptics:
			haptics.pulse(1.0, 150)
		ride.bike.stop_dead()
		_get_off_bike()
		return
	if happened == "land" or happened == "hit":
		bike_sound.knock(ride.bike.last_impact)
		if haptics:
			haptics.pulse(clampf(ride.bike.last_impact / 8.0, 0.2, 1.0), 70)
	elif happened == "shift" and haptics:
		haptics.pulse(0.25, 20, "right")
	if haptics and ride.holding("right"):
		haptics.rumble(0.04 + 0.12 * ride.bike.throttle, "right", 60.0)   # (the engine, through the bars)
	level.lods.update(camera.global_position)
	sfx.hush(dt)
	hud.update(dt)
	hud.speed_label.visible = true
	hud.speed_label.text = "%d km/h · gear %d" % [roundi(absf(ride.bike.speed) * 3.6), ride.bike.gear + 1]
	var tapped := Input.is_key_pressed(KEY_Q) and not step_key_was
	step_key_was = Input.is_key_pressed(KEY_Q)
	var held := vr and right_controller.is_button_pressed("primary_click")
	held_step_off = held_step_off + dt if held else 0.0
	if (tapped or held_step_off > STEP_OFF_HOLD) and absf(ride.bike.speed) < 2.0 and not ride.bike.air and ride.bike.wheelie < 0.05:
		held_step_off = -1e9
		_get_off_bike()


# The board while you are on foot: lying about (its physics), or in your hand (it follows the hand).
func _board_on_foot(dt: float, catch_pressed: bool) -> void:
	var pose := carry.update(dt, prop.transform(), _may_carry)
	if carry.holding():
		prop.place(pose.origin, pose.basis.orthonormalized().get_rotation_quaternion())
	else:
		prop.step(dt)
		if prop.lost():
			_drop_board_in_front(foot.body(), foot.facing())
		pose = prop.transform()
	board_view.show_at(world, pose)
	carry.place()                  # (the board fits the tracked hand; carrying never rotates the visible wrist)
	if catch_pressed and not detach_foot_was and carry.holding() and foot.air:
		_catch_from_foot(pose)
	detach_foot_was = catch_pressed


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
	if goals != null and (park == null or park.counting()):
		goals.check_total(total)   # (after the message above: a goal reached replaces it; once a round is over the result is settled)


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
	if look.has("panorama") and ResourceLoader.exists(look.panorama):   # a rendered 360° backdrop instead (tools/build_*_panorama.py)
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = load(look.panorama)
		panorama.energy_multiplier = 1.0 / float(look.exposure)   # the image is already exposed: shown as rendered
		sky.sky_material = panorama
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
