# The land in front of the house: flat dirt out to the horizon, a straight road past the front gate that the driveway runs on to, and a
# link road south from it to a big oval loop. Inside the loop is open ground to build on. Painted lines: a dashed centre line, solid edge
# lines, broken where roads meet.
#
# Coordinates in this file are the house brief's (x east, y north, metres); the engine's are (x, up, -y).
class_name HubRoads
extends RefCounted

const ASSETS := "res://assets/road/"
const HEIGHT := HubDriveway.HEIGHT     # flush with the driveway
const PAINT_HEIGHT := HEIGHT + 0.002
const TEXTURE_SIZE := 3.0              # metres the asphalt texture covers
const GROUND_EXTENT := 800.0           # the dirt goes this far each way from the house

const MAIN_Y := -24.0                  # the road past the house: its middle line,
const MAIN_WIDTH := 8.0
const MAIN_FROM := -250.0              # and its ends
const MAIN_TO := 250.0
const LINK_WIDTH := 8.0                # the road south to the loop, from the middle of the main road
const LOOP_CENTRE := Vector2(0.0, -150.0)
const LOOP_STRAIGHT := 240.0           # the loop: two straights this long, east-west,
const LOOP_RADIUS := 70.0              # joined by half circles this big (to the middle of the road)
const LOOP_WIDTH := 10.0
const ARC_STEPS := 90

const LINE_WIDTH := 0.15
const EDGE_INSET := 0.35               # an edge line's middle, in from the edge of the road
const DASH := 3.0                      # the centre line: 3 m painted, 6 m gap
const DASH_GAP := 6.0
const PIECE := 2.0                     # lines are laid in pieces this long, so they can stop where roads meet


static func add_to(root: Node3D) -> void:
	_extend_ground(root)
	var roads := Node3D.new()
	roads.name = "Roads"
	root.add_child(roads)

	var asphalt := ShaderMaterial.new()
	asphalt.shader = load("res://shaders/road.gdshader")
	asphalt.set_shader_parameter("albedo_texture", load(ASSETS + "asphalt_albedo.jpg"))
	asphalt.set_shader_parameter("normal_texture", load(ASSETS + "asphalt_normal.jpg"))
	asphalt.set_shader_parameter("arm_texture", load(ASSETS + "asphalt_arm.jpg"))
	asphalt.set_shader_parameter("tile", TEXTURE_SIZE)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("e4e0d4")
	paint.roughness = 0.75

	var link_top := MAIN_Y - MAIN_WIDTH / 2.0
	var loop_north := LOOP_CENTRE.y + LOOP_RADIUS
	var link_bottom := loop_north + LOOP_WIDTH / 2.0
	var main_line: Array[Vector2] = [Vector2(MAIN_FROM, MAIN_Y), Vector2(MAIN_TO, MAIN_Y)]
	var link_line: Array[Vector2] = [Vector2(0.0, link_top), Vector2(0.0, link_bottom)]
	var loop_line := loop_points()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_ribbon(surface, main_line, false, 0.0, MAIN_WIDTH, HEIGHT, true)
	_ribbon(surface, link_line, false, 0.0, LINK_WIDTH, HEIGHT, true)
	_ribbon(surface, loop_line, true, 0.0, LOOP_WIDTH, HEIGHT, true)
	surface.generate_tangents()
	var mesh := surface.commit()
	_add_mesh(roads, "Road_Asphalt", mesh, asphalt)
	_add_mesh(roads, "COL_Road_Asphalt", mesh, null)

	# where the link road meets the others, their lines stop
	var junctions: Array[Rect2] = [
		Rect2(-LINK_WIDTH / 2.0 - 0.5, MAIN_Y - MAIN_WIDTH, LINK_WIDTH + 1.0, MAIN_WIDTH),
		Rect2(-LINK_WIDTH / 2.0 - 0.5, loop_north, LINK_WIDTH + 1.0, LOOP_WIDTH),
	]
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_paint(lines, main_line, false, side * (MAIN_WIDTH / 2.0 - EDGE_INSET), junctions, false)
		_paint(lines, link_line, false, side * (LINK_WIDTH / 2.0 - EDGE_INSET), [], false)
		_paint(lines, loop_line, true, side * (LOOP_WIDTH / 2.0 - EDGE_INSET), junctions, false)
	_paint(lines, main_line, false, 0.0, junctions, true)
	_paint(lines, link_line, false, 0.0, [], true)
	_paint(lines, loop_line, true, 0.0, junctions, true)
	_add_mesh(roads, "Road_Lines", lines.commit(), paint)


# The middle line of the loop, going round anticlockwise (seen from above): the west half circle from the west end of the north straight,
# then the east one from the east end of the south straight. (The straights are the steps between them.)
static func loop_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var half := LOOP_STRAIGHT / 2.0
	for end: Array in [[-half, PI / 2.0], [half, -PI / 2.0]]:
		var centre := LOOP_CENTRE + Vector2(end[0], 0.0)
		for i in ARC_STEPS + 1:
			var a: float = end[1] + PI * float(i) / ARC_STEPS
			points.append(centre + Vector2(cos(a), sin(a)) * LOOP_RADIUS)
	return points


# The dirt the house stands in goes out much further (the house file has it to 250 m).
static func _extend_ground(root: Node3D) -> void:
	var ground := root.find_child("Ground_Dirt_Property", true, false) as MeshInstance3D
	if ground == null or not ground.mesh is ArrayMesh:
		return
	var old := ground.mesh as ArrayMesh
	var arrays := old.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var far := 0.0
	for v in vertices:
		far = maxf(far, maxf(absf(v.x), absf(v.z)))
	# the file's UVs are (x, z + 3) / 3: a 3 m repeat, kept the same out to the new edge
	for i in vertices.size():
		var v := vertices[i]
		if is_equal_approx(absf(v.x), far):
			v.x = signf(v.x) * GROUND_EXTENT
		if is_equal_approx(absf(v.z), far):
			v.z = signf(v.z) * GROUND_EXTENT
		vertices[i] = v
		uvs[i] = Vector2(v.x / 3.0, (v.z + 3.0) / 3.0)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, old.surface_get_material(0))
	ground.mesh = mesh


# A strip `width` wide along `line` (`offset` to the right of it), flat at `height`, its texture laid in the world (so strips meet
# without a seam).
static func _ribbon(st: SurfaceTool, line: Array[Vector2], closed: bool, offset: float, width: float, height: float, uv := false) -> void:
	var n := line.size()
	var count := n if closed else n - 1
	for i in count:
		var a := line[i]
		var b := line[(i + 1) % n]
		var na := _side(line, i, closed)
		var nb := _side(line, (i + 1) % n, closed)
		var quad := [
			a + na * (offset - width / 2.0), b + nb * (offset - width / 2.0),
			b + nb * (offset + width / 2.0), a + na * (offset + width / 2.0),
		]
		_quad(st, quad, height, uv)


# The unit vector to the right of the line at point `i` (the corners of a bend are mitred).
static func _side(line: Array[Vector2], i: int, closed: bool) -> Vector2:
	var n := line.size()
	var before := line[(i - 1 + n) % n] if closed or i > 0 else line[i]
	var after := line[(i + 1) % n] if closed or i < n - 1 else line[i]
	var along := (after - before).normalized()
	return Vector2(along.y, -along.x)


# A painted line along `line`, `offset` to the right of its middle: solid, or dashed; left out inside `skip`.
static func _paint(st: SurfaceTool, line: Array[Vector2], closed: bool, offset: float, skip: Array[Rect2], dashed: bool) -> void:
	var n := line.size()
	var count := n if closed else n - 1
	var travelled := 0.0
	for i in count:
		var a := line[i]
		var b := line[(i + 1) % n]
		var na := _side(line, i, closed)
		var nb := _side(line, (i + 1) % n, closed)
		var length := a.distance_to(b)
		var pieces := maxi(1, ceili(length / PIECE))
		for k in pieces:
			var t0 := float(k) / pieces
			var t1 := float(k + 1) / pieces
			var at := travelled + length * (t0 + t1) / 2.0
			if dashed and fmod(at, DASH + DASH_GAP) > DASH:
				continue
			var p0 := a.lerp(b, t0) + na.lerp(nb, t0).normalized() * offset
			var p1 := a.lerp(b, t1) + na.lerp(nb, t1).normalized() * offset
			var middle := (p0 + p1) / 2.0
			var hidden := false
			for rect in skip:
				if rect.has_point(middle):
					hidden = true
			if hidden:
				continue
			var across := na.lerp(nb, (t0 + t1) / 2.0).normalized() * LINE_WIDTH / 2.0
			_quad(st, [p0 - across, p1 - across, p1 + across, p0 + across], PAINT_HEIGHT, false)
		travelled += length


# Two triangles facing up (corners given going round the quad in the brief's axes).
static func _quad(st: SurfaceTool, corners: Array, height: float, uv: bool) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		var p: Vector2 = corners[i]
		st.set_normal(Vector3.UP)
		if uv:
			st.set_uv(p / TEXTURE_SIZE)
		st.add_vertex(Vector3(p.x, height, -p.y))


static func _add_mesh(parent: Node3D, label: String, mesh: Mesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	if label.begins_with("COL_"):
		instance.set_meta("extras", {"role": "collision"})
	parent.add_child(instance)
