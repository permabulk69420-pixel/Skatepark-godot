# A plain stand-in for the house, until the real model arrives. It is laid out to the house's measurements
# (one big room: lounge with the TV at the west end, skate shop with the board wall at the east end; a veranda and a ramp down to the
# back yard; the empty slab where the half pipe goes), and it is read by the same code as an imported file: collision meshes named COL_,
# empties carrying their role in "extras". When the real house is dropped in at the hub's file, nothing else has to change.
#
# Coordinates in this file are the house's (x east, y north, z up, metres); `g` turns them into the engine's (x, up, -north).
class_name HubBlockout
extends RefCounted

const FLOOR := 0.30      # raised timber floor above the yard
const EAVE := 3.3
const RIDGE := 4.9

const TIMBER := Color("a8825c")
const WOOD_FLOOR := Color("8b6b4a")
const CONCRETE := Color("9d9d98")
const DIRT := Color("a58b66")
const ROOF := Color("6f7479")
const FENCE := Color("86704f")
const SOFA := Color("c9b79b")
const COUNTER := Color("5b4838")
const DARK := Color("1b1b1d")

var root: Node3D
var _floor_faces := PackedVector3Array()
var _wall_faces := PackedVector3Array()
var _materials := {}


# The house's coordinates to the engine's.
static func g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


static func build() -> Node3D:
	var house := HubBlockout.new()
	house._make()
	return house.root


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_materials[color] = m
	return _materials[color]


# A box: centre and size in the house's axes. `kind` says what it is to the sim ("floor", "wall", or "" for looks only); `shown` false
# makes it collision only. `rotation` is in the engine's axes.
func _box(c: Vector3, size: Vector3, color: Color, kind := "", shown := true, rotation := Basis.IDENTITY, node_name := "") -> void:
	var s := Vector3(size.x, size.z, size.y)
	var xf := Transform3D(rotation, g(c.x, c.y, c.z))
	var mesh := BoxMesh.new()
	mesh.size = s
	if shown:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _material(color)
		mi.transform = xf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if node_name != "":
			mi.name = node_name
		root.add_child(mi)
	if kind != "":
		var moved := PackedVector3Array()
		for v in mesh.get_faces():
			moved.append(xf * v)
		if kind == "floor":
			_floor_faces.append_array(moved)
		else:
			_wall_faces.append_array(moved)


# A wall running along x at height y, split into boxes around its openings. Each opening: { a, b, z0, z1, solid } (x range, z range;
# solid: closed for walking and riding even though it is open to look through, as the windows are).
func _wall_x(y: float, x0: float, x1: float, thick: float, openings: Array) -> void:
	openings.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p.a < q.a)
	var cursor := x0
	for o: Dictionary in openings:
		if o.a > cursor:
			_box(Vector3((cursor + o.a) / 2.0, y, EAVE / 2.0), Vector3(o.a - cursor, thick, EAVE), TIMBER, "wall")
		if o.z0 > 0.0:
			_box(Vector3((o.a + o.b) / 2.0, y, o.z0 / 2.0), Vector3(o.b - o.a, thick, o.z0), TIMBER, "wall")
		if o.z1 < EAVE:
			_box(Vector3((o.a + o.b) / 2.0, y, (o.z1 + EAVE) / 2.0), Vector3(o.b - o.a, thick, EAVE - o.z1), TIMBER, "wall")
		if o.solid:
			_box(Vector3((o.a + o.b) / 2.0, y, (o.z0 + o.z1) / 2.0), Vector3(o.b - o.a, thick, o.z1 - o.z0), TIMBER, "wall", false)
		cursor = o.b
	if cursor < x1:
		_box(Vector3((cursor + x1) / 2.0, y, EAVE / 2.0), Vector3(x1 - cursor, thick, EAVE), TIMBER, "wall")


func _marker(marker_name: String, at: Vector3, extras: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = marker_name
	node.position = g(at.x, at.y, at.z)
	node.set_meta("extras", extras)
	root.add_child(node)
	return node


func _make() -> void:
	root = Node3D.new()
	root.name = "Home"

	# ---- the ground: the yard, the field beyond the fence -----------------------------------------------------------------------
	_box(Vector3(0, 9, -0.5), Vector3(40, 42, 1.0), DIRT, "floor")                      # the property, x -20..20, y -12..30
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(500, 500)
	field.mesh = plane
	field.material_override = _material(Color("8f8a63"))
	field.position = g(0, 9, -0.03)
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(field)
	_box(Vector3(1.0, 19.5, 0.006), Vector3(16, 9, 0.012), CONCRETE)                    # the empty slab the half pipe goes on

	# ---- the house: floor, decks, steps, ramp ------------------------------------------------------------------------------------
	_box(Vector3(0, 0, FLOOR / 2.0), Vector3(14.4, 9.4, FLOOR), WOOD_FLOOR, "floor")    # main room, outer faces at x +-7.2, y +-4.7
	_box(Vector3(0, 6.2, FLOOR / 2.0), Vector3(14.4, 3.0, FLOOR), WOOD_FLOOR, "floor")  # back veranda y 4.7..7.7
	_box(Vector3(0, -5.95, FLOOR / 2.0), Vector3(14.4, 2.5, FLOOR), WOOD_FLOOR, "floor")  # front porch y -7.2..-4.7
	_box(Vector3(0, -7.35, 0.10), Vector3(3.0, 0.3, 0.20), WOOD_FLOOR, "floor")         # two steps down at the front
	_box(Vector3(0, -7.65, 0.05), Vector3(3.0, 0.3, 0.10), WOOD_FLOOR, "floor")
	# the ramp down the back: 3 m wide, 2.4 m long, 0.30 m drop (1:8)
	var slope := atan(FLOOR / 2.4)
	var along := sqrt(2.4 * 2.4 + FLOOR * FLOOR)
	var normal_g := Vector3(0.0, cos(slope), -sin(slope))
	var ramp_top := g(1.0, 8.9, FLOOR / 2.0)
	var ramp_c := ramp_top - normal_g * 0.15
	var ramp_mesh := BoxMesh.new()
	ramp_mesh.size = Vector3(3.0, 0.3, along)
	var ramp_basis := Basis(Vector3.RIGHT, -slope)
	var ramp := MeshInstance3D.new()
	ramp.mesh = ramp_mesh
	ramp.material_override = _material(WOOD_FLOOR)
	ramp.transform = Transform3D(ramp_basis, ramp_c)
	root.add_child(ramp)
	for v in ramp_mesh.get_faces():
		_floor_faces.append(ramp.transform * v)

	# ---- walls (heights from the ground, 3.3 m eaves) ---------------------------------------------------------------------------
	_wall_x(-4.6, -7.2, 7.2, 0.2, [
		{"a": -0.55, "b": 0.55, "z0": FLOOR, "z1": FLOOR + 2.1, "solid": false},                # front door
		{"a": -5.3, "b": -3.7, "z0": FLOOR + 0.9, "z1": FLOOR + 2.2, "solid": true},            # windows
		{"a": 3.7, "b": 5.3, "z0": FLOOR + 0.9, "z1": FLOOR + 2.2, "solid": true},
	])
	_wall_x(4.6, -7.2, 7.2, 0.2, [
		{"a": -5.8, "b": -4.2, "z0": FLOOR + 0.9, "z1": FLOOR + 2.2, "solid": true},
		{"a": -1.0, "b": 3.0, "z0": FLOOR, "z1": FLOOR + 2.4, "solid": false},                  # the way out to the back veranda
		{"a": 4.7, "b": 6.3, "z0": FLOOR + 0.9, "z1": FLOOR + 2.2, "solid": true},
	])
	_box(Vector3(-7.1, 0, EAVE / 2.0), Vector3(0.2, 9.4, EAVE), TIMBER, "wall")           # west wall (the TV wall)
	_box(Vector3(7.1, 0, EAVE / 2.0), Vector3(0.2, 9.4, EAVE), TIMBER, "wall")            # east wall (the board wall)
	for side in [-1.0, 1.0]:                                                                # the gable ends
		var prism := MeshInstance3D.new()
		var tri := PrismMesh.new()
		tri.size = Vector3(9.4, RIDGE - EAVE, 0.2)
		prism.mesh = tri
		prism.material_override = _material(TIMBER)
		prism.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), g(7.1 * side, 0, EAVE + (RIDGE - EAVE) / 2.0))
		root.add_child(prism)

	# ---- roof: the two main slopes, and a lower one over each veranda ----------------------------------------------------------
	var main_a := atan((RIDGE - EAVE) / 4.7)
	var main_len := 4.7 / cos(main_a) + 0.6
	for side in [-1.0, 1.0]:   # side -1 = south
		var rot := Basis(Vector3.RIGHT, main_a * -side)
		var mid := g(0, side * 2.35, (RIDGE + EAVE) / 2.0 + 0.05)
		var down := Vector3(0.0, -sin(main_a), cos(main_a) * -side).normalized()   # pointing down the slope (engine axes)
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(15.2, 0.15, main_len)
		slab.mesh = slab_mesh
		slab.material_override = _material(ROOF)
		slab.transform = Transform3D(rot, mid + down * 0.3)
		root.add_child(slab)
	var porch_a := atan(0.4 / 3.2)
	for side in [-1.0, 1.0]:
		var rot := Basis(Vector3.RIGHT, porch_a * -side)
		var slab := MeshInstance3D.new()
		var slab_mesh := BoxMesh.new()
		slab_mesh.size = Vector3(15.2, 0.12, 3.3)
		slab.mesh = slab_mesh
		slab.material_override = _material(ROOF)
		slab.transform = Transform3D(rot, g(0, side * 6.4, 3.1))
		root.add_child(slab)

	# ---- veranda posts and railings ----------------------------------------------------------------------------------------------
	for post_y in [7.55, -7.05]:
		for x in [-7.1, -4.0, 4.0, 7.1]:
			_box(Vector3(x, post_y, FLOOR + 1.3), Vector3(0.15, 0.15, 2.6), TIMBER, "wall")
	# along the edges, leaving a gap for the ramp at the back and the steps at the front
	for edge in [{"y": 7.65, "gap_a": -0.5, "gap_b": 2.5}, {"y": -7.15, "gap_a": -1.5, "gap_b": 1.5}]:
		_box(Vector3((-7.2 + edge.gap_a) / 2.0, edge.y, FLOOR + 0.5), Vector3(edge.gap_a + 7.2, 0.08, 1.0), TIMBER, "wall")
		_box(Vector3((edge.gap_b + 7.2) / 2.0, edge.y, FLOOR + 0.5), Vector3(7.2 - edge.gap_b, 0.08, 1.0), TIMBER, "wall")
	for x in [-7.15, 7.15]:                                                                  # and down the two ends of each veranda
		_box(Vector3(x, 6.2, FLOOR + 0.5), Vector3(0.08, 3.0, 1.0), TIMBER, "wall")
		_box(Vector3(x, -5.95, FLOOR + 0.5), Vector3(0.08, 2.5, 1.0), TIMBER, "wall")

	# ---- the fence round the property ---------------------------------------------------------------------------------------------
	_box(Vector3(0, 30.0, 0.9), Vector3(40.2, 0.12, 1.8), FENCE, "wall")
	_box(Vector3(0, -12.0, 0.9), Vector3(40.2, 0.12, 1.8), FENCE, "wall")
	_box(Vector3(-20.0, 9.0, 0.9), Vector3(0.12, 42.2, 1.8), FENCE, "wall")
	_box(Vector3(20.0, 9.0, 0.9), Vector3(0.12, 42.2, 1.8), FENCE, "wall")

	# ---- inside: the lounge --------------------------------------------------------------------------------------------------------
	_box(Vector3(-6.97, 0, FLOOR + 1.675), Vector3(0.06, 2.5, 1.45), DARK)                  # the TV's frame
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.4, 1.35)
	screen.mesh = quad
	screen.name = "TV_Screen"
	var screen_material := StandardMaterial3D.new()
	screen_material.albedo_color = Color(0.02, 0.02, 0.03)
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override = screen_material
	screen.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), g(-6.93, 0, FLOOR + 1.675))
	root.add_child(screen)
	_box(Vector3(-2.65, 0, FLOOR + 0.225), Vector3(0.9, 2.2, 0.45), SOFA, "wall")           # sofa: seat and back
	_box(Vector3(-2.35, 0, FLOOR + 0.6), Vector3(0.3, 2.2, 0.8), SOFA, "wall")
	_box(Vector3(-4.4, 0, FLOOR + 0.225), Vector3(0.6, 1.2, 0.45), COUNTER, "wall")        # coffee table

	# ---- inside: the shop ----------------------------------------------------------------------------------------------------------
	_box(Vector3(2.8, 0, FLOOR + 0.525), Vector3(0.7, 3.6, 1.05), COUNTER, "wall")          # counter
	var colours := [Color("c9473b"), Color("2f7d8f"), Color("e0b63c"), Color("3c4f8a"), Color("6aa84f"), Color("d97a2b")]
	for row in 2:
		var z := 1.25 + 0.85 * row                                                          # the boards' centres (above the ground)
		_box(Vector3(6.95, 0, z - 0.42), Vector3(0.1, 3.4, 0.04), COUNTER)                   # the ledge each row of boards rests on
		for i in 6:
			var slot := 1 + row * 6 + i
			var y := -1.25 + 0.5 * i
			_marker("BoardSlot_%02d" % slot, Vector3(6.95, y, z), {"role": "board_slot", "heading_radians": PI / 2.0})
			_box(Vector3(6.94, y, z), Vector3(0.02, 0.2, 0.8), colours[(slot - 1) % colours.size()])   # a stand-in board

	# ---- markers -------------------------------------------------------------------------------------------------------------------
	_marker("Spawn_Hub", Vector3(0, -3.0, FLOOR), {"role": "spawn", "heading_radians": 0.0})
	_marker("Remote_Spot", Vector3(-4.4, 0, FLOOR + 0.45), {"role": "remote_spot"})
	_marker("RampPad", Vector3(1.0, 19.5, 0.0), {"role": "ramp_pad", "heading_radians": -PI / 2.0, "pad_length": 16.0, "pad_width": 9.0})
	var lamps := [Vector3(-5, -2.5, 3.0), Vector3(-3, 2.5, 3.0), Vector3(2.5, -2.5, 3.0), Vector3(3, 2.5, 3.0), Vector3(5.5, 0, 3.0), Vector3(1, 6.2, 2.5)]
	for i in lamps.size():
		_marker("Light_%02d" % (i + 1), lamps[i], {"role": "light", "energy": 0.8})

	# ---- collision ----------------------------------------------------------------------------------------------------------------
	root.add_child(_collision_mesh("COL_Floors", _floor_faces))
	root.add_child(_collision_mesh("COL_Walls", _wall_faces))


static func _collision_mesh(mesh_name: String, faces: PackedVector3Array) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.name = mesh_name
	node.set_meta("extras", {"role": "collision"})
	return node
