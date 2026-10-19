# The TV remote: a rounded dark plastic body with a power button, a d-pad, coloured keys and a row of small ones, long axis along z (the
# front, with the infrared window, at -z), buttons up (+y). It sits in a hand's grip socket when held.
class_name HubRemote
extends RefCounted

const SIZE := Vector3(0.05, 0.022, 0.17)
const RADIUS := 0.009


# The body: a box with its edges and corners rounded (every vertex pulled out to the rounded outline).
static func _rounded_box(size: Vector3, radius: float) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = 16
	box.subdivide_height = 8
	box.subdivide_depth = 44
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var inner_half := size / 2.0 - Vector3.ONE * radius
	for i in verts.size():
		var p := verts[i]
		var inner := Vector3(clampf(p.x, -inner_half.x, inner_half.x), clampf(p.y, -inner_half.y, inner_half.y), clampf(p.z, -inner_half.z, inner_half.z))
		var out := p - inner
		if out.length() > 0.00001:
			normals[i] = out.normalized()
			verts[i] = inner + normals[i] * radius
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _material(color: Color, roughness: float, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func build() -> Node3D:
	var node := Node3D.new()
	node.name = "Remote"
	var top := SIZE.y / 2.0
	_part(node, _rounded_box(SIZE, RADIUS), _material(Color(0.07, 0.07, 0.08), 0.42), Vector3.ZERO)
	var rubber := _material(Color(0.2, 0.21, 0.22), 0.8)
	var key := _rounded_box(Vector3(0.016, 0.005, 0.009), 0.0023)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.0075
	disc.bottom_radius = 0.0075
	disc.height = 0.005
	_part(node, disc, _material(Color("c9382d"), 0.6), Vector3(0.0, top, -0.062))                 # power
	var ring := CylinderMesh.new()
	ring.top_radius = 0.0165
	ring.bottom_radius = 0.0165
	ring.height = 0.004
	_part(node, ring, rubber, Vector3(0.0, top, -0.02))                                             # d-pad
	var centre := CylinderMesh.new()
	centre.top_radius = 0.0065
	centre.bottom_radius = 0.0065
	centre.height = 0.007
	_part(node, centre, _material(Color(0.1, 0.1, 0.11), 0.5), Vector3(0.0, top, -0.02))
	var arrow := _rounded_box(Vector3(0.006, 0.005, 0.005), 0.0015)
	for offset in [Vector3(0, 0, -0.012), Vector3(0, 0, 0.012), Vector3(-0.012, 0, 0), Vector3(0.012, 0, 0)]:
		_part(node, arrow, _material(Color(0.5, 0.52, 0.55), 0.6), Vector3(0.0, top + 0.003, -0.02) + offset)
	for i in 3:                                                                                      # the coloured keys
		var colour: Color = [Color("c9382d"), Color("4f9a45"), Color("e0b63c")][i]
		var small := CylinderMesh.new()
		small.top_radius = 0.0048
		small.bottom_radius = 0.0048
		small.height = 0.004
		_part(node, small, _material(colour, 0.6), Vector3(-0.0125 + 0.0125 * i, top, 0.016))
	for row in 2:                                                                                    # two rows of small keys
		for i in 3:
			_part(node, key, rubber, Vector3(-0.0155 + 0.0155 * i, top, 0.036 + 0.0185 * row))
	var window := _rounded_box(Vector3(0.026, 0.007, 0.004), 0.0015)
	_part(node, window, _material(Color("5a0d0d"), 0.3, 0.4), Vector3(0.0, 0.0, -SIZE.z / 2.0 + 0.001))   # the infrared window
	return node


# Where the remote sits in a hand's grip socket. The grip is solved for a flat plate lying along `plate_out` from the hollow of the hand
# (tools/solve_grip.gd), so modes 0 and 2 lay the remote the way that plate lies, and 1 and 3 across the palm like a baton; 2 and 3 have the
# buttons on the other side.
static func in_hand(handedness: String, mode := 0) -> Transform3D:
	var solution: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VrHands.SOLUTION))[handedness]
	var offset := Vector3(solution.bar_offset[0], solution.bar_offset[1], solution.bar_offset[2])
	var out := Vector3(solution.plate_out[0], solution.plate_out[1], solution.plate_out[2]).normalized()
	var bar := Vector3.UP
	var thick := out.cross(bar).normalized()
	var buttons := thick if mode < 2 else -thick
	var along := -out if (mode % 2) == 0 else bar
	var basis := Basis(buttons.cross(along), buttons, along).orthonormalized()
	return Transform3D(basis, offset + (out * 0.05 if (mode % 2) == 0 else Vector3.ZERO))
