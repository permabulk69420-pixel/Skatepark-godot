# The score, tested without a game: events go in the way the sim sends them, and chains are checked for what they are worth,
# when they bank and when they are lost. (It checks how the numbers relate, not the numbers themselves, so they can be tuned.)
#   godot --headless --path . -s res://tests/score_logic.gd
extends SceneTree

var failures := 0
var banks: Array = []
var losses: Array = []
var changes: Array = []


func check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func fresh() -> Score:
	var s := Score.new()
	banks.clear()
	losses.clear()
	changes.clear()
	s.banked.connect(func(points: int, total: int) -> void: banks.append([points, total]))
	s.lost.connect(func(points: int) -> void: losses.append(points))
	s.chain_changed.connect(func(text: String, points: int) -> void: changes.append([text, points]))
	return s


# Lets `seconds` of plain rolling go by.
func roll(s: Score, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		s.update(0.05, true)
		t += 0.05


func _init() -> void:
	# a jump with a grab and a flip, landed and rolled out
	var s := fresh()
	s.event("grabEnd", {"name": "Indy", "part": "right", "time": 1.0})
	s.event("land", {"impact": 2.0})
	s.event("flip", {"name": "Kickflip"})
	check(s.chain_text() == "Indy + Kickflip", "a grab and a flip make one chain, named in order (%s)" % s.chain_text())
	check(s.total == 0 and s.chain_points() > 0, "nothing is banked until it has been rolled out")
	var live := s.chain_points()
	roll(s, Score.CHAIN_GAP + 0.2)
	check(banks.size() == 1 and banks[0][0] == live and s.total == live, "rolling out banks exactly what the chain showed (%d)" % live)
	check(s.chain.is_empty(), "the chain starts again after a bank")

	# different tricks multiply; one trick alone does not
	s = fresh()
	s.event("flip", {"name": "Kickflip"})
	var single := s.chain_points()
	s.event("grabEnd", {"name": "Indy", "time": 0.0 + Score.GRAB_MIN_HOLD})
	s.event("grindEnd", {"name": "50-50", "reason": "pop", "time": 1.0})
	var parts := 0.0
	for entry: Dictionary in s.chain:
		parts += entry.points
	check(s.chain_points() > roundi(parts), "three different tricks are worth more than the sum of their parts")
	check(s.chain_points() == roundi(parts * (1.0 + Score.MULTIPLIER_STEP * 2.0)), "...by the multiplier step for each extra trick")
	check(single > 0, "a lone trick scores")

	# the same trick again is worth less, and adds nothing to the multiplier
	s = fresh()
	s.event("flip", {"name": "Kickflip"})
	var first := s.chain_points()
	s.event("flip", {"name": "Kickflip"})
	var twice := s.chain_points()
	check(twice > first and twice < first * 2, "a repeated trick adds less than the first (%d then %d)" % [first, twice])
	check(s.chain_text() == "Kickflip", "...and is not listed twice")

	# a bail throws the chain away
	s = fresh()
	s.event("flip", {"name": "Heelflip"})
	var at_risk := s.chain_points()
	s.event("bail", {"reason": "landing"})
	check(s.total == 0 and s.chain.is_empty(), "a bail loses the chain")
	check(losses == [at_risk], "...and says what it was worth")
	roll(s, 3.0)
	check(banks.is_empty(), "...so nothing is banked later")

	# things that come with the bail do not score
	s = fresh()
	s.event("bail", {"reason": "impact"})
	s.event("grabEnd", {"name": "Indy", "time": 1.5})
	s.event("grindEnd", {"name": "50-50", "reason": "bail", "time": 2.0})
	check(s.chain.is_empty(), "a grab that lets go in a bail scores nothing")
	s.update(0.05, false, true)
	s.event("grabEnd", {"name": "Indy", "time": 1.5})
	check(s.chain.is_empty(), "...for as long as the skater is still bailing")
	s.update(0.05, true, false)
	s.event("grabEnd", {"name": "Indy", "time": 1.5})
	check(not s.chain.is_empty(), "...and scoring is back once the skater is up")

	# a sketchy landing keeps only part of the chain
	s = fresh()
	s.event("flip", {"name": "Kickflip"})
	var clean := s.chain_points()
	s = fresh()
	s.event("sketchy", {})
	s.event("land", {"impact": 3.0})
	s.event("flip", {"name": "Kickflip"})
	check(s.chain_points() == roundi(clean * Score.SKETCHY_KEEP), "a sketchy landing keeps SKETCHY_KEEP of it (%d of %d)" % [s.chain_points(), clean])
	s = fresh()
	s.event("sketchy", {})
	s.update(0.05, true)
	s.event("flip", {"name": "Kickflip"})
	check(s.chain_points() == clean, "a sketchy landing with no trick on it does not spoil the next chain")

	# a trick inside the gap carries the chain on; the gap only counts plain rolling
	s = fresh()
	s.event("flip", {"name": "Kickflip"})
	roll(s, Score.CHAIN_GAP * 0.6)
	check(banks.is_empty(), "rolling for less than the gap banks nothing yet")
	s.event("flip", {"name": "Heelflip"})
	roll(s, Score.CHAIN_GAP * 0.6)
	check(banks.is_empty() and s.chain.size() == 2, "a trick inside the gap carries the chain on")
	for i in 40:
		s.update(0.05, false)   # in the air, or in a manual or grind: no plain rolling
	check(banks.is_empty(), "time in the air or on a grind never banks the chain")
	roll(s, Score.CHAIN_GAP + 0.2)
	check(banks.size() == 1, "...and it banks once, when the rolling has gone on long enough")

	# short grabs, short grinds and bails mid-grind do not score; manuals score on their own
	s = fresh()
	s.event("grabEnd", {"name": "Indy", "time": Score.GRAB_MIN_HOLD * 0.5})
	s.event("grindEnd", {"name": "50-50", "reason": "pop", "time": Score.GRIND_MIN_TIME * 0.5})
	s.event("manualEnd", {"name": "Manual", "reason": "pop", "time": Score.MANUAL_MIN_TIME * 0.5})
	check(s.chain.is_empty(), "a touch of a grab, a grind or a manual scores nothing")
	s.event("manualEnd", {"name": "Kickflip + Manual", "reason": "pop", "time": 2.0})
	check(s.chain_text() == "Manual", "a manual that began with a flip scores only the manual (%s)" % s.chain_text())

	# longer holds are worth more
	s = fresh()
	s.event("grindEnd", {"name": "50-50", "reason": "pop", "time": 1.0})
	var short := s.chain_points()
	s = fresh()
	s.event("grindEnd", {"name": "50-50", "reason": "pop", "time": 3.0})
	check(s.chain_points() > short, "a longer grind is worth more")
	s = fresh()
	s.event("grindEnd", {"name": "Coping 50-50", "reason": "pop", "time": 1.0})
	check(s.chain_points() == short, "a coping grind is worth the same as the grind it is")

	# a flip that has several tricks in it, and fakie
	s = fresh()
	s.event("flip", {"name": "Kickflip + Pop Shove-it"})
	check(s.chain_text() == "Kickflip + Pop Shove-it", "a credit with several tricks lists each of them")
	s = fresh()
	s.event("flip", {"name": "Kickflip"})
	var plain := s.chain_points()
	s = fresh()
	s.event("flip", {"name": "Fakie Kickflip"})
	check(s.chain_points() > plain, "a fakie trick is worth more")
	s = fresh()
	s.event("flip", {"name": "Double Kickflip"})
	var double := s.chain_points()
	s = fresh()
	s.event("flip", {"name": "Triple Kickflip"})
	var triple := s.chain_points()
	s = fresh()
	s.event("flip", {"name": "Backflip"})
	check(plain < double and double < triple and s.chain_points() > plain, "doubles and triples are worth more than singles, and a backflip more than a kickflip")

	# a loop, a board-off trick
	s = fresh()
	s.event("loopEnd", {"reason": "exit", "name": "Loop", "completed": false})
	check(s.chain.is_empty(), "a loop you fell off scores nothing")
	s.event("loopEnd", {"reason": "exit", "name": "Loop", "completed": true})
	check(s.chain_text() == "Loop", "a loop ridden all the way round does")
	s = fresh()
	s.event("catch", {"quality": "clean", "name": "Backflip"})
	var caught := s.chain_points()
	s = fresh()
	s.event("catch", {"quality": "sketchy", "name": "Backflip"})
	check(s.chain_points() < caught, "a sketchy catch is worth less than a clean one")
	s = fresh()
	s.event("catch", {"quality": "clean", "name": ""})
	check(s.chain.is_empty(), "a catch with no trick scores nothing")

	# the text for the screen
	s = fresh()
	for trick in ["Kickflip", "Indy", "50-50", "Manual"]:
		s.event("flip", {"name": trick})
	check(s.chain_text() == "… + Indy + 50-50 + Manual", "a long chain shows its last three (%s)" % s.chain_text())
	check(Score.format(0) == "0" and Score.format(950) == "950" and Score.format(1200) == "1,200" and Score.format(1234567) == "1,234,567", "points are written with commas")
	check(changes.size() == 4 and changes[3][1] == s.chain_points(), "every trick tells the screen the chain so far")

	print("")
	print("all score checks pass" if failures == 0 else "%d score checks FAILED" % failures)
	quit(0 if failures == 0 else 1)
