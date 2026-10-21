# How close a rail has to be for a grind to catch: wherever the board would touch it, plus 10 cm each side.
#   godot --headless --path . -s res://tests/grind_logic.gd
extends SceneTree


func _init() -> void:
	var T = Config.Tuning
	var failures := 0
	var checks := [
		["a 50-50 straight along the rail catches it anywhere under the board's width plus 10 cm each side (%.1f cm)" % (Skater.board_reach(0.0) * 100.0), absf(Skater.board_reach(0.0) - (Config.Board.width / 2.0 + 0.10)) < 1e-6],
		["a boardslide square across the rail catches it anywhere along the board's length plus 10 cm each end (%.1f cm)" % (Skater.board_reach(PI / 2.0) * 100.0), absf(Skater.board_reach(PI / 2.0) - (Config.Board.length / 2.0 + 0.10)) < 1e-6],
		["in between, the reach grows smoothly (never smaller than the 50-50's, never bigger than the boardslide's)", Skater.board_reach(0.6) > Skater.board_reach(0.0) and Skater.board_reach(0.6) < Skater.board_reach(PI / 2.0)],
		["a board across the rail is a boardslide and along it a 50-50, split at 45 degrees with no gap", absf(T.grindSplit - PI / 4.0) < 1e-6],
	]
	for c in checks:
		print("%s  %s" % ["ok  " if c[1] else "FAIL", c[0]])
		if not c[1]:
			failures += 1
	print("all grind checks pass" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
