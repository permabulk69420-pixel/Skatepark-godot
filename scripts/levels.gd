# The levels the game can load. Each entry says where its model is and the few things that differ per level: the play area the skater
# is kept inside (half-extents x/z around an optional centre cx/cz), the intro text, and `look` (optional) to override the lighting:
# toneMapping ("aces"; anything else is plain linear), exposure, sun (intensity), sunColor, sunDirection ([x, y, z] towards the sun),
# hemisphere (fill), fog (colour), fogNear, fogFar.
# Same layout as the web build's levels.js, so more levels can be added one entry at a time.
class_name Levels
extends RefCounted

const LEVELS := {
	# The house: a place to walk around, with the TV that picks the level. `blockout` builds a plain stand-in (scripts/hub_blockout.gd) until
	# the real model is at `file`.
	"hub": {
		"name": "Home",
		"file": "res://assets/levels/hub.glb",
		"blockout": true,
		"blurb": "Walk to the TV, pick up the remote, choose a level · the half pipe is out the back · hold the left menu button to come back here",
		"bounds": {"x": 20.0, "z": 21.0, "cx": 0.0, "cz": -9.0},
		"camera_far": 400.0,
		"look": {
			"exposure": 0.8, "sun": 2.6, "sunColor": "#ffe6c4", "sunDirection": [-0.45, 0.65, -0.55],
			"hemisphere": 0.45, "environment": 0.4, "fog": "#c4d4de", "fogNear": 120.0, "fogFar": 300.0,
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
		"look": {
			"exposure": 0.74, "sun": 3.4, "sunColor": "#ffdcb4", "sunDirection": [-0.62, 0.5, -0.6],
			"hemisphere": 0.25, "environment": 0.5, "fog": "#c4d4de", "fogNear": 320.0, "fogFar": 1300.0,
		},
	},
}

const HUB := "hub"
const PLAYABLE := ["gravesend", "foundry", "breakwater", "megaramp", "flightline"]   # the levels on the TV, in channel order
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
