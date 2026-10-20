# Turns the Quest controllers, a keyboard or a gamepad into the things the skater cares about.
#   left stick / W S A D   up = push, down = brake, sideways = steer / air spin / grind balance
#   right A / Space / pad A       hold to crouch, release to ollie
#   right trigger / G or Shift / pad right trigger   grind: press it once; the rail or coping the board touches in the next moment is caught
#   right B / F + stick / pad B   (Tony Hawk style, trick_controls.gd) left/right = kickflip/heelflip, down = shove-it,
#                                 down-left/down-right = varial kickflip/heelflip; up does nothing
#   left trigger / C / pad left trigger   in the air while holding the board in a grab: take the board off your feet
#   left Y / Z / pad Y      switch stance
#   both grips held (on the ground)     stand on the board where you are (the headset only)
class_name SkateInput
extends RefCounted

const DEADZONE := 0.15

var held_recenter := 0.0
var key_stance_was := false
var pad_stance_was := false
var vr_stance_was := false
var command := Skater.Command.new()

# In the headset: the two XRController3D nodes (anything with is_button_pressed / get_vector2 will do). Null on a flat screen.
var vr_left = null
var vr_right = null
# Set by the game: while true, holding both grips does not re-centre (in the air, or while grabbing the board).
var block_recenter := false


static func deadzone(v: float) -> float:
	if absf(v) <= DEADZONE:
		return 0.0
	return (absf(v) - DEADZONE) / (1.0 - DEADZONE) * signf(v)


func poll(dt: float) -> Skater.Command:
	var c := command
	var steer := 0.0
	var drive := 0.0
	var jump := Input.is_key_pressed(KEY_SPACE)
	var flip := Input.is_key_pressed(KEY_F)
	var grind := Input.is_key_pressed(KEY_G) or Input.is_key_pressed(KEY_SHIFT)
	var detach := Input.is_key_pressed(KEY_C)
	steer += float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	drive += float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
	var key_stance := Input.is_key_pressed(KEY_Z)
	var toggle_stance := key_stance and not key_stance_was
	key_stance_was = key_stance
	var stick := Vector2(steer, -drive)   # on a keyboard the stick is the steer/drive keys
	var has_stick := false                # a real stick is driving the trick controls (gamepad or controller)
	var in_vr := vr_left != null and vr_right != null
	var left_squeeze := false
	var right_squeeze := false

	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var pad: int = pads[0]
		var x := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
		if absf(x) > DEADZONE or absf(y) > DEADZONE:
			has_stick = true
			steer += deadzone(x)
			drive -= deadzone(y)
			stick = Vector2(x, y)
		jump = jump or Input.is_joy_button_pressed(pad, JOY_BUTTON_A)
		flip = flip or Input.is_joy_button_pressed(pad, JOY_BUTTON_B)
		grind = grind or Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		detach = detach or Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.5
		var pad_stance := Input.is_joy_button_pressed(pad, JOY_BUTTON_Y)
		toggle_stance = toggle_stance or (pad_stance and not pad_stance_was)
		pad_stance_was = pad_stance

	if in_vr:
		# In the headset, trick controls come exclusively from the left controller and right B: no keyboard can change them.
		flip = false
		var s: Vector2 = vr_left.get_vector2("primary")
		steer += deadzone(s.x)
		drive += deadzone(s.y)               # a controller's stick has up = +y
		stick = Vector2(s.x, -s.y)           # …the trick stick works in screen terms: up = −y
		has_stick = true
		left_squeeze = vr_left.is_button_pressed("grip_click")
		var left_y: bool = vr_left.is_button_pressed("by_button")
		toggle_stance = toggle_stance or (left_y and not vr_stance_was)
		vr_stance_was = left_y
		detach = detach or vr_left.is_button_pressed("trigger_click")
		jump = jump or vr_right.is_button_pressed("ax_button")                # right A
		grind = grind or vr_right.is_button_pressed("trigger_click")
		flip = flip or vr_right.is_button_pressed("by_button")                # right B
		right_squeeze = vr_right.is_button_pressed("grip_click")

	# Both grips held stands you on the board where you are.
	held_recenter = held_recenter + dt if (left_squeeze and right_squeeze and not block_recenter) else 0.0
	var recenter := false
	if held_recenter > 0.6:
		recenter = true
		held_recenter = -1e9

	c.steer = clampf(steer, -1.0, 1.0)
	c.drive = clampf(drive, -1.0, 1.0)
	# Balance comes from the hands in the headset (main sets it); on a flat screen the steer keys balance so it stays playable.
	c.lean = 0.0 if in_vr else c.steer
	c.jump = jump
	c.grind = grind
	c.flip = flip
	c.detach = detach
	c.recenter = recenter
	c.toggle_stance = toggle_stance
	c.grabbing = false
	c.body_y = NAN
	if has_stick:
		c.trick_stick = Vector2(clampf(stick.x, -1.0, 1.0), clampf(stick.y, -1.0, 1.0))
	else:
		c.trick_stick = Vector2(clampf(c.steer, -1.0, 1.0), clampf(-c.drive, -1.0, 1.0))
	return c
