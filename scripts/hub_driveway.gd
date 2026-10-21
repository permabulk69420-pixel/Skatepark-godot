# A paved route beside the west wall, from the open front gate to the back yard, which is paved from the back of the house to the fences
# (over the old ramp slab, which is taken out). The house stays in its original GLB; only the boundary meshes are substituted.
class_name HubDriveway
extends RefCounted

const ASSETS := "res://assets/driveway/"
const HEIGHT := 0.004
const GATE_X := -12.5
const GATE_Z := 12.0
const OPENING := 5.2
const YARD := Rect2(-19.8, 10.8, 39.6, 19.0)   # the paved back yard: fence to fence, from the back of the house to the back fence
const OUTLINE := [
	Vector2(-14.9, -18.0), Vector2(-10.1, -18.0),
	Vector2(-10.1, 8.8), Vector2(-8.1, 10.8), Vector2(19.8, 10.8),
	Vector2(19.8, 29.8), Vector2(-19.8, 29.8),
	Vector2(-19.8, 10.8), Vector2(-14.9, 10.8),
]
const JOINT_PITCH := 3.0


static func add_to(root: Node3D) -> bool:
	var fence := root.find_child("Boundary_Timber_Weathered_Structure", true, false) as MeshInstance3D
	var walls := root.find_child("COL_Walls", true, false) as MeshInstance3D
	if fence == null or walls == null:
		return false # The fallback blockout has no imported boundary to replace.
	var source := (load(ASSETS + "fence_opening.glb") as PackedScene).instantiate()
	var cut_fence := source.find_child("Boundary_OpenDriveway", true, false) as MeshInstance3D
	var cut_walls := source.find_child("COL_OpenDrivewayBoundary", true, false) as MeshInstance3D
	var timber := fence.mesh.surface_get_material(0)
	fence.mesh = cut_fence.mesh
	fence.material_override = timber
	walls.mesh = cut_walls.mesh
	source.free()
	var slab := root.find_child("Ground_Concrete_Worn_Shop", true, false)
	if slab != null:
		slab.get_parent().remove_child(slab)   # (the paving covers it; its collision, part of COL_Floors, lies flush under the paving)
		slab.free()

	var driveway := Node3D.new()
	driveway.name = "Driveway"
	root.add_child(driveway)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_texture = load(ASSETS + "concrete_albedo.jpg")
	concrete.roughness_texture = load(ASSETS + "concrete_arm.jpg")
	concrete.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	concrete.roughness = 1.0
	concrete.normal_enabled = true
	concrete.normal_texture = load(ASSETS + "concrete_normal.jpg")
	concrete.normal_scale = 0.4
	concrete.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var pavement := SurfaceTool.new()
	pavement.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector2Array(OUTLINE)
	var indices := Geometry2D.triangulate_polygon(points)
	for tri in range(0, indices.size(), 3):
		for i in [0, 2, 1]:
			var p := points[indices[tri + i]]
			pavement.set_normal(Vector3.UP)
			pavement.set_uv(p / 3.0) # A real-world 3 m texture repeat.
			pavement.add_vertex(Vector3(p.x, HEIGHT, -p.y))
	pavement.generate_tangents()
	var surface := pavement.commit()
	_add_mesh(driveway, "Driveway_Concrete", surface, concrete)
	_add_mesh(driveway, "COL_Driveway_Concrete", surface, null)
	# The old closed fence hid an exterior terrain ring with no physics. Once the
	# gate is open, its dirt must support feet/wheels too, including beside the paving.
	var verge := SurfaceTool.new()
	verge.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rect: Rect2 in [Rect2(-250, -250, 230, 500), Rect2(20, -250, 230, 500),
		Rect2(-20, -250, 40, 238), Rect2(-20, 30, 40, 220)]:
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]
		for i in [0, 2, 1, 0, 3, 2]:
			var p: Vector2 = corners[i]
			verge.add_vertex(Vector3(p.x, 0, -p.y))
	_add_mesh(driveway, "COL_Driveway_ExteriorDirt", verge.commit(), null)

	var joints := SurfaceTool.new()
	joints.begin(Mesh.PRIMITIVE_TRIANGLES)
	for north in range(-15, 11, 3):
		_box(joints, Vector3(-12.5, HEIGHT + 0.0005, -north), Vector3(4.8, 0.001, 0.014))
	# the yard in 3 m bays, lined up with the joints across the drive
	var east := 0.5 - JOINT_PITCH * floorf((0.5 - YARD.position.x) / JOINT_PITCH)
	while east < YARD.end.x - 0.5:
		_box(joints, Vector3(east, HEIGHT + 0.0005, -YARD.get_center().y), Vector3(0.014, 0.001, YARD.size.y))
		east += JOINT_PITCH
	var line_north := JOINT_PITCH * ceilf(YARD.position.y / JOINT_PITCH)
	while line_north < YARD.end.y - 0.5:
		_box(joints, Vector3(YARD.get_center().x, HEIGHT + 0.0005, -line_north), Vector3(YARD.size.x, 0.001, 0.014))
		line_north += JOINT_PITCH
	var joint_material := StandardMaterial3D.new()
	joint_material.albedo_color = Color("6c6961")
	joint_material.roughness = 1.0
	_add_mesh(driveway, "Driveway_Joints", joints.commit(), joint_material)

	var wood := SurfaceTool.new()
	var metal := SurfaceTool.new()
	var collision := SurfaceTool.new()
	for st in [wood, metal, collision]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var hinge := Vector3(GATE_X + side * OPENING / 2.0, 0, GATE_Z)
		_box(wood, hinge + Vector3.UP * 0.95, Vector3(0.22, 1.9, 0.22))
		_box(collision, hinge + Vector3.UP * 0.95, Vector3(0.22, 1.9, 0.22))
		_box(metal, hinge + Vector3.UP * 1.92, Vector3(0.26, 0.04, 0.26))
		# Both leaves swing out towards the road, slightly past a right angle.
		var basis := Basis(Vector3.UP, side * deg_to_rad(105.0))
		var xf := Transform3D(basis, hinge)
		var length := 2.48
		var centre := -side * length / 2.0
		for plank in 18:
			var x := -side * (0.075 + plank * (length - 0.15) / 17.0)
			_box(wood, Vector3(x, 0.88, 0), Vector3(0.13, 1.52, 0.045), xf)
		for y in [0.18, 1.58]:
			_box(metal, Vector3(centre, y, -0.04), Vector3(length, 0.065, 0.065), xf)
		for x in [-side * 0.04, -side * (length - 0.04)]:
			_box(metal, Vector3(x, 0.88, -0.04), Vector3(0.065, 1.46, 0.065), xf)
		var a := Vector3(-side * 0.08, 0.23, -0.045)
		var b := Vector3(-side * (length - 0.08), 1.53, -0.045)
		var brace := Basis.looking_at((b - a).normalized(), Vector3.FORWARD)
		_box(metal, Vector3.ZERO, Vector3(0.045, 0.045, a.distance_to(b)), xf * Transform3D(brace, (a + b) / 2.0))
		_box(collision, Vector3(centre, 0.88, 0), Vector3(length, 1.52, 0.12), xf)
		var marker := Marker3D.new()
		marker.name = "OpenGate_Left" if side < 0 else "OpenGate_Right"
		marker.transform = xf
		driveway.add_child(marker)
	_add_mesh(driveway, "Gate_Timber", wood.commit(), timber)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("343a3a")
	steel.metallic = 0.65
	steel.roughness = 0.65
	_add_mesh(driveway, "Gate_Steel", metal.commit(), steel)
	_add_mesh(driveway, "COL_Driveway_Gates", collision.commit(), null)
	return true


static func _add_mesh(parent: Node3D, label: String, mesh: Mesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	if label.begins_with("COL_"):
		instance.set_meta("extras", {"role": "collision"})
	parent.add_child(instance)


static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, xf := Transform3D.IDENTITY) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xf * Transform3D(Basis.IDENTITY, centre))
