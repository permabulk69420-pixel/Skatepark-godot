# The half pipe out the back of the house, built from code on the empty slab (the "RampPad" empty): a mini ramp with a flat bottom, two
# quarter-circle transitions with vertical lips, a short deck at each end and coping on both lips (the same kind of grind line the
# other levels have). The brief to the house modeller leaves the slab bare so that the ramp is exactly what the skating was matched to.
class_name HubRamp
extends RefCounted

const HEIGHT := 1.5      # also the radius of the transitions
const DECK := 1.2
const FLAT := 8.0
const WIDTH := 5.0
const SEGMENTS := 14
const COPING_RADIUS := 0.035
const PLY_BASE := "res://assets/levels/flightline_competitionply_base.webp"   # the same skate ply the big ramps are made of
const PLY_NORMAL := "res://assets/levels/flightline_competitionply_normal.webp"
const SHEET := Vector2(2.44, 1.22)   # one sheet of ply: along the pipe, across it
const COPING := Color("b9bcc0")


# One triangle, wound so that its front face looks along `facing` (Godot: front faces are clockwise).
static func _tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) < 0.0:
		var t := b
		b = c
		c = t
	faces.append(a)
	faces.append(b)
	faces.append(c)


# The surface as strips across the pipe: profile points (x along the pipe, y up) with the way each faces (into the pipe).
static func _profile() -> Array:
	var strips: Array = []   # { a, b, na, nb }: Vector2 points and normals
	var half := FLAT / 2.0
	var lip_w := -(half + HEIGHT)
	strips.append({"a": Vector2(lip_w - DECK, HEIGHT), "b": Vector2(lip_w, HEIGHT), "na": Vector2.UP, "nb": Vector2.UP})
	for i in SEGMENTS:
		var p0 := PI / 2.0 * float(i) / SEGMENTS
		var p1 := PI / 2.0 * float(i + 1) / SEGMENTS
		var c := Vector2(-half, HEIGHT)
		strips.append({
			"a": c + HEIGHT * Vector2(-cos(p0), -sin(p0)), "b": c + HEIGHT * Vector2(-cos(p1), -sin(p1)),
			"na": Vector2(cos(p0), sin(p0)), "nb": Vector2(cos(p1), sin(p1)),
		})
	strips.append({"a": Vector2(-half, 0.0), "b": Vector2(half, 0.0), "na": Vector2.UP, "nb": Vector2.UP})
	for i in SEGMENTS:
		var p0 := PI / 2.0 * float(i) / SEGMENTS
		var p1 := PI / 2.0 * float(i + 1) / SEGMENTS
		var c := Vector2(half, HEIGHT)
		strips.append({
			"a": c + HEIGHT * Vector2(cos(p0), -sin(p0)), "b": c + HEIGHT * Vector2(cos(p1), -sin(p1)),
			"na": Vector2(-cos(p0), sin(p0)), "nb": Vector2(-cos(p1), sin(p1)),
		})
	var lip_e := half + HEIGHT
	strips.append({"a": Vector2(lip_e, HEIGHT), "b": Vector2(lip_e + DECK, HEIGHT), "na": Vector2.UP, "nb": Vector2.UP})
	return strips


# Adds the ramp to a house scene that has a "RampPad" empty. Returns false if there is no pad.
static func add_to(root: Node3D) -> bool:
	var pad := root.find_child("RampPad", true, false) as Node3D
	if pad == null:
		return false
	var heading: float = (pad.get_meta("extras", {}) as Dictionary).get("heading_radians", 0.0)
	# local axes: x along the pipe, y up, z across; the pad's heading says which way "along" points
	var xf := Transform3D(Basis(Vector3.UP, heading + PI / 2.0), pad.position)
	var strips := _profile()
	var half_w := WIDTH / 2.0

	var shown := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var solid := PackedVector3Array()
	var run := 0.0   # distance along the surface, so the sheets lie flat round the transitions
	for s: Dictionary in strips:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var na: Vector2 = s.na
		var nb: Vector2 = s.nb
		var p00 := Vector3(a.x, a.y, -half_w)
		var p01 := Vector3(a.x, a.y, half_w)
		var p10 := Vector3(b.x, b.y, -half_w)
		var p11 := Vector3(b.x, b.y, half_w)
		var n_a := Vector3(na.x, na.y, 0.0)
		var n_b := Vector3(nb.x, nb.y, 0.0)
		for tri in [[p00, p10, p11, n_a, n_b, n_b], [p00, p11, p01, n_a, n_b, n_a]]:
			var facing: Vector3 = tri[3] + tri[4] + tri[5]
			var verts := PackedVector3Array()
			_tri(verts, tri[0], tri[1], tri[2], facing)
			shown.append_array(verts)
			for v in verts:
				# the normal for each vertex is the one belonging to its end of the strip
				var at_a := v.x == a.x and v.y == a.y
				normals.append(n_a if at_a else n_b)
				uvs.append(Vector2((run if at_a else run + a.distance_to(b)) / SHEET.x, v.z / SHEET.y))
			if absf(a.y - HEIGHT) > 0.001 or absf(b.y - HEIGHT) > 0.001 or a.x == b.x:
				solid.append_array(verts)
		run += a.distance_to(b)

	var mesh := _mesh(shown, normals, uvs)
	var look := MeshInstance3D.new()
	look.mesh = mesh
	look.name = "HalfPipe"
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(PLY_BASE)
	material.normal_enabled = true
	material.normal_texture = load(PLY_NORMAL)
	material.roughness = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.material_override = material
	look.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, 0.0))   # a hair above the slab, so the two do not fight
	look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(look)

	# collision: the arcs and the flat (the decks are solid blocks, so their tops and ends are right)
	var faces := PackedVector3Array()
	for v in solid:
		faces.append(v)
	var half := FLAT / 2.0 + HEIGHT
	for side in [-1.0, 1.0]:
		var block := BoxMesh.new()
		block.size = Vector3(DECK, HEIGHT, WIDTH)
		var centre := Vector3(side * (half + DECK / 2.0), HEIGHT / 2.0, 0.0)
		for v in block.get_faces():
			faces.append(v + centre)
	var col := MeshInstance3D.new()
	col.mesh = _mesh(faces, PackedVector3Array())
	col.name = "COL_HalfPipe"
	col.transform = xf
	col.set_meta("extras", {"role": "collision"})
	root.add_child(col)

	# coping on both lips, and a thin tube to look at
	for side in [-1.0, 1.0]:
		var coping := Node3D.new()
		coping.name = "PATH_HalfPipe_Coping_%s" % ("W" if side < 0.0 else "E")
		coping.transform = xf
		coping.set_meta("extras", {
			"role": "grind_path", "kind": "coping", "closed": false, "radius": COPING_RADIUS,
			"points": [side * half, HEIGHT, -half_w, side * half, HEIGHT, half_w],
		})
		root.add_child(coping)
		var tube := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = COPING_RADIUS
		cyl.bottom_radius = COPING_RADIUS
		cyl.height = WIDTH
		cyl.radial_segments = 8
		tube.mesh = cyl
		var tube_material := StandardMaterial3D.new()
		tube_material.albedo_color = COPING
		tube.material_override = tube_material
		tube.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(side * half, HEIGHT, 0.0))
		root.add_child(tube)
	return true


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs := PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if normals.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if uvs.size() == verts.size():   # the ply's normal map needs tangents
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_tangents()
		mesh = st.commit()
	return mesh
