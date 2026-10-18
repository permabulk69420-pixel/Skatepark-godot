# Quest controllers buzz. Everything the game feels goes through here: one-shot thumps on the skater's events and a continuous
# texture (wheels on concrete, a grind) that follows what the board is doing.
class_name Haptics
extends RefCounted

var controllers := {}        # "left" / "right" -> XRController3D
var last_pulse := {"left": 0, "right": 0}
var enabled := true


func _init(left, right) -> void:
	controllers["left"] = left
	controllers["right"] = right


func _buzz(hand: String, strength: float, ms: float) -> void:
	var controller = controllers.get(hand)
	if controller == null:
		return
	last_pulse[hand] = Time.get_ticks_msec()
	controller.trigger_haptic_pulse("haptic", 0.0, strength, ms / 1000.0, 0.0)


# One-shot thump on one or both hands.
func pulse(intensity: float, ms: float = 30.0, hand: String = "both") -> void:
	if not enabled:
		return
	var strength := clampf(intensity, 0.0, 1.0)
	for h in ["left", "right"]:
		if hand == "both" or hand == h:
			_buzz(h, strength, clampf(ms, 1.0, 250.0))


# Continuous texture: call every frame, it re-pulses at most every `every` ms.
func rumble(intensity: float, hand: String = "both", every: float = 45.0) -> void:
	if not enabled or intensity <= 0.005:
		return
	var now := Time.get_ticks_msec()
	var strength := clampf(intensity, 0.0, 1.0)
	for h in ["left", "right"]:
		if hand != "both" and hand != h:
			continue
		if now - last_pulse[h] < every:
			continue
		_buzz(h, strength, every + 12.0)


# What the skater just did, felt in the hands.
func event(type: String, data: Dictionary) -> void:
	match type:
		"crouch":
			pulse(0.22, 18)
		"pop":
			pulse(0.5 + 0.35 * float(data.charge), 34)
		"push":
			pulse(0.3, 28)
		"flipStart":
			pulse(0.3, 22)
		"flip":
			pulse(0.6, 45)
		"sketchy":
			pulse(0.55, 80)
		"pump":
			pulse(clampf(0.25 + float(data.gain) * 0.6, 0.25, 0.7), 40)
		"land":
			if float(data.impact) >= 0.9:
				pulse(clampf(0.2 + float(data.impact) * 0.09, 0.2, 1.0), minf(120.0, 30.0 + float(data.impact) * 7.0))
		"wall":
			pulse(clampf(0.3 + float(data.impact) * 0.14, 0.3, 1.0), 70)
		"grindStart":
			pulse(0.85, 32)
		"manualStart":
			pulse(0.45, 28)
		"bail":
			pulse(1.0, 240)
		"loopStart":
			pulse(0.4, 30)
		"loopEnd":
			if data.completed:
				pulse(0.9, 90)
		"catch":
			pulse(0.7 if data.quality == "clean" else 0.5, 50)


# Called every frame: the feel of whatever the board is doing right now.
func continuous(sim: Skater) -> void:
	if sim.mode == Skater.Mode.GROUND:
		if sim.manual != null:
			rumble(0.12 + 0.45 * sim.manual.bal * sim.manual.bal, "both", 40.0)
		elif sim.braking:
			rumble(0.3, "both", 40.0)
		elif sim.speed > 0.4:
			rumble(0.03 + 0.06 * minf(sim.speed / 10.0, 1.0), "both", 60.0)
	elif sim.mode == Skater.Mode.LOOP and sim.loop != null:
		# The track presses harder the faster you go round it.
		rumble(0.08 + 0.3 * minf(absf(sim.loop.gs) / 12.0, 1.0), "both", 40.0)
	elif sim.mode == Skater.Mode.GRIND and sim.grind != null:
		# The closer to falling off, the harder the rail shakes the board.
		rumble(0.28 + 0.5 * sim.grind.bal * sim.grind.bal, "both", 35.0)
