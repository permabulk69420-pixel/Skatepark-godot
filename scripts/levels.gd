# The levels the game can load. Each entry says where its model is and the few things that differ per level: the play area the skater
# is kept inside (half-extents x/z around an optional centre cx/cz), the intro text, and `look` (optional) to override the lighting:
# toneMapping ("aces"; anything else is plain linear), exposure, sun (intensity), sunColor, sunDirection ([x, y, z] towards the sun),
# hemisphere (fill), fog (colour), fogNear, fogFar. A level can also have `night` (a night version of a scan, see scripts/night.gd).
# Same layout as the web build's levels.js, so more levels can be added one entry at a time.
class_name Levels
extends RefCounted

const LEVELS := {
	# The house: a place to walk around, with the TV that picks the level. If there is no model at `file`, a plain stand-in is built instead
	# (scripts/hub_blockout.gd).
	"hub": {
		"name": "Home",
		"file": "res://assets/levels/hub.glb",
		"blurb": "Walk to the TV, pick up the remote, choose a level · the half pipe is out the back · hold the left menu button to come back here",
		"bounds": {"x": 20.0, "z": 21.0, "cx": 0.0, "cz": -9.0},
		"camera_far": 400.0,
		"look": {
			# golden hour: a low warm sun from the west-south-west and a warm horizon
			"exposure": 0.8, "sun": 2.6, "sunColor": "#ffbe7a", "sunDirection": [-0.75, 0.3, 0.45],
			"hemisphere": 0.45, "environment": 0.4, "fog": "#e6c6a2", "fogNear": 120.0, "fogFar": 300.0,
			"ambient": "#a07a58", "ambientSky": 0.35,
		},
	},
	"gravesend": {
		"name": "Gravesend",
		"file": "res://assets/levels/gravesend.glb",
		"blurb": "A photogrammetry scan of the real Gravesend skatepark · banks, ledges, rail, a quarter and stairs · scan by artfletch (CC-BY 4.0) · RIFT board",
		"bounds": {"x": 29.0, "z": 22.5, "cx": 0.0, "cz": 0.0},
		"camera_far": 280.0,
		"look": {
			"exposure": 0.74, "sun": 3.4, "sunColor": "#ffdcb4", "sunDirection": [-0.62, 0.5, -0.6],
			"hemisphere": 0.25, "environment": 0.5, "fog": "#c4d4de", "fogNear": 130.0, "fogFar": 290.0,
		},
	},
	"gravesendnight": {
		"name": "Gravesend Night",
		"file": "res://assets/levels/gravesend.glb",   # the same scan as Gravesend: the night is made in its material (scripts/night.gd)
		"blurb": "The Gravesend scan after dark · lit by cool white LED floods, with a big pool of light from where the sun was and three lamps · scan by artfletch (CC-BY 4.0) · RIFT board",
		"bounds": {"x": 29.0, "z": 22.5, "cx": 0.0, "cz": 0.0},
		"camera_far": 280.0,
		"look": {
			# sunDirection is the moon: up and ahead of the spawn (the floodlight below still comes from where the sun was when the scan was photographed)
			"exposure": 1.0, "sun": 0.25, "sunColor": "#9db8ff", "sunDirection": [-0.45, 0.53, -0.71],
			"hemisphere": 0.12, "environment": 0.02, "fog": "#03060d", "fogNear": 18.0, "fogFar": 85.0,
		},
		"night": {
			# the moon is up and ahead, to the right of where the rider starts (the faint moonlight on the board comes from it too)
			"sky": {"moon": [-0.45, 0.53, -0.71], "glow": "#5a4830"},
			"ambient": "#0b1426",
			"key": {"direction": [0.31, 0.42, 0.85], "colour": "#bcd6ff", "strength": 1.1, "centre": [0.0, 0.0], "radius": 20.0},
			"lamps": [
				{"base": [-24.0, 1.99, -17.0], "height": 9.0, "colour": "#d6e6ff", "power": 1.5, "radius": 15.0, "glow": 9.0},
				{"base": [23.0, 1.93, 2.0], "height": 9.0, "colour": "#d6e6ff", "power": 1.5, "radius": 15.0, "glow": 9.0},
				{"base": [-4.0, 2.16, 16.0], "height": 9.0, "colour": "#d6e6ff", "power": 1.5, "radius": 15.0, "glow": 9.0},
			],
		},
	},
	"breakwater": {
		"name": "Breakwater",
		"file": "res://assets/levels/breakwater.glb",
		"blurb": "104 × 88 metres · Street, bowl and transition · RIFT board",
		"bounds": {"x": 54.6, "z": 46.3, "cx": 0.0, "cz": 0.0},
		"camera_far": 280.0,
		"look": {
			"toneMapping": "aces", "exposure": 0.85, "sun": 2.1, "sunColor": "#ffe6c4", "sunDirection": [-0.40, 0.73, -0.56],
			"hemisphere": 0.48, "environment": 0.25, "fog": "#b8c6c5", "fogNear": 130.0, "fogFar": 290.0,
		},
	},
	"foundry": {
		"name": "Foundry",
		"file": "res://assets/levels/foundry.glb",
		"blurb": "80 × 72 metres · A 6.5 m start tower with a loop-the-loop, 7-, 5- and 3-stair sets, rails, hubbas, ledges, a funbox, a bowl and a mini ramp · RIFT board",
		"bounds": {"x": 39.55, "z": 35.55, "cx": 0.0, "cz": 0.0},
		"camera_far": 280.0,
		"decals": "Construction|Paint",
		"look": {
			"exposure": 0.74, "sun": 3.4, "sunColor": "#ffdcb4", "sunDirection": [-0.62, 0.5, -0.6],
			"hemisphere": 0.25, "environment": 0.5, "fog": "#c4d4de", "fogNear": 130.0, "fogFar": 290.0,
		},
	},
	"switchyard": {
		"name": "Switchyard",
		"file": "res://assets/levels/switchyard.glb",
		"blurb": "194 × 172 metres · 30-foot vert halfpipe, 20-foot transitions, 15-foot spine, deep flow bowl, 24 stairs and a sweeping boardslide rail · RIFT board",
		"bounds": {"x": 96.75, "z": 85.75, "cx": 5.0, "cz": 6.0},
		"camera_far": 280.0,
		"decals": "Construction|Paint",
		"look": {
			"exposure": 0.76, "sun": 3.3, "sunColor": "#ffead3", "sunDirection": [-0.5, 0.62, -0.6],
			"hemisphere": 0.28, "environment": 0.65, "fog": "#c4d1d4", "fogNear": 210.0, "fogFar": 500.0,
		},
	},
	"megaramp": {
		"name": "Mega Ramp",
		"file": "res://assets/levels/megaramp.glb",
		"blurb": "Competition mega ramp · 25 m roll-in, the big gap and a practice gap, a vert quarter pipe · RIFT board",
		"bounds": {"x": 31.5, "z": 81.5, "cx": 0.0, "cz": -60.0},
		"camera_far": 280.0,
		"look": {
			"exposure": 0.74, "sun": 3.4, "sunColor": "#ffdcb4", "sunDirection": [-0.62, 0.5, -0.6],
			"hemisphere": 0.25, "environment": 0.5, "fog": "#c4d4de", "fogNear": 130.0, "fogFar": 290.0,
		},
	},
	"flightline": {
		"name": "Flightline",
		"file": "res://assets/levels/flightline.glb",
		"blurb": "1 km downhill Big Air circuit · Ten linked gaps from 8 to 32 m, a shorter-gap route, four gap-spanning rails and a 10.5 m vert finish · RIFT board",
		"bounds": {"x": 86.0, "z": 566.37, "cx": 4.0, "cz": -496.37},
		"camera_far": 1500.0,
		"decals": "Paint",
		# A timed run: the clock starts as you ride off the top (the lip of the drop-in) and stops as you cross the finish line, just before
		# the vert. A gate is a line across the whole track: pos (its middle), forward (the way you cross it), half_width, and an optional min_y.
		"run": {
			"start": {"pos": [6.125, 186.0, 29.5], "forward": [0.0, 0.0, -1.0], "half_width": 15.9, "min_y": 150.0},
			"finish": {"pos": [6.125, 11.2, -929.0], "forward": [0.0, 0.0, -1.0], "half_width": 16.2},
		},
		"look": {
			"exposure": 0.74, "sun": 3.4, "sunColor": "#ffdcb4", "sunDirection": [-0.62, 0.5, -0.6],
			"hemisphere": 0.25, "environment": 0.5, "fog": "#c4d4de", "fogNear": 320.0, "fogFar": 1300.0,
		},
	},
}

const HUB := "hub"
const PLAYABLE := ["gravesend", "gravesendnight", "foundry", "breakwater", "switchyard", "megaramp", "flightline"]   # the levels on the TV, in channel order
const SETTINGS := "user://settings.cfg"

# The level the next scene should open on (set by go_to); empty means the house.
static var next_id := ""


# Remembers where the player went, and sets it up for the scene that is about to be loaded.
static func go_to(id: String) -> void:
	next_id = id
	if PLAYABLE.has(id):
		save(id)


# What a freshly started scene opens on: the level asked for by go_to, otherwise the house.
static func take_next() -> String:
	var id := next_id if LEVELS.has(next_id) else HUB
	next_id = ""
	return id


# The last level that was played (the TV opens on it), or the first one.
static func saved() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		var id: String = config.get_value("game", "level", PLAYABLE[0])
		if PLAYABLE.has(id):
			return id
	return PLAYABLE[0]


static func save(id: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	config.set_value("game", "level", id)
	config.save(SETTINGS)


# The channel after this one (wrapping), in the TV's order.
static func next_channel(id: String, step := 1) -> String:
	return PLAYABLE[posmod(PLAYABLE.find(id) + step, PLAYABLE.size())]
