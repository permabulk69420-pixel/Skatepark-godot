# Turns the keyboard (or a gamepad) into the things the skater cares about; Quest controllers will join these later.
#   left stick / W S A D   up = push, down = brake, sideways = steer / air spin / grind balance
#   A button / Space        hold to crouch, release to ollie
#   right trigger / G or Shift   grind: press it once; the rail or coping the board touches in the next moment is caught
#   B button / F + stick    (Tony Hawk style, trick_controls.gd) left/right = kickflip/heelflip, down = shove-it,
#                           down-left/down-right = varial kickflip/heelflip; up does nothing
#   left trigger / C        in the air while holding the board in a grab: take the board off your feet
#   Y / Z                   switch stance        X held / R held: back to the entrance
class_name SkateInput
extends RefCounted

const DEADZONE := 0.15

var held_spawn := 0.0
var key_stance_was := false
var pad_stance_was := false
var command := Skater.Command.new()


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
	var spawn_held := Input.is_key_pressed(KEY_R)
	var stick := Vector2(steer, -drive)   # on a keyboard the stick is the steer/drive keys
	var has_pad := false

	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var pad: int = pads[0]
		var x := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
		if absf(x) > DEADZONE or absf(y) > DEADZONE:
			has_pad = true
			steer += deadzone(x)
			drive -= deadzone(y)
			stick = Vector2(x, y)
		jump = jump or Input.is_joy_button_pressed(pad, JOY_BUTTON_A)
		flip = flip or Input.is_joy_button_pressed(pad, JOY_BUTTON_B)
		grind = grind or Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT) > 0.5
		detach = detach or Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT) > 0.5
		spawn_held = spawn_held or Input.is_joy_button_pressed(pad, JOY_BUTTON_X)
		var pad_stance := Input.is_joy_button_pressed(pad, JOY_BUTTON_Y)
		toggle_stance = toggle_stance or (pad_stance and not pad_stance_was)
		pad_stance_was = pad_stance

	# Held R (or X) takes you back to the entrance.
	held_spawn = held_spawn + dt if spawn_held else 0.0
	var to_spawn := false
	if held_spawn > 0.8:
		to_spawn = true
		held_spawn = -1e9

	c.steer = clampf(steer, -1.0, 1.0)
	c.drive = clampf(drive, -1.0, 1.0)
	# Balance comes from the hands in VR; on a flat screen the steer keys balance so it stays playable for testing.
	c.lean = c.steer
	c.jump = jump
	c.grind = grind
	c.flip = flip
	c.detach = detach
	c.to_spawn = to_spawn
	c.toggle_stance = toggle_stance
	c.recenter = false
	c.grabbing = false
	c.body_y = NAN
	if has_pad:
		c.trick_stick = Vector2(clampf(stick.x, -1.0, 1.0), clampf(stick.y, -1.0, 1.0))
	else:
		c.trick_stick = Vector2(clampf(c.steer, -1.0, 1.0), clampf(-c.drive, -1.0, 1.0))
	return c
