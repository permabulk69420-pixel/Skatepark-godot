# The RIFT board in the scene: follows the sim, spins its wheels, and drops a blob shadow so height reads in the air.
class_name BoardView
extends RefCounted

const BOARD = Config.Board

var root: Node3D
var wheels: Array[Node3D] = []
var shadow: MeshInstance3D
var shadow_material: StandardMaterial3D
var _hit := SkateWorld.Hit.new()


func _init(parent: Node, model: Node3D) -> void:
	root = Node3D.new()
	root.name = "skateboard"
	root.add_child(model)
	parent.add_child(root)
	var stack: Array = [model]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is GeometryInstance3D:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if node is Node3D and (node.name as String).begins_with("Wheel_"):
			wheels.append(node)
	shadow = _make_blob_shadow()
	parent.add_child(shadow)


static func _make_blob_shadow() -> MeshInstance3D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 2
	material.no_depth_test = false
	var quad := PlaneMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = quad
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 16384.0
	mesh.name = "board_shadow"
	return mesh


# The board lying about or carried (not under the skater): at this pose, with its blob shadow under it.
func show_at(world: SkateWorld, at: Transform3D) -> void:
	root.global_transform = at
	_place_shadow(world, at.origin, Skater.yaw_of(-at.basis.z.x, -at.basis.z.z) if absf(at.basis.z.y) < 0.99 else 0.0)


func _place_shadow(world: SkateWorld, base: Vector3, heading: float) -> void:
	var hit := world.ground(base.x, base.z, base.y + 0.6, _hit, 40.0)
	if hit == null:
		shadow.visible = false
		return
	var height := maxf(0.0, base.y - hit.y)
	var fade := clampf(1.0 - height / 4.5, 0.0, 1.0)
	shadow.visible = fade > 0.02
	var material := shadow.material_override as StandardMaterial3D
	material.albedo_color = Color(1, 1, 1, fade)
	var tilt := Quaternion(Vector3.UP, hit.normal)
	var turn := Quaternion(Vector3.UP, heading)
	var size := 0.5 + height * 0.09
	var basis := Basis(tilt * turn).scaled(Vector3(size * 0.75, 1.0, size * 1.55))
	shadow.global_transform = Transform3D(basis, Vector3(base.x, hit.y + 0.012, base.z))


func update(sim: Skater, dt: float) -> void:
	var bailing := sim.mode == Skater.Mode.BAIL and sim.bail_board != null
	if bailing:
		root.global_transform = Transform3D(Basis(sim.bail_board.quat), sim.bail_board.pos)
	else:
		root.global_transform = Transform3D(Basis(sim.board_quaternion()), sim.pos + sim.up * sim.manual_lift)
	var spin := -(sim.roll_speed / BOARD.wheelRadius) * dt
	for wheel in wheels:
		wheel.rotate_x(spin)

	var base: Vector3 = root.global_position if bailing else sim.pos
	var hit := sim.world.ground(base.x, base.z, base.y + 0.6, _hit, 40.0)
	if hit == null:
		shadow.visible = false
		return
	var height := maxf(0.0, base.y - hit.y)
	var fade := clampf(1.0 - height / 4.5, 0.0, 1.0)
	shadow.visible = fade > 0.02
	var material := shadow.material_override as StandardMaterial3D
	material.albedo_color = Color(1, 1, 1, fade)
	# Lie on the surface, with the same heading as the board so the long blob lines up with the deck.
	var tilt := Quaternion(Vector3.UP, hit.normal)
	var turn := Quaternion(Vector3.UP, sim.heading)
	var size := 0.5 + height * 0.09
	var basis := Basis(tilt * turn).scaled(Vector3(size * 0.75, 1.0, size * 1.55))
	shadow.global_transform = Transform3D(basis, Vector3(base.x, hit.y + 0.012, base.z))
