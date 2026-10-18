# Flip tricks: press B and push the left stick, in either order. The trick fires the instant both are there.
#
#      up-left    up    up-right        (the three upward directions do nothing)
#        left     ·     right           Kickflip / Heelflip
#   down-left   down   down-right       Varial Kickflip / Pop Shove-it / Varial Heelflip
#
# Eight equal 45° directions. Stick coordinates are the raw controller axes: left = -x, right = +x, up = -y, down = +y.
# A trick's "flip" is null (no flip), true (kickflip) or false (heelflip); "shuv" is null (none), true (backside) or false.
class_name TrickControls
extends RefCounted

const T = Config.Tuning

const TRICKS := {
	"left": {"name": "Kickflip", "flip": true, "shuv": null},
	"right": {"name": "Heelflip", "flip": false, "shuv": null},
	"down": {"name": "Pop Shove-it", "flip": null, "shuv": true},
	"down-left": {"name": "Varial Kickflip", "flip": true, "shuv": true},
	"down-right": {"name": "Varial Heelflip", "flip": false, "shuv": false},
}

var held := false             # B down last frame
var press_age := INF          # time since B was pressed, while it is waiting for a direction
var last = null               # the last stick direction pushed: { x, y, age since the stick came back to centre }
var ready_trick = null        # a trick picked on the ground, waiting for the board to leave it
var ready_age := 0.0

var pending: bool:
	get:
		return press_age <= T.trickWindow or ready_trick != null


static func stick_angle(x: float, y: float) -> float:
	return atan2(absf(x), y) * 180.0 / PI   # 0 = straight down, 180 = straight up


static func stick_direction(x: float, y: float) -> String:
	if not is_finite(x) or not is_finite(y) or sqrt(x * x + y * y) < T.trickStick:
		return "center"
	var a := stick_angle(x, y)
	var side := "left" if x < 0.0 else "right"
	if a < 22.5:
		return "down"
	if a < 67.5:
		return "down-" + side
	if a < 112.5:
		return side
	if a < 157.5:
		return "up-" + side
	return "up"


func reset() -> void:
	press_age = INF
	ready_trick = null
	ready_age = 0.0


# Returns the trick to start now ({name, flip, shuv}), or null.
func sample(button: bool, x: float, y: float, dt: float, enabled: bool, can_start: bool):
	var pressed := button and not held
	held = button

	var out := stick_direction(x, y) != "center"
	if out:
		last = {"x": x, "y": y, "age": 0.0}
	elif last != null:
		last.age += dt
		if last.age > T.trickWindow:
			last = null

	if not enabled:
		reset()
		return null
	if pressed:
		press_age = 0.0
		ready_trick = null
	elif press_age != INF:
		press_age += dt
	if press_age > T.trickWindow:
		press_age = INF

	# B is live and there is a direction: now if the stick is pushed, or the push you just let go of.
	if ready_trick == null and press_age != INF and last != null:
		var trick = TRICKS.get(stick_direction(last.x, last.y))
		press_age = INF   # one press, one trick (an upward direction uses it up and does nothing)
		last = null
		if trick != null:
			ready_trick = trick
			ready_age = 0.0

	if ready_trick == null:
		return null
	ready_age += dt
	if ready_age > T.trickWindow:
		ready_trick = null
		return null   # pressed on the ground and never left it
	if not can_start:
		return null
	var picked = ready_trick
	reset()
	return picked
