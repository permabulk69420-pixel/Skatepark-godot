# Replays recorded inputs on the Gravesend collision mesh and checks every frame against what the web build's sim did with the same
# inputs: same mode on every frame, same events on the same frames, positions within a millimetre or so (32-bit vs 64-bit floats).
#   godot --headless --path . -s res://tests/sim_replay.gd            all scenarios in tests/fixtures
#   godot --headless --path . -s res://tests/sim_replay.gd -- ride    just those named
# Exit code 0 only if every scenario matches.
#
# Fixtures: <name>.input.json  { dt, frames: [[steer, drive, jump, grind, flip, stickX, stickY, lean], …] }
#           <name>.expected.json { trace: [[x, y, z, vx, vy, vz, heading, mode], …], events: [[frame, type], …] }
# They were recorded from the web build's sim.js on this level's collision triangles as Godot imports them (see tests/reference),
# so the check is like for like. A scenario that rolls off a deck edge on a knife-edge frame can differ by a frame in any
# implementation (the web sim itself loses sync with itself when its start is nudged by two micrometres), so the scenarios here
# are ones that are stable.
extends SceneTree

const LEVEL := "res://assets/levels/gravesend.glb"
const FIXTURES := "res://tests/fixtures"
const MODES := ["ground", "air", "grind", "bail", "loop"]
const POS_TOLERANCE := 0.01   # metres

# mulberry32, the same generator the web run used, so the balance wobble and bail tumble match.
class Mulberry:
	var state := 12345

	static func imul(a: int, b: int) -> int:
		return (a * b) & 0xFFFFFFFF

	func next() -> float:
		state = (state + 0x6D2B79F5) & 0xFFFFFFFF
		var t := state
		t = imul(t ^ (t >> 15), t | 1)
		t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF)) & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0


func _init() -> void:
	run.call_deferred()


func read_json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func run() -> void:
	var names: Array = Array(OS.get_cmdline_user_args())
	if names.is_empty():
		for file in DirAccess.get_files_at(FIXTURES):
			if file.ends_with(".input.json"):
				names.append(file.trim_suffix(".input.json"))
		names.sort()

	await process_frame
	var holder := Node3D.new()
	root.add_child(holder)
	var level := LevelLoader.load_level(LEVEL, holder)
	await process_frame
	await physics_frame
	await physics_frame
	var world := SkateWorld.new(holder.get_world_3d().direct_space_state)
	var paths := GrindPath.parse(level.grind_nodes)

	var failed := 0
	for scenario_name in names:
		if not replay(String(scenario_name), level, world, paths):
			failed += 1
	print("\n%d of %d scenarios match the web build" % [names.size() - failed, names.size()])
	quit(0 if failed == 0 else 1)


func replay(scenario_name: String, level: LevelLoader, world: SkateWorld, paths: Array[GrindPath]) -> bool:
	var scenario := read_json("%s/%s.input.json" % [FIXTURES, scenario_name])
	var expected := read_json("%s/%s.expected.json" % [FIXTURES, scenario_name])
	var rand := Mulberry.new()
	var sim := Skater.new(world, paths, [] as Array[LoopPath], {"x": 29.0, "z": 22.5, "cx": 0.0, "cz": 0.0}, true)
	sim.random_fn = rand.next
	sim.set_spawn(level.spawn_pos, level.spawn_heading)
	var events: Array = []
	var frame := [0]   # an array so the callback below sees the current frame (lambdas capture locals by value)
	sim.event.connect(func(type: String, _data: Dictionary): events.append([frame[0], type]))
	events.clear()

	var dt: float = scenario.dt
	var frames: Array = scenario.frames
	var trace: Array = expected.trace
	var max_pos := 0.0
	var max_vel := 0.0
	var mode_diffs := 0
	var first_bad := -1
	var cmd := Skater.Command.new()
	for i in frames.size():
		frame[0] = i
		var f: Array = frames[i]
		cmd.steer = f[0]
		cmd.drive = f[1]
		cmd.jump = f[2] != 0
		cmd.grind = f[3] != 0
		cmd.flip = f[4] != 0
		cmd.trick_stick = Vector2(f[5], f[6])
		cmd.lean = f[7]
		sim.update(cmd, dt)
		var e: Array = trace[i]
		var dp := (sim.pos - Vector3(e[0], e[1], e[2])).length()
		var dv := (sim.vel - Vector3(e[3], e[4], e[5])).length()
		var mode_differs: bool = int(sim.mode) != int(e[7])
		max_pos = maxf(max_pos, dp)
		max_vel = maxf(max_vel, dv)
		if mode_differs:
			mode_diffs += 1
		if first_bad < 0 and (dp > POS_TOLERANCE or mode_differs):
			first_bad = i
			print("  first divergence at frame %d (t=%.2fs): position off by %.5f m, mode %s (web build: %s)" % [i, i * dt, dp, MODES[int(sim.mode)], MODES[int(e[7])]])

	var want_events: Array = expected.events
	var event_diffs := 0
	for i in maxi(want_events.size(), events.size()):
		var got = events[i] if i < events.size() else null
		var want = want_events[i] if i < want_events.size() else null
		if got == null or want == null or got[0] != int(want[0]) or got[1] != want[1]:
			event_diffs += 1
			if event_diffs <= 3:
				print("  event %d differs: got %s, web build %s" % [i, str(got), str(want)])
	var ok := first_bad < 0 and event_diffs == 0
	print("%-8s %s  %4d frames, %3d events, max position diff %.5f m, max velocity diff %.5f m/s" % [scenario_name, "MATCH " if ok else "DIFFERS", frames.size(), events.size(), max_pos, max_vel])
	return ok
