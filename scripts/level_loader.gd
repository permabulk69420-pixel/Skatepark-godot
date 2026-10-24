# Reads a level file (a GLB prepared by tools/prepare-level.mjs) into what the game needs: the visible park, the collision
# bodies the sim rides on, the grind paths, the spawn point and the LOD chunks. The park builder tags nodes with an "extras" role.
class_name LevelLoader
extends RefCounted

const MARKER_ROLES := ["remote_spot", "board_slot", "ramp_pad", "light"]
const START_SPAWNS := ["Spawn_Entrance", "Spawn_Hub"]   # the spawn nodes the game starts at (any other is ignored)

var root: Node3D
var render_meshes: Array = []       # MeshInstance3D, everything you see
var collision_bodies: Array[StaticBody3D] = []
var grind_nodes: Array = []
var loop_nodes: Array = []
var spawn_pos := Vector3(0.0, 0.045, 40.0)
var spawn_heading := 0.0
var lods: LodSet
var markers: Array = []             # Node3D: the empties a level uses to say where things go (remote_spot, board_slot, ramp_pad, light)
var ground: Array = []              # MeshInstance3D: what you see of the level itself (not of the build pieces in it): what GroundCut cuts


# Loads `path` and adds it under `parent` (which must already be in the scene tree). Returns null if the file is missing.
# `decals`: a regex on material names; those materials are paint lying flat on other surfaces (see shaders/decal.gdshader).
static func load_level(path: String, parent: Node3D, decals := "") -> LevelLoader:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return from_root(packed.instantiate(), parent, decals)


# The same for a scene that is already built (the house's stand-in is made in code): `root` is read as if it had just been imported.
static func from_root(root: Node3D, parent: Node3D, decals := "") -> LevelLoader:
	var level := LevelLoader.new()
	level.root = root
	parent.add_child(level.root)
	var collision_meshes: Array = []
	var stack: Array = [level.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var extras: Dictionary = node.get_meta("extras", {})
		var role: String = extras.get("role", "")
		if role == "grind_path":
			level.grind_nodes.append(node)
		elif role == "loop_path":
			level.loop_nodes.append(node)
		elif role in MARKER_ROLES and node is Node3D:
			level.markers.append(node)
		elif role == "spawn" and node is Node3D:
			# a level can have several (Foundry: the tower and the plaza), but the web build only starts at "Spawn_Entrance"; a level
			# without one (Switchyard) starts at the default point above. The house has its own.
			if node.name in START_SPAWNS:
				level.spawn_pos = (node as Node3D).global_position
				level.spawn_heading = extras.get("heading_radians", 0.0)
		elif node is MeshInstance3D:
			if role == "collision" or node.name.begins_with("COL_"):
				collision_meshes.append(node)
			else:
				level.render_meshes.append(node)
	# Pieces that sit down in the ground (a bowl) open it where they stand, in what you see and in the collision.
	var pieces := BuildPieces.find_all(level.root)
	var own := func(node: Node) -> bool:
		for piece in pieces:
			if piece == node or piece.is_ancestor_of(node):
				return false
		return true
	level.ground = level.render_meshes.filter(own)
	var holes := GroundCut.holes(level.root)
	if not holes.is_empty():
		GroundCut.cut(level.root, level.ground, holes)
		GroundCut.cut(level.root, collision_meshes.filter(own), holes)
		collision_meshes.append_array(GroundCut.catch_floors(level.root, holes))
	level.collision_bodies = SkateWorld.add_colliders(level.root, collision_meshes)
	for mesh in collision_meshes:
		mesh.queue_free()   # the collision shape has its own copy of the triangles; the mesh itself is never drawn
	if decals != "":
		level._make_decals(decals)
	level.lods = LodSet.new(level.render_meshes)
	return level


# Swaps the materials whose names match `pattern` for the decal shader, keeping their colour.
func _make_decals(pattern: String) -> void:
	var matcher := RegEx.create_from_string(pattern)
	var shader := load("res://shaders/decal.gdshader") as Shader
	var swapped := {}   # original material -> its decal replacement (shared by every mesh that used it)
	for mesh_instance: MeshInstance3D in render_meshes:
		for surface in mesh_instance.mesh.get_surface_count():
			var original := mesh_instance.mesh.surface_get_material(surface)
			if not original is BaseMaterial3D or matcher.search(original.resource_name) == null:
				continue
			if not swapped.has(original):
				var decal := ShaderMaterial.new()
				decal.shader = shader
				decal.set_shader_parameter("albedo", (original as BaseMaterial3D).albedo_color)
				decal.set_shader_parameter("roughness", (original as BaseMaterial3D).roughness)
				swapped[original] = decal
			mesh_instance.set_surface_override_material(surface, swapped[original])


# The markers of one role, in name order (BoardSlot_01, BoardSlot_02, …).
func markers_with(role: String) -> Array:
	var found: Array = []
	for node: Node3D in markers:
		if (node.get_meta("extras", {}) as Dictionary).get("role", "") == role:
			found.append(node)
	found.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	return found
