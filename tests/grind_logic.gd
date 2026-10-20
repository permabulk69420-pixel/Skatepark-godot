# How close a rail has to be for a grind to catch: the footprint of the board, plus 10 cm each side.
#   godot --headless --path . -s res://tests/grind_logic.gd
extends SceneTree


func _init() -> void:
	var T = Config.Tuning
	var failures := 0
	var checks := [
		["a 50-50 catches a rail anywhere under the board's width plus 10 cm each side (%.1f cm)" % (T.truckLateral * 100.0), absf(T.truckLateral - (Config.Board.width / 2.0 + 0.10)) < 1e-6 and T.truckLateral > 0.19 and T.truckLateral < 0.22],
		["a boardslide catches a rail anywhere along the board's length plus 10 cm each end (%.1f cm)" % (T.slideLateral * 100.0), absf(T.slideLateral - (Config.Board.length / 2.0 + 0.10)) < 1e-6 and T.slideLateral > 0.49 and T.slideLateral < 0.52],
		["the angles are back to 30 degrees", absf(T.grindAlign - 0.52) < 0.01 and absf(T.slideAlign - 0.52) < 0.01],
	]
	for c in checks:
		print("%s  %s" % ["ok  " if c[1] else "FAIL", c[0]])
		if not c[1]:
			failures += 1
	print("all grind checks pass" if failures == 0 else "%d FAILED" % failures)
	quit(1 if failures > 0 else 0)
