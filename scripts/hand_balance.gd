# Turns the two hands into a push on the balance meter: the tilt of the line between them, like holding a balance pole. Right
# hand up is a push right, left hand up a push left.
#
# Tilt is an angle, so it feels the same whether the hands are held close together or wide apart. It is measured against a
# "neutral" learned only while the rider is rolling relaxed on the ground (the caller says when, with `learn`): arms swinging
# through a crouch, pop or flight must not become the neutral, or the meter would start a grind already shoved to one side.
# The neutral is frozen for the length of a balance, and the push eases in so landing arm-swing does not kick the meter.
class_name HandBalance
extends RefCounted

const HANDS = Config.Hands

var rest := NAN        # neutral tilt in radians
var lean := 0.0
var engage := 0.0      # 0..1, how far the push has eased in since the balance started


# left / right are hand positions in play space, or null when a hand is not tracked. Returns −1..1 (right hand up = +).
func update(dt: float, left, right, balancing: bool = false, learn: bool = true) -> float:
	if left == null or right == null:
		engage = 0.0
		lean += (0.0 - lean) * (1.0 - exp(-HANDS.response * dt))
		return lean
	var spread := maxf(HANDS.minSpread, Skater.hypot(right.x - left.x, right.z - left.z))
	var tilt := atan2(right.y - left.y, spread)
	if is_nan(rest):
		rest = tilt
	if not balancing and learn:
		rest += (tilt - rest) * (1.0 - exp(-dt / HANDS.restTime))
	engage = minf(1.0, engage + dt / HANDS.ease) if balancing else 0.0
	var push := tilt - rest
	push = (absf(push) - HANDS.deadzone) * signf(push) if absf(push) > HANDS.deadzone else 0.0
	var target := clampf(push / (HANDS.range - HANDS.deadzone), -1.0, 1.0) * engage
	lean += (target - lean) * (1.0 - exp(-HANDS.response * dt))
	return lean
