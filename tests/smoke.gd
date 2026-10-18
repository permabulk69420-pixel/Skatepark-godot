# Plays recorded scenarios through the whole game (rig, board, HUD, sounds), not just the sim, and fails on any script error.
#   godot --headless --path . -s res://tests/smoke.gd
extends SceneTree

const SCENARIOS := ["rail", "ledge", "random1", "random5"]

# Feeds a recorded input list instead of the keyboard.
class ScriptedInput extends SkateInput:
	var frames: Array = []
	var index := 0

	func poll(_dt: float) -> Skater.Command:
		var f: Array = frames[mini(index, frames.size() - 1)]
		index += 1
		command.steer = f[0]
		command.drive = f[1]
		command.jump = f[2] != 0
		command.grind = f[3] != 0
		command.flip = f[4] != 0
		command.trick_stick = Vector2(f[5], f[6])
		command.lean = f[7]
		return command


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "gravesend"   # (not whichever level was left on last; `level=<id>` after -- picks another)
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 2000:
		await process_frame
		guard += 1
	if not main.ready_to_play:
		push_error("the game never became ready")
		quit(1)
		return
	main.set_process(false)   # the test calls the frame loop itself, with the recorded time step
	var modes_seen := {}
	for scenario_name in SCENARIOS:
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/%s.input.json" % scenario_name))
		var scripted := ScriptedInput.new()
		scripted.frames = scenario.frames
		main.input = scripted
		main.sim.respawn(main.sim.spawn)
		for i in scenario.frames.size():
			main._process(scenario.dt)
			modes_seen[main.sim.mode] = true
			if i % 4 == 0:
				await process_frame   # let the engine run its own frame now and then (audio mixing, HUD layout)
		print("%-8s done: mode %d, pos %s, hud shows '%s'" % [scenario_name, main.sim.mode, main.sim.pos, main.hud.trick_label.text])
	print("sounds played: ", main.sfx.played)
	print("modes seen: ", modes_seen.keys())
	main.queue_free()
	await process_frame
	quit(0)
