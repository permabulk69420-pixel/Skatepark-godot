# The levels the game can load. Each entry says where its model is and the few things that differ per level: the play area the skater
# is kept inside (half-extents x/z around an optional centre cx/cz), the intro text, and `look` (optional) to override the lighting:
# exposure, sun (intensity), sunColor, sunDirection ([x, y, z] towards the sun), hemisphere (fill), fog (colour), fogNear, fogFar.
# Same layout as the web build's levels.js, so more levels can be added one entry at a time.
class_name Levels
extends RefCounted

const LEVELS := {
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
}

const DEFAULT_LEVEL := "gravesend"
