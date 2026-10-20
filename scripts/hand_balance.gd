# Turns the two hands into a push on the balance meter: the tilt of the line between them, like holding a balance pole.
#
# Tilt is an angle, so it feels the same whether the hands are held close together or wide apart. It is measured against the tilt
# your hands have at the moment a grind or manual starts, wherever they happen to be then (arms out, down, mid-swing): that is the
# neutral, and it stays put for the length of the balance. The push also eases in over a moment, so the first instant is never a shove.
class_name HandBalance
extends RefCounted

const HANDS = Config.Hands

# Which hand, raised, pushes the meter to the right: "left" or "right". There is a choice for grinds and one for manuals, both in the
# menu and kept in the settings file. `update` below always reports right hand up as +; the game applies the choice on top.
static func pushing_hand(kind: String) -> String:
	var config := ConfigFile.new()
	if config.load(Levels.SETTINGS) == OK:
		var hand: String = config.get_value("hands", kind, "left")
		if hand == "right":
			return hand
	return "left"


static func set_pushing_hand(kind: String, hand: String) -> void:
	var config := ConfigFile.new()
	config.load(Levels.SETTINGS)
	config.set_value("hands", kind, hand)
	config.save(Levels.SETTINGS)


static func other_hand(hand: String) -> String:
	return "left" if hand == "right" else "right"


# The sign to apply to `update`'s result for a choice of hand.
static func sign_for(hand: String) -> float:
	return 1.0 if hand == "right" else -1.0


var rest := 0.0        # neutral tilt in radians: the tilt when this balance started
var anchored := false  # the neutral has been taken for the balance that is under way
var lean := 0.0
var engage := 0.0      # 0..1, how far the push has eased in since the balance started


# left / right are hand positions in play space, or null when a hand is not tracked. `balancing`: a grind or manual is under way.
# Returns −1..1 (right hand up = +).
func update(dt: float, left, right, balancing: bool = false) -> float:
	if left == null or right == null:
		engage = 0.0
		anchored = false   # (a hand that comes back mid-balance is the new neutral)
		lean += (0.0 - lean) * (1.0 - exp(-HANDS.response * dt))
		return lean
	var spread := maxf(HANDS.minSpread, Skater.hypot(right.x - left.x, right.z - left.z))
	var tilt := atan2(right.y - left.y, spread)
	if not balancing:
		anchored = false
	elif not anchored:
		rest = tilt
		anchored = true
	engage = minf(1.0, engage + dt / HANDS.ease) if balancing else 0.0
	var push := tilt - rest
	push = (absf(push) - HANDS.deadzone) * signf(push) if absf(push) > HANDS.deadzone else 0.0
	var target := clampf(push / (HANDS.range - HANDS.deadzone), -1.0, 1.0) * engage
	lean += (target - lean) * (1.0 - exp(-HANDS.response * dt))
	return lean
