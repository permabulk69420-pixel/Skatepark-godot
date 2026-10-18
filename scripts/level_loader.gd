# Reads a level file (a GLB prepared by tools/prepare-level.mjs) into what the game needs: the visible park, the collision
# bodies the sim rides on, the grind paths, the spawn point and the LOD chunks. The park builder tags nodes with an "extras" role.
class_name LevelLoader
extends RefCounted

var root: Node3D
var render_meshes: Array = []       # MeshInstance3D, everything you see
var collision_bodies: Array[StaticBody3D] = []
var grind_nodes: Array = []
var loop_nodes: Array = []
var spawn_pos := Vector3(0.0, 0.045, 40.0)
var spawn_heading := 0.0
var lods: LodSet


# Loads `path` and adds it under `parent` (which must already be in the scene tree). Returns null if the file is missing.
static func load_level(path: String, parent: Node3D) -> LevelLoader:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var level := LevelLoader.new()
	level.root = packed.instantiate()
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
		elif role == "spawn" and node is Node3D:
			level.spawn_pos = (node as Node3D).global_position
			level.spawn_heading = extras.get("heading_radians", 0.0)
		elif node is MeshInstance3D:
			if role == "collision" or node.name.begins_with("COL_"):
				collision_meshes.append(node)
			else:
				level.render_meshes.append(node)
	level.collision_bodies = SkateWorld.add_colliders(level.root, collision_meshes)
	for mesh in collision_meshes:
		mesh.queue_free()   # the collision shape has its own copy of the triangles; the mesh itself is never drawn
	level.lods = LodSet.new(level.render_meshes)
	return level
