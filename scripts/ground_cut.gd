# Pieces that sit down in the ground (a bowl) open the ground themselves, in any level: wherever one stands, the level's own floor
# (what lies about as high as its rim and faces up) has the piece's outline cut out of it, so that ground runs right up to the rim and
# nothing of it covers the bowl. The cut is made on the level's meshes and its collision when the level is read (LevelLoader), and on
# the meshes alone (what you see) when a piece is put down in build mode; the collision follows when the level is loaded again.
class_name GroundCut
extends RefCounted

const BELOW := 0.6          # ground from this far under a rim…
const ABOVE := 0.15         # …to this far over it is cut
const FLAT := 0.7           # and only where it faces up at least this much (a floor, not the side of something)
const EDGE_STEP := 0.25     # metres between the points along an outline (so the new triangles keep to it)
const CATCH_DEPTH := 3.0    # an unseen floor this far under each hole, in case its piece is picked up and carried off


class Hole:
	var outline: PackedVector2Array   # on the ground (x, z), in the level's own space
	var rim := 0.0                    # the height of the ground round it
	var box: Rect2


# The holes the sunken pieces under `root` need, where they stand now.
static func holes(root: Node3D) -> Array:
	var found: Array = []
	for piece in BuildPieces.find_all(root):
		var outline: PackedVector2Array = BuildPieces.info(piece).get("sunken", PackedVector2Array())
		if outline.is_empty() or piece.is_queued_for_deletion():
			continue
		var xf := _to_root(piece, root)
		var hole := Hole.new()
		hole.rim = xf.origin.y
		for p in outline:
			var at: Vector3 = xf * Vector3(p.x, 0.0, p.y)
			hole.outline.append(Vector2(at.x, at.z))
		hole.outline = _dense(hole.outline)
		hole.box = Rect2(hole.outline[0], Vector2.ZERO)
		for p in hole.outline:
			hole.box = hole.box.expand(p)
		found.append(hole)
	return found


# Cuts `meshes` (MeshInstance3D under `root`) round `found` holes. Each keeps its uncut mesh, so it can be cut again from that when a
# piece moves (and goes back to it when nothing needs it cut any more).
static func cut(root: Node3D, meshes: Array, found: Array) -> void:
	for mi: MeshInstance3D in meshes:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var source: Mesh = mi.get_meta("uncut", mi.mesh)
		var to_root := _to_root(mi, root)
		var box := to_root * source.get_aabb()
		var touched: Array = []
		for hole: Hole in found:
			if hole.box.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z), true) \
					and box.position.y <= hole.rim + ABOVE and box.end.y >= hole.rim - BELOW:
				touched.append(hole)
		if touched.is_empty():
			if mi.has_meta("uncut"):
				mi.mesh = source
				mi.remove_meta("uncut")
			continue
		mi.set_meta("uncut", source)
		mi.mesh = _cut_mesh(source, to_root, touched)


# Unseen floors under the holes, as COL_ meshes under `root` (for LevelLoader to read with the rest of the collision).
static func catch_floors(root: Node3D, found: Array) -> Array:
	var floors: Array = []
	for hole: Hole in found:
		var faces := PackedVector3Array()
		var tris := Geometry2D.triangulate_polygon(hole.outline)
		for i in range(0, tris.size(), 3):
			for k in [0, 2, 1]:
				var p := hole.outline[tris[i + k]]
				faces.append(Vector3(p.x, hole.rim - CATCH_DEPTH, p.y))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var floor := MeshInstance3D.new()
		floor.name = "COL_GroundCut_Catch"
		floor.mesh = mesh
		floor.visible = false
		root.add_child(floor, true)
		floor.global_transform = root.global_transform
		floors.append(floor)
	return floors


static func _to_root(node: Node3D, root: Node3D) -> Transform3D:
	if node.is_inside_tree() and root.is_inside_tree():
		return root.global_transform.affine_inverse() * node.global_transform
	var xf := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		xf = (at as Node3D).transform * xf
		at = at.get_parent()
	return xf


# The outline with points no further apart than EDGE_STEP.
static func _dense(outline: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var n := maxi(1, ceili(a.distance_to(b) / EDGE_STEP))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	return out


# A copy of `source` with the holes cut out of its floor triangles. Everything else is copied as it was; the new triangles round a hole
# take their position, normal, UVs and colour from the triangle they were cut from.
static func _cut_mesh(source: Mesh, to_root: Transform3D, touched: Array) -> ArrayMesh:
	var from_root := to_root.affine_inverse()
	var out := ArrayMesh.new()
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			for i in verts.size():
				index.append(i)
		var kept := PackedInt32Array()
		var added := {}   # attribute -> values appended for the new triangles' vertices
		for t in range(0, index.size() - 2, 3):
			var ids := [index[t], index[t + 1], index[t + 2]]
			var p: Array = [to_root * verts[ids[0]], to_root * verts[ids[1]], to_root * verts[ids[2]]]
			var holes_here := _holes_over(p, touched)
			if holes_here.is_empty():
				kept.append_array(ids)
				continue
			for tri in _cut_triangle(p, holes_here):
				for q: Vector2 in tri:
					var w := _weights(q, p)
					kept.append(verts.size() + _count(added))
					_add_vertex(added, arrays, ids, w, from_root * (p[0] * w.x + p[1] * w.y + p[2] * w.z))
		var new_arrays := arrays.duplicate()
		for attribute in added:
			new_arrays[attribute] = _join(arrays[attribute], added[attribute])
		if kept.is_empty():   # (keep the surface, so the mesh's materials stay where they were)
			kept = PackedInt32Array([0, 0, 0])
		new_arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		out.surface_set_material(s, source.surface_get_material(s))
	return out


# The holes a triangle (in the level's space) is floor for and reaches into.
static func _holes_over(p: Array, touched: Array) -> Array:
	var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if n.length_squared() < 1e-12 or absf(n.normalized().y) < FLAT:
		return []
	var tri := PackedVector2Array([Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z), Vector2(p[2].x, p[2].z)])
	var rect := Rect2(tri[0], Vector2.ZERO).expand(tri[1]).expand(tri[2])
	var found: Array = []
	for hole: Hole in touched:
		var low: float = minf(p[0].y, minf(p[1].y, p[2].y))
		var high: float = maxf(p[0].y, maxf(p[1].y, p[2].y))
		if high > hole.rim + ABOVE or low < hole.rim - BELOW or not rect.intersects(hole.box, true):
			continue
		if not Geometry2D.intersect_polygons(tri, hole.outline).is_empty():
			found.append(hole)
	return found


# What is left of a triangle (on the ground, x z) once the holes are taken out of it, as triangles wound as it was.
static func _cut_triangle(p: Array, holes_here: Array) -> Array:
	var tri := PackedVector2Array([Vector2(p[0].x, p[0].z), Vector2(p[1].x, p[1].z), Vector2(p[2].x, p[2].z)])
	var points := PackedVector2Array(tri)
	for hole: Hole in holes_here:
		var o := hole.outline
		for i in o.size():
			var a := o[i]
			var b := o[(i + 1) % o.size()]
			if Geometry2D.is_point_in_polygon(a, tri):
				points.append(a)
			for k in 3:   # where the outline crosses the triangle's edges
				var hit = Geometry2D.segment_intersects_segment(a, b, tri[k], tri[(k + 1) % 3])
				if hit != null:
					points.append(hit)
	var clockwise := (tri[1] - tri[0]).cross(tri[2] - tri[0]) < 0.0
	var result: Array = []
	var ids := Geometry2D.triangulate_delaunay(points)
	for i in range(0, ids.size(), 3):
		var piece := PackedVector2Array([points[ids[i]], points[ids[i + 1]], points[ids[i + 2]]])
		var centre := (piece[0] + piece[1] + piece[2]) / 3.0
		if absf((piece[1] - piece[0]).cross(piece[2] - piece[0])) < 1e-9 or not Geometry2D.is_point_in_polygon(centre, tri):
			continue
		var open := false
		for hole: Hole in holes_here:
			if Geometry2D.is_point_in_polygon(centre, hole.outline):
				open = true
		if open:
			continue
		if ((piece[1] - piece[0]).cross(piece[2] - piece[0]) < 0.0) != clockwise:
			piece = PackedVector2Array([piece[0], piece[2], piece[1]])
		result.append(piece)
	return result


# Barycentric weights of `q` (x, z) in the triangle `p`.
static func _weights(q: Vector2, p: Array) -> Vector3:
	var a := Vector2(p[0].x, p[0].z)
	var b := Vector2(p[1].x, p[1].z)
	var c := Vector2(p[2].x, p[2].z)
	var d := (b - a).cross(c - a)
	if absf(d) < 1e-12:
		return Vector3(1, 0, 0)
	var wb := (q - a).cross(c - a) / d
	var wc := (b - a).cross(q - a) / d
	return Vector3(1.0 - wb - wc, wb, wc)


static func _count(added: Dictionary) -> int:
	var verts = added.get(Mesh.ARRAY_VERTEX)
	return 0 if verts == null else verts.size()


# Appends one vertex (at `local`) to the new vertices, with each attribute the source has blended from the triangle's three.
static func _add_vertex(added: Dictionary, arrays: Array, ids: Array, w: Vector3, local: Vector3) -> void:
	_append(added, Mesh.ARRAY_VERTEX, PackedVector3Array(), local)
	if arrays[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		_append(added, Mesh.ARRAY_NORMAL, PackedVector3Array(), (n[ids[0]] * w.x + n[ids[1]] * w.y + n[ids[2]] * w.z).normalized())
	if arrays[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var v := Vector3.ZERO
		for k in 3:
			v += Vector3(tg[ids[k] * 4], tg[ids[k] * 4 + 1], tg[ids[k] * 4 + 2]) * w[k]
		v = v.normalized()
		for value in [v.x, v.y, v.z, tg[ids[0] * 4 + 3]]:
			_append(added, Mesh.ARRAY_TANGENT, PackedFloat32Array(), value)
	for uv_array in [Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arrays[uv_array] != null:
			var uv: PackedVector2Array = arrays[uv_array]
			_append(added, uv_array, PackedVector2Array(), uv[ids[0]] * w.x + uv[ids[1]] * w.y + uv[ids[2]] * w.z)
	if arrays[Mesh.ARRAY_COLOR] != null:
		var col: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_append(added, Mesh.ARRAY_COLOR, PackedColorArray(), col[ids[0]] * w.x + col[ids[1]] * w.y + col[ids[2]] * w.z)


static func _append(added: Dictionary, attribute: int, empty, value) -> void:
	var values = added.get(attribute, empty)
	values.append(value)
	added[attribute] = values


static func _join(a, b):
	var joined = a.duplicate()
	joined.append_array(b)
	return joined
