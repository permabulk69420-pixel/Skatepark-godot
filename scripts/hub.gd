# The house as a level: builds its scene (the real model if there is one, otherwise the stand-in), puts the half pipe on the slab, and
# looks after what lives in it: the lamps, the TV with its remote, the boards on the shop wall.
class_name Hub
extends RefCounted

const INDOOR_LAYER := 2          # render layer bit for what is inside: the sun does not reach it, the lamps do
const INDOOR := ["Interior_", "Cabinet_", "Shell_Timber_Painted_Interior", "TV_Screen"]
const LAMP_COLOUR := Color("ffc68a")
const LAMP_GAIN := 2.2

var level: LevelLoader
var tv: HubTv
var lamps: Array[OmniLight3D] = []


# The scene to read as the house: the model at the hub's file when it exists, otherwise the blockout, with the half pipe added to either,
# and everything build mode has moved or added where it was left.
static func build_root() -> Node3D:
	var info: Dictionary = Levels.LEVELS[Levels.HUB]
	var root: Node3D = null
	if ResourceLoader.exists(info.file):
		var packed := load(info.file) as PackedScene
		if packed != null:
			root = packed.instantiate()
	if root == null:
		root = HubBlockout.build()
	HubDriveway.add_to(root)
	HubRoads.add_to(root)
	HubRamp.add_to(root)
	BuildPieces.mark_house(root)
	HubLayout.apply(root, HubLayout.read())
	return root


# `level` must already be loaded (in the tree).
func _init(p_level: LevelLoader, parent: Node3D, vr := false) -> void:
	level = p_level
	# no shadows, so without this the sun shines straight through the roof onto everything inside and the room looks flat and cold
	for node in level.root.find_children("*", "MeshInstance3D", true, false):
		for prefix: String in INDOOR:
			if node.name.begins_with(prefix):
				(node as MeshInstance3D).layers = INDOOR_LAYER
	_light_pieces()
	var sun := parent.find_child("Sun", false, false) as DirectionalLight3D
	if sun != null:
		sun.light_cull_mask &= ~INDOOR_LAYER
	for marker in level.markers_with("light"):
		var lamp := OmniLight3D.new()
		lamp.light_energy = (marker.get_meta("extras", {}) as Dictionary).get("energy", 0.8) * LAMP_GAIN
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.6   # falls off faster than real, so each lamp lights its own patch of the room
		lamp.shadow_enabled = false
		lamp.light_color = LAMP_COLOUR
		marker.add_child(lamp)
		lamps.append(lamp)
	var screen := level.root.find_child("TV_Screen", true, false) as MeshInstance3D
	var spots := level.markers_with("remote_spot")
	if screen != null and not spots.is_empty():
		tv = HubTv.new(screen, spots[0], parent, Levels.saved(), vr)


# Build mode's pieces are lit as indoors when they stand inside the house (over its floor), and by the sun when they are out in the yard.
func _light_pieces() -> void:
	var inside := AABB()
	var first := true
	var pieces := BuildPieces.find_all(level.root)
	for node in level.render_meshes:
		var mesh := node as MeshInstance3D
		if not mesh.name.begins_with("Interior_") or pieces.has(mesh):
			continue
		var box := mesh.global_transform * mesh.get_aabb()
		inside = box if first else inside.merge(box)
		first = false
	if first:
		return
	for piece in pieces:
		var at := piece.global_position
		var indoors := at.x > inside.position.x and at.x < inside.end.x and at.z > inside.position.z and at.z < inside.end.z
		var meshes: Array = piece.find_children("*", "MeshInstance3D", true, false)
		if piece is MeshInstance3D:
			meshes.append(piece)
		for mesh: MeshInstance3D in meshes:
			mesh.layers = INDOOR_LAYER if indoors else 1
