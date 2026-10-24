# The Slab: a blank square of concrete in an open field, to build a park on yourself. It is made in code and read by LevelLoader like an
# imported file: the concrete and the field round it, their COL_ collision, the spawn, and whatever build mode has added (HubLayout).
# A piece that sits down in the ground (a bowl) has its outline cut out of the concrete, so the concrete runs right up to its rim.
class_name Slab
extends RefCounted

const SIZE := 100.0             # metres along each side of the concrete
const TILE := 4.0               # metres the concrete's texture covers before it repeats
const FIELD := 600.0            # metres along each side of the field round it
const FIELD_TILE := 8.0
const FIELD_DROP := 0.02        # the field lies this far below the concrete
const CATCH := -2.5             # an unseen floor under everything, below the deepest bowl (in case one is picked up off its hole)
const EDGE_STEP := 0.25         # metres between the points along a hole's edge (so the triangles keep to it)
const SPAWN := Vector3(0.0, 0.03, 20.0)   # on the concrete, facing its middle
const CONCRETE := ["res://assets/levels/switchyard_concrete_floor_base.webp", "res://assets/levels/switchyard_concrete_floor_normal.webp",
	"res://assets/levels/switchyard_concrete_floor_orm.webp"]
const GROUND := ["res://assets/levels/hub_ground_base.jpg", "res://assets/levels/hub_ground_normal.png", "res://assets/levels/hub_ground_orm.jpg"]


static func build_root() -> Node3D:
	var root := Node3D.new()
	root.name = "Slab"
	var spawn := Node3D.new()
	spawn.name = "Spawn_Entrance"
	spawn.position = SPAWN
	spawn.set_meta("extras", {"role": "spawn", "heading_radians": 0.0})
	root.add_child(spawn)
	HubLayout.apply(root, HubLayout.read(Levels.SLAB))
	_add_floor(root, "Slab_Concrete", floor_mesh(SIZE, _holes(root)), 0.0, _material(CONCRETE, SIZE / TILE))
	_add_floor(root, "Slab_Field", floor_mesh(FIELD, [_square(Transform3D.IDENTITY, Vector2(SIZE, SIZE) / 2.0)]), -FIELD_DROP, _material(GROUND, FIELD / FIELD_TILE))
	var catch_plane := PlaneMesh.new()
	catch_plane.size = Vector2(SIZE, SIZE)
	var catch_floor := MeshInstance3D.new()
	catch_floor.name = "COL_Slab_Catch"
	catch_floor.mesh = catch_plane
	catch_floor.position.y = CATCH
	catch_floor.visible = false
	root.add_child(catch_floor)
	return root


# Cuts the concrete again round where the sunken pieces stand now (`root`: the Slab, loaded). Only what you see: their collision follows
# when the level is loaded again.
static func open_ground(root: Node3D) -> void:
	var concrete := root.get_node_or_null("Slab_Concrete") as MeshInstance3D
	if concrete != null:
		concrete.mesh = floor_mesh(SIZE, _holes(root))


# The outlines the sunken pieces under `root` need open, on the ground (x, z).
static func _holes(root: Node3D) -> Array:
	var holes: Array = []
	var square := _square(Transform3D.IDENTITY, Vector2(SIZE, SIZE) / 2.0)
	for piece in BuildPieces.find_all(root):
		var outline: PackedVector2Array = BuildPieces.info(piece).get("sunken", PackedVector2Array())
		if outline.is_empty() or piece.is_queued_for_deletion():
			continue
		var xf := piece.transform if not piece.is_inside_tree() else root.global_transform.affine_inverse() * piece.global_transform
		var placed := PackedVector2Array()
		for p in outline:
			var at: Vector3 = xf * Vector3(p.x, 0.0, p.y)
			placed.append(Vector2(at.x, at.z))
		for part in Geometry2D.intersect_polygons(placed, square):   # (only the part on the concrete)
			holes.append(part)
	return holes


# A rectangle on the ground, `half` (x, z) each way from the origin of `xf`.
static func _square(xf: Transform3D, half: Vector2) -> PackedVector2Array:
	var corners := PackedVector2Array()
	for c in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]:
		var p: Vector3 = xf * c
		corners.append(Vector2(p.x, p.z))
	return corners


# A flat square `size` across with `holes` (polygons on the ground) left open, facing up. Its UVs run 0..1 across the square, as a
# PlaneMesh's do.
static func floor_mesh(size: float, holes: Array) -> ArrayMesh:
	var half := size / 2.0
	var points := PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	for hole: PackedVector2Array in holes:
		for i in hole.size():
			var a := hole[i]
			var b := hole[(i + 1) % hole.size()]
			var n := maxi(1, ceili(a.distance_to(b) / EDGE_STEP))
			for k in n:
				points.append(a.lerp(b, float(k) / n))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var triangles := Geometry2D.triangulate_delaunay(points)
	for t in range(0, triangles.size(), 3):
		var tri := [points[triangles[t]], points[triangles[t + 1]], points[triangles[t + 2]]]
		var centre: Vector2 = (tri[0] + tri[1] + tri[2]) / 3.0
		var open := false
		for hole: PackedVector2Array in holes:
			if Geometry2D.is_point_in_polygon(centre, hole):
				open = true
		if open:
			continue
		if (tri[1] - tri[0]).cross(tri[2] - tri[0]) < 0.0:   # (clockwise seen from above: Godot's front)
			tri = [tri[0], tri[2], tri[1]]
		for p: Vector2 in tri:
			st.set_uv(Vector2(p.x / size + 0.5, p.y / size + 0.5))
			st.add_vertex(Vector3(p.x, 0.0, p.y))
	st.generate_tangents()
	return st.commit()


# A floor drawn with `material` at height `y`, and its collision.
static func _add_floor(root: Node3D, node_name: String, mesh: Mesh, y: float, material: Material) -> void:
	var floor := MeshInstance3D.new()
	floor.name = node_name
	floor.mesh = mesh
	floor.material_override = material
	floor.position.y = y
	root.add_child(floor)
	var collider := MeshInstance3D.new()
	collider.name = "COL_" + node_name
	collider.mesh = mesh
	collider.position.y = y
	collider.visible = false
	collider.set_meta("extras", {"role": "collision"})
	root.add_child(collider)


# `textures`: its colour, normal and ORM maps.
static func _material(textures: Array, repeats: float) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(textures[0])
	m.normal_enabled = true
	m.normal_texture = load(textures[1])
	m.orm_texture = load(textures[2])
	m.uv1_scale = Vector3(repeats, repeats, 1.0)
	return m
