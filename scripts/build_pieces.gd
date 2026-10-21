# What build mode can move about the house and the yard: the half pipe, the couch and the rug that come with the house, and the pieces
# you can add (the arcade machine, a flat rail). Each piece is one node with everything it needs under it (its look, its COL_ collision
# mesh, its grind_path markers), so moving that node moves all of it, and LevelLoader reads it like any other part of the house.
class_name BuildPieces
extends RefCounted

const META := "build_piece"            # on each piece's node: {"id", "kind" ("" for the house's own), "name", "colliders"}
const ADDABLE := ["arcade", "rail"]
const ARCADE_SCENE := "res://assets/arcade/arcade_machine.glb"
const RAIL_LENGTH := 3.0
const RAIL_HEIGHT := 0.33              # metres from the ground to the top of the bar
const RAIL_RADIUS := 0.025
const RAIL_LEG_INSET := 0.3            # each leg this far in from an end of the bar
const STEEL := Color("3a3f44")
const COUCH_MARGIN := 0.2              # the couch's collision box is looked for this far around the couch (it stands taller than the couch)


static func caption(kind: String) -> String:
	match kind:
		"arcade": return "Arcade machine"
		"rail": return "Flat rail"
	return kind


# Marks the house's own movable things (`root`: the house, before it is loaded). The couch's collision box is part of COL_Walls in the
# house file, so it is cut out of there and given to the couch.
static func mark_house(root: Node3D) -> void:
	var ramp := root.find_child("HalfPipe", true, false) as Node3D
	if ramp != null:
		_mark(ramp, "halfpipe", "", "Half pipe", ["COL_WoodenHalfPipe"])
	var couch := root.find_child("Interior_Couch", true, false) as MeshInstance3D
	if couch != null:
		_mark(couch, "couch", "", "Couch", ["COL_Couch"] if _split_couch(root, couch) else [])
	var rug := root.find_child("Interior_Rug", true, false) as Node3D
	if rug != null:
		_mark(rug, "rug", "", "Rug", [])


static func _mark(node: Node3D, id: String, kind: String, title: String, colliders: Array) -> void:
	node.set_meta(META, {"id": id, "kind": kind, "name": title, "colliders": colliders})


# Every piece under `root`.
static func find_all(root: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.has_meta(META):
			found.append(node)
			continue
		stack.append_array(node.get_children())
	return found


static func info(piece: Node3D) -> Dictionary:
	return piece.get_meta(META, {})


# A new piece of `kind`, named after `id`, standing at its own origin (on the ground, facing -Z).
static func make(kind: String, id: String) -> Node3D:
	var piece := Node3D.new()
	piece.name = "Build_" + id
	var colliders: Array = []
	match kind:
		"arcade":
			var model := (load(ARCADE_SCENE) as PackedScene).instantiate() as Node3D
			piece.add_child(model)
			var box := bounds(piece)
			var collider := _collision_mesh("COL_Build_" + id, _box_faces(box))
			piece.add_child(collider)
			colliders.append(collider.name)
		"rail":
			_build_rail(piece, id)
	_mark(piece, id, kind, caption(kind), colliders)
	return piece


# A round steel bar on two legs, grindable along its whole length.
static func _build_rail(piece: Node3D, id: String) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = STEEL
	steel.metallic = 0.8
	steel.roughness = 0.35
	var centre := RAIL_HEIGHT - RAIL_RADIUS
	var bar := CylinderMesh.new()
	bar.top_radius = RAIL_RADIUS
	bar.bottom_radius = RAIL_RADIUS
	bar.height = RAIL_LENGTH
	bar.radial_segments = 16
	bar.rings = 1
	_add_mesh(piece, "Rail_Bar", bar, steel, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, centre, 0.0)))
	var leg := CylinderMesh.new()
	leg.top_radius = 0.02
	leg.bottom_radius = 0.02
	leg.height = centre
	leg.radial_segments = 10
	leg.rings = 1
	var foot := BoxMesh.new()
	foot.size = Vector3(0.12, 0.012, 0.3)
	for side in [-1.0, 1.0]:
		var x: float = side * (RAIL_LENGTH * 0.5 - RAIL_LEG_INSET)
		_add_mesh(piece, "Rail_Leg", leg, steel, Transform3D(Basis.IDENTITY, Vector3(x, centre * 0.5, 0.0)))
		_add_mesh(piece, "Rail_Foot", foot, steel, Transform3D(Basis.IDENTITY, Vector3(x, 0.006, 0.0)))
	var path := Node3D.new()
	path.name = "PATH_Build_" + id
	var half := RAIL_LENGTH * 0.5
	path.set_meta("extras", {"role": "grind_path", "kind": "rail", "closed": false, "radius": RAIL_RADIUS,
		"points": [-half, centre, 0.0, half, centre, 0.0]})
	piece.add_child(path)


static func _add_mesh(parent: Node3D, node_name: String, mesh: Mesh, material: Material, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = material
	mi.transform = xf
	parent.add_child(mi, true)


# The box around everything you can see of `piece`, in the piece's own frame (works before it is in the tree).
static func bounds(piece: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[piece, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and not node.name.begins_with("COL_") and (node as MeshInstance3D).mesh != null:
			var part: AABB = xf * (node as MeshInstance3D).get_aabb()
			box = part if first else box.merge(part)
			first = false
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return box


# The couch's box is the triangles of COL_Walls that lie wholly inside the couch: they are moved into a COL_Couch under the couch.
static func _split_couch(root: Node3D, couch: MeshInstance3D) -> bool:
	var walls := root.find_child("COL_Walls", true, false) as MeshInstance3D
	if walls == null:
		return false
	var couch_xf := _to_root(couch, root)
	var walls_xf := _to_root(walls, root)
	var around := (couch_xf * couch.get_aabb()).grow(COUCH_MARGIN)
	var faces := walls.mesh.get_faces()
	var kept := PackedVector3Array()
	var taken := PackedVector3Array()
	var to_couch := couch_xf.affine_inverse() * walls_xf
	for i in range(0, faces.size() - 2, 3):
		var a := walls_xf * faces[i]
		var b := walls_xf * faces[i + 1]
		var c := walls_xf * faces[i + 2]
		if around.has_point(a) and around.has_point(b) and around.has_point(c):
			taken.append_array([to_couch * faces[i], to_couch * faces[i + 1], to_couch * faces[i + 2]])
		else:
			kept.append_array([faces[i], faces[i + 1], faces[i + 2]])
	if taken.is_empty():
		return false
	walls.mesh = _faces_mesh(kept)
	couch.add_child(_collision_mesh("COL_Couch", taken))
	return true


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


static func _box_faces(box: AABB) -> PackedVector3Array:
	var mesh := BoxMesh.new()
	mesh.size = box.size
	var faces := mesh.get_faces()
	var centre := box.get_center()
	for i in faces.size():
		faces[i] += centre
	return faces


static func _faces_mesh(faces: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _collision_mesh(node_name: String, faces: PackedVector3Array) -> MeshInstance3D:
	var collider := MeshInstance3D.new()
	collider.name = node_name
	collider.mesh = _faces_mesh(faces)
	collider.visible = false   # (never drawn: a piece added in build mode keeps it until the house is loaded again and it is read)
	collider.set_meta("extras", {"role": "collision"})
	return collider
