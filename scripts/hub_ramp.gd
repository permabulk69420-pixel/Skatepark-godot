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
const SHEET := Vector2(4.88, 4.88)   # the ply texture is 4 sheets (1.22 m) along the pipe by 2 (2.44 m, the long side across it)
const COPING := Color("b9bcc0")
const SIDE_TINT := Color(0.74, 0.68, 0.62)   # the side walls: the same ply, older and out of the sun
const COLUMNS := 12                           # across the riding surface, for the wear to vary across it


# One triangle, wound so that its front face looks along `facing` (Godot: front faces are clockwise).
static func _tri(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, facing: Vector3) -> void:
	if (c - a).cross(b - a).dot(facing) < 0.0:
		var t := b
		b = c
		c = t
	faces.append(a)
	faces.append(b)
	faces.append(c)


# Two triangles for the quad a b c d (in order round it), facing `facing`.
static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	_tri(faces, a, b, c, facing)
	_tri(faces, a, c, d, facing)


# The same, for a mesh that is drawn: with its normal and planar texture coordinates (a side wall: x and y; the back of a deck: z and y).
static func _quad_uv(faces: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	var start := faces.size()
	_quad(faces, a, b, c, d, facing)
	for i in range(start, faces.size()):
		var v := faces[i]
		normals.append(facing)
		uvs.append(Vector2((v.x if facing.x == 0.0 else v.z) / SHEET.x, v.y / SHEET.y))


# How worn the ply is at a point on the riding surface: grey wheel grime in the middle of the flat and the bottom of the curves, and
# the dark wax band under the coping, both strongest down the middle where everyone rides. Decks stay clean.
static func _wear(v: Vector3, on_deck: bool) -> Color:
	if on_deck:
		return Color.WHITE
	var middle := 1.0 - absf(v.z) / (WIDTH / 2.0)
	var up := v.y / HEIGHT
	var dirt := 0.10 * (1.0 - smoothstep(0.0, 0.5, up)) + 0.30 * smoothstep(0.72, 0.97, up)
	var k := 1.0 - dirt * (0.7 + 0.3 * middle)
	return Color(k, k * 0.97, k * 0.94)


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
	var colours := PackedColorArray()
	var solid := PackedVector3Array()
	var run := 0.0   # distance along the surface, so the sheets lie flat round the transitions
	for s: Dictionary in strips:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		var n_a := Vector3(s.na.x, s.na.y, 0.0)
		var n_b := Vector3(s.nb.x, s.nb.y, 0.0)
		for col in COLUMNS:
			var z0 := -half_w + WIDTH * float(col) / COLUMNS
			var z1 := -half_w + WIDTH * float(col + 1) / COLUMNS
			var p00 := Vector3(a.x, a.y, z0)
			var p01 := Vector3(a.x, a.y, z1)
			var p10 := Vector3(b.x, b.y, z0)
			var p11 := Vector3(b.x, b.y, z1)
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
					colours.append(_wear(v, absf(v.x) > FLAT / 2.0 + HEIGHT + 0.001))
				if absf(a.y - HEIGHT) > 0.001 or absf(b.y - HEIGHT) > 0.001 or a.x == b.x:
					solid.append_array(verts)
		run += a.distance_to(b)

	var look := MeshInstance3D.new()
	look.mesh = _mesh(shown, normals, uvs, colours)
	look.name = "HalfPipe"
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(PLY_BASE)
	material.vertex_color_use_as_albedo = true
	material.normal_enabled = true
	material.normal_texture = load(PLY_NORMAL)
	material.roughness = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	look.material_override = material
	look.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, 0.0))   # a hair above the slab, so the two do not fight
	look.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(look)

	# the outside of the ramp: ply side walls under each transition and deck, and the back of each deck, so it is a solid ramp and
	# not a shell you can see under. The same faces are its collision (with the decks' tops).
	var half := FLAT / 2.0 + HEIGHT
	var skin := PackedVector3Array()
	var skin_normals := PackedVector3Array()
	var skin_uvs := PackedVector2Array()
	for s: Dictionary in strips:
		var a: Vector2 = s.a
		var b: Vector2 = s.b
		if a.y < 0.001 and b.y < 0.001:
			continue
		for z in [-half_w, half_w]:
			var out := Vector3(0.0, 0.0, signf(z))
			_quad_uv(skin, skin_normals, skin_uvs, Vector3(a.x, 0.0, z), Vector3(b.x, 0.0, z), Vector3(b.x, b.y, z), Vector3(a.x, a.y, z), out)
	for side in [-1.0, 1.0]:
		var x1: float = side * (half + DECK)
		_quad_uv(skin, skin_normals, skin_uvs, Vector3(x1, 0.0, -half_w), Vector3(x1, HEIGHT, -half_w), Vector3(x1, HEIGHT, half_w), Vector3(x1, 0.0, half_w), Vector3(side, 0.0, 0.0))
	var sides := MeshInstance3D.new()
	sides.mesh = _mesh(skin, skin_normals, skin_uvs)
	sides.name = "HalfPipe_Sides"
	var side_material := StandardMaterial3D.new()
	side_material.albedo_texture = material.albedo_texture
	side_material.albedo_color = SIDE_TINT
	side_material.normal_enabled = true
	side_material.normal_texture = material.normal_texture
	side_material.roughness = 0.85
	sides.material_override = side_material
	sides.transform = look.transform
	sides.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(sides)

	# collision: the arcs and the flat, the decks' tops, and the outside walls. Only the outside: a face standing behind the transition
	# (the inner side of a solid block) is inside the ramp, where the board's front wheels reach on the steep part, and hitting it there
	# was a wall slam out of nowhere when popping near the lip.
	var faces := PackedVector3Array()
	faces.append_array(solid)
	for side in [-1.0, 1.0]:
		var x0: float = side * half
		var x1: float = side * (half + DECK)
		_quad(faces, Vector3(x0, HEIGHT, -half_w), Vector3(x1, HEIGHT, -half_w), Vector3(x1, HEIGHT, half_w), Vector3(x0, HEIGHT, half_w), Vector3.UP)
	faces.append_array(skin)
	var col_node := MeshInstance3D.new()
	col_node.mesh = _mesh(faces, PackedVector3Array())
	col_node.name = "COL_HalfPipe"
	col_node.transform = xf
	col_node.set_meta("extras", {"role": "collision"})
	root.add_child(col_node)

	# coping on both lips, and a steel pipe to look at
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
		cyl.radial_segments = 16
		cyl.rings = 1
		tube.mesh = cyl
		var tube_material := StandardMaterial3D.new()
		tube_material.albedo_color = COPING
		tube_material.metallic = 0.9
		tube_material.roughness = 0.35
		tube.material_override = tube_material
		tube.transform = xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(side * half, HEIGHT, 0.0))
		root.add_child(tube)
	return true


static func _mesh(verts: PackedVector3Array, normals: PackedVector3Array, uvs := PackedVector2Array(), colours := PackedColorArray()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if normals.size() == verts.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if uvs.size() == verts.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if colours.size() == verts.size():
		arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if uvs.size() == verts.size():   # the ply's normal map needs tangents
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_tangents()
		mesh = st.commit()
	return mesh
