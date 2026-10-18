# The house as a level: builds its scene (the real model if there is one, otherwise the stand-in), puts the half pipe on the slab, and
# looks after what lives in it: the lamps, the TV with its remote, the boards on the shop wall.
class_name Hub
extends RefCounted

var level: LevelLoader
var tv: HubTv
var lamps: Array[OmniLight3D] = []


# The scene to read as the house: the model at the hub's file when it exists, otherwise the blockout, with the half pipe added to either.
static func build_root() -> Node3D:
	var info: Dictionary = Levels.LEVELS[Levels.HUB]
	var root: Node3D = null
	if ResourceLoader.exists(info.file):
		var packed := load(info.file) as PackedScene
		if packed != null:
			root = packed.instantiate()
	if root == null:
		root = HubBlockout.build()
	HubRamp.add_to(root)
	return root


# `level` must already be loaded (in the tree).
func _init(p_level: LevelLoader, parent: Node3D, vr := false) -> void:
	level = p_level
	for marker in level.markers_with("light"):
		var lamp := OmniLight3D.new()
		lamp.light_energy = (marker.get_meta("extras", {}) as Dictionary).get("energy", 0.8)
		lamp.omni_range = 9.0
		lamp.shadow_enabled = false
		lamp.light_color = Color("ffe2b8")
		marker.add_child(lamp)
		lamps.append(lamp)
	var screen := level.root.find_child("TV_Screen", true, false) as MeshInstance3D
	var spots := level.markers_with("remote_spot")
	if screen != null and not spots.is_empty():
		tv = HubTv.new(screen, spots[0], parent, Levels.saved(), vr)
