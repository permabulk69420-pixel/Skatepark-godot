# The score. It listens to the skating events (the same ones the HUD flashes names for) and turns them into points, Tony Hawk style.
# The tricks you do in one go (a jump, the grind or manual you land in, and on to the next if you keep going) make a chain. The chain is
# banked into the total once you have been plainly rolling along for CHAIN_GAP seconds, and thrown away if you bail.
# Every number to tune is in the block below.
class_name Score
extends RefCounted

signal chain_changed(text: String, points: int)   # a trick was added to the live chain: the chain's names, and what it is worth so far
signal banked(points: int, total: int)            # the chain was landed and rolled out: what it was worth, and the new total
signal lost(points: int)                          # the chain was thrown away (a bail): what it would have been worth

# ---- the numbers to tune ----------------------------------------------------------------------------------------------------------
const CHAIN_GAP := 1.0          # seconds of plain rolling that bank a chain (do another trick inside it and the chain carries on)
const MULTIPLIER_STEP := 0.5    # each different trick in a chain adds this to the multiplier: x1, x1.5, x2, x2.5 ...
const REPEAT_KEEP := 0.5        # a trick that is already in the chain is worth this much of its value, and adds nothing to the multiplier
const SKETCHY_KEEP := 0.5       # a sketchy landing keeps this much of the chain

# Flips and shove-its: the first keyword found in the trick's name sets its value. (A name can hold several: "Kickflip + Pop Shove-it".)
const FLIPS := [["Varial", 450], ["Backflip", 700], ["Frontflip", 700], ["Kickflip", 300], ["Heelflip", 300], ["Shove-it", 250]]
const FLIP_DEFAULT := 250
const FAKIE_BONUS := 1.2        # "Fakie" tricks are worth this much more
const TURNS := {"Double ": 2.0, "Triple ": 3.0}   # a double or triple is worth this many times the single

# Grabs: a base value, plus a bit for every second you hold it (up to the cap). Under GRAB_MIN_HOLD is a touch, and scores nothing.
const GRABS := {"Indy": 250, "Stalefish": 300, "Melon": 250, "Mute": 300, "Nose grab": 200, "Tail grab": 200}
const GRAB_DEFAULT := 200
const GRAB_MIN_HOLD := 0.3
const GRAB_PER_SECOND := 150
const GRAB_MAX_SECONDS := 5.0

# Grinds, by keyword in the name ("Coping 50-50" is a 50-50), plus a bit for every second on it.
const GRINDS := [["Axle Stall", 150], ["Nosegrind", 350], ["5-0", 350], ["Boardslide", 300], ["50-50", 250]]
const GRIND_DEFAULT := 250
const GRIND_MIN_TIME := 0.3
const GRIND_PER_SECOND := 120
const GRIND_MAX_SECONDS := 8.0

# Manuals.
const MANUAL := 100
const MANUAL_MIN_TIME := 0.5
const MANUAL_PER_SECOND := 100
const MANUAL_MAX_SECONDS := 10.0

const LOOP := 1000              # a loop-the-loop ridden all the way round
const CATCH := 600              # the board taken off your feet, a trick done, and caught (a sketchy catch is worth SKETCHY_KEEP of it)
const CHRIST_AIR := 1200        # the same, when the trick was a Christ Air
# -----------------------------------------------------------------------------------------------------------------------------------

var total := 0                  # points banked so far
var best_chain := 0             # the best chain banked so far
var chain: Array = []           # the live chain: { label, points, repeat }
var _sketchy := false           # the chain has had a sketchy landing
var _idle := 0.0                # seconds of plain rolling since the chain last did anything
var _bailing := false           # the skater is in a bail: events that come with it (a grab letting go) score nothing


# One skating event ({ type, data } as the sim and the board grab emit them).
func event(type: String, data: Dictionary) -> void:
	if type == "bail":
		_bailing = true
		_drop()
		return
	if type == "respawn":
		_drop()
		return
	if _bailing:
		return
	match type:
		"sketchy":
			_sketchy = true
		"flip":
			for part in String(data.get("name", "")).split(" + ", false):
				_add(part, _flip_value(part))
		"grabEnd":
			var held := float(data.get("time", 0.0))
			if held >= GRAB_MIN_HOLD:
				var name := String(data.get("name", ""))
				_add(name, float(GRABS.get(name, GRAB_DEFAULT)) + GRAB_PER_SECOND * minf(held, GRAB_MAX_SECONDS))
		"grindEnd":
			var time := float(data.get("time", 0.0))
			if data.get("reason", "") != "bail" and time >= GRIND_MIN_TIME:
				var name := String(data.get("name", ""))
				_add(name, _keyword_value(GRINDS, name, GRIND_DEFAULT) + GRIND_PER_SECOND * minf(time, GRIND_MAX_SECONDS))
		"manualEnd":
			var time := float(data.get("time", 0.0))
			if data.get("reason", "") != "bail" and time >= MANUAL_MIN_TIME:
				var parts := String(data.get("name", "Manual")).split(" + ", false)   # ("Kickflip + Manual": the flip scores by itself)
				_add(parts[parts.size() - 1] if parts.size() > 0 else "Manual", MANUAL + MANUAL_PER_SECOND * minf(time, MANUAL_MAX_SECONDS))
		"loopEnd":
			if data.get("completed", false):
				_add("Loop", LOOP)
		"catch":
			var name := String(data.get("name", ""))
			if name != "":
				var worth := CHRIST_AIR if name.contains("Christ Air") else CATCH
				_add(name, worth * (SKETCHY_KEEP if data.get("quality", "") == "sketchy" else 1.0))


# Every frame. `rolling_plain`: on the ground, not in a manual or a grind. `in_bail`: the skater is bailing.
func update(dt: float, rolling_plain: bool, in_bail := false) -> void:
	if not in_bail:
		_bailing = false
	if chain.is_empty():
		_idle = 0.0
		_sketchy = false   # (a sketchy landing with no trick on it counts against nothing)
		return
	_idle = _idle + dt if rolling_plain else 0.0
	if _idle >= CHAIN_GAP:
		var points := chain_points()
		total += points
		best_chain = maxi(best_chain, points)
		_clear()
		banked.emit(points, total)


# What the live chain is worth now: its tricks added up, times a multiplier for how many different ones there are.
func chain_points() -> int:
	var sum := 0.0
	var different := 0
	for entry: Dictionary in chain:
		sum += entry.points
		if not entry.repeat:
			different += 1
	var multiplier := 1.0 + MULTIPLIER_STEP * maxi(different - 1, 0)
	return roundi(sum * multiplier * (SKETCHY_KEEP if _sketchy else 1.0))


# The live chain's trick names, in order, as "Kickflip + Indy + 50-50" (the last three, if it is longer than that).
func chain_text() -> String:
	var names := PackedStringArray()
	for entry: Dictionary in chain:
		if not entry.repeat:
			names.append(entry.label)
	var start := maxi(names.size() - 3, 0)
	return ("… + " if start > 0 else "") + " + ".join(names.slice(start))


func reset() -> void:
	total = 0
	best_chain = 0
	_clear()
	_bailing = false


# 1234567 -> "1,234,567".
static func format(points: int) -> String:
	var digits := str(absi(points))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if points < 0 else "") + out


func _add(label: String, points: float) -> void:
	if label == "":
		return
	var repeat := false
	for entry: Dictionary in chain:
		if entry.label == label:
			repeat = true
	chain.append({"label": label, "points": points * (REPEAT_KEEP if repeat else 1.0), "repeat": repeat})
	_idle = 0.0
	chain_changed.emit(chain_text(), chain_points())


func _drop() -> void:
	var had_chain := not chain.is_empty()
	var points := chain_points()
	_clear()
	if had_chain:
		lost.emit(points)


func _clear() -> void:
	chain.clear()
	_sketchy = false
	_idle = 0.0


func _flip_value(part: String) -> float:
	var value := _keyword_value(FLIPS, part, FLIP_DEFAULT)
	for word: String in TURNS:
		if part.contains(word):
			value *= float(TURNS[word])
	return value * (FAKIE_BONUS if part.begins_with("Fakie ") else 1.0)


# The value of the first keyword in `list` ([[keyword, value], …]) that `name` contains, else `fallback`.
static func _keyword_value(list: Array, name: String, fallback: float) -> float:
	for entry: Array in list:
		if name.contains(entry[0]):
			return float(entry[1])
	return fallback
