# Taking the board off your feet in the air and catching it again (board_grab.gd does the holding, skater.gd the consequences).
# While you hold the board in a grab, squeeze the detach button (left trigger; C on a flat screen): the board leaves your feet and
# stays in your hand exactly where it was. Let go of the button to catch: the board snaps back under your feet if it is close enough
# and lined up well enough at that moment (if not, it stays in your hand: squeeze and let go again). Land without it and you bail.
# Held out to the side with your other arm out the other way (a T, like a cross) it is a Christ Air.
class_name BoardOff
extends RefCounted

const CLEAN_ANGLE := 0.4363323129985824    # 25°: within both of these, a clean catch
const CLEAN_DISTANCE := 0.3
const SKETCHY_ANGLE := 1.0471975511965976  # 60°: within both of these, caught, but you land sketchy
const SKETCHY_DISTANCE := 0.5
const MISS_BAILS := false                   # a catch pressed with the board way off: false = nothing happens (try again), true = you bail
const CHRIST := 0.5                         # flat screen (no hands to see): the board held at least this far from your feet is a Christ Air
const TPOSE_SPAN := 1.0                     # metres between the two hands (across, from above)
const TPOSE_BODY := 0.35                    # metres: your head is this near the line between the hands (arms out either side, not both in front)
const TPOSE_BELOW := 0.65                   # metres: the hands are no lower than this under your head...
const TPOSE_ABOVE := 0.15                   # ...and no higher than this over it
const TPOSE_LEVEL := 0.35                   # metres: and within this of each other in height
const CHRIST_HOLD := 0.25                   # seconds in that pose, at some point while the board is in your hand, for it to be a Christ Air
const SETTLE := 0.12                        # seconds the board takes to swing the last few degrees into line after a catch
const NAME_NEAR := "Board Off"
const NAME_FAR := "Christ Air"


# Are the two hands held out in a T (head between them, arms out to either side, roughly level and about shoulder height)?
static func is_tpose(head: Vector3, left: Vector3, right: Vector3) -> bool:
	var a := Vector2(left.x, left.z)
	var b := Vector2(right.x, right.z)
	if a.distance_to(b) < TPOSE_SPAN:
		return false
	var closest := Geometry2D.get_closest_point_to_segment(Vector2(head.x, head.z), a, b)
	if closest.distance_to(Vector2(head.x, head.z)) > TPOSE_BODY:
		return false
	for y in [left.y, right.y]:
		if y < head.y - TPOSE_BELOW or y > head.y + TPOSE_ABOVE:
			return false
	return absf(left.y - right.y) <= TPOSE_LEVEL


# How a catch pressed now would go. The board and the feet are each a position and an orientation in the world, where the feet are the
# frame the board belongs in (the sim's board frame: origin where the wheels meet the ground, nose along −z, up +y).
# Returns { quality: "clean" | "sketchy" | "miss", angle, distance, reversed } — reversed: caught nose-for-tail (it still counts; the
# board is then ridden the other way round, as after a shove-it).
static func judge_catch(board_pos: Vector3, board_q: Quaternion, feet_pos: Vector3, feet_q: Quaternion) -> Dictionary:
	var up := board_q * Vector3.UP
	var feet_up := feet_q * Vector3.UP
	var length := board_q * Vector3(0, 0, -1)
	var feet_length := feet_q * Vector3(0, 0, -1)
	var tilt := up.angle_to(feet_up)                        # upside down is ~180°
	var along := length.dot(feet_length)
	var twist := acos(minf(1.0, absf(along)))               # nose or tail first, either is fine
	var angle := maxf(tilt, twist)
	var distance := board_pos.distance_to(feet_pos)
	var quality := "miss"
	if angle <= CLEAN_ANGLE and distance <= CLEAN_DISTANCE:
		quality = "clean"
	elif angle <= SKETCHY_ANGLE and distance <= SKETCHY_DISTANCE:
		quality = "sketchy"
	return {"quality": quality, "angle": angle, "distance": distance, "reversed": along < 0.0}
