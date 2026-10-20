# The menu: Resume, Retry, Return to house, the two balance-hand choices, Exit. In the headset it is the big frame from the watch (assets/hud/menu_frame.glb) hung
# in front of you, with a laser from the right hand to point and the trigger to press. On a flat screen it is a plain overlay
# (M opens it, the mouse or Up / Down / Enter choose).
class_name WatchMenu
extends RefCounted

signal chosen(action: String)   # "resume", "retry", "home", "grind_hand", "manual_hand" or "exit"
signal hovered                    # the pointer moved onto a different button

const FRAME := "res://assets/hud/menu_frame.glb"
const PIXELS := Vector2i(960, 616)
const INNER := Vector2(0.668, 0.428)   # the plate inside the frame, in the model's own metres
const FRAME_SCALE := 0.7
const DISTANCE := 0.85                  # metres in front of your head
const DROP := 0.1                       # and a little below it
const FACE_Z := 0.004                   # the content sits this far (model metres) in front of the plate
const REACH := 3.0                      # the laser's length when it points at nothing
const ACCENT := Color("5fd0c0")
const PANEL := Color(0.05, 0.09, 0.11, 1.0)

var is_open := false
var root: Node3D
var viewport: SubViewport
var content: Control
var buttons := {}                  # action -> Button
var laser: MeshInstance3D
var dot: MeshInstance3D
var vr: bool
var layer: CanvasLayer             # flat screen only
var down_was := false
var over: Button


func _init(parent: Node, p_vr: bool, in_house: bool, title: String) -> void:
	vr = p_vr
	content = _build(in_house, title)
	if vr:
		_build_frame(parent)
	else:
		layer = CanvasLayer.new()
		layer.name = "Menu"
		layer.layer = 20
		layer.visible = false
		parent.add_child(layer)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.55)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(dim)
		var centre := CenterContainer.new()
		centre.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(centre)
		centre.add_child(content)


# The buttons the menu has for this place (the house has nothing to retry and nowhere to go back to).
static func actions_for(in_house: bool) -> Array:
	if in_house:
		return ["resume", "grind_hand", "manual_hand", "exit"]
	return ["resume", "retry", "home", "grind_hand", "manual_hand", "exit"]


static func caption_for(action: String) -> String:
	match action:
		"resume": return "Resume"
		"retry": return "Retry"
		"home": return "Return to house"
		"grind_hand": return "Grind balance"
		"manual_hand": return "Manual balance"
		_: return "Exit"


# The two balance buttons say which hand, raised, moves the meter to the right (pressing one switches it).
func set_hands(grind: String, manual: String) -> void:
	(buttons["grind_hand"] as Button).text = "%s: %s hand up = right" % [caption_for("grind_hand"), grind]
	(buttons["manual_hand"] as Button).text = "%s: %s hand up = right" % [caption_for("manual_hand"), manual]


func _build(in_house: bool, title: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PIXELS)
	panel.add_theme_stylebox_override("panel", _box(PANEL, PANEL, 0))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = title.to_upper()
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 34)
	heading.add_theme_color_override("font_color", ACCENT)
	column.add_child(heading)
	for action: String in actions_for(in_house):
		var button := Button.new()
		button.text = caption_for(action)
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE if vr else Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size", 38)
		button.add_theme_color_override("font_color", Color("f8f4e8"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_color_override("font_focus_color", Color.WHITE)
		var idle := _box(Color(0.1, 0.17, 0.2), Color(0.18, 0.32, 0.35), 4)
		var lit := _box(Color(0.12, 0.3, 0.32), ACCENT, 4)
		button.add_theme_stylebox_override("normal", idle)
		button.add_theme_stylebox_override("hover", lit)
		button.add_theme_stylebox_override("focus", lit)
		button.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.5, 0.5), Color.WHITE, 4))
		button.pressed.connect(func() -> void: chosen.emit(action))
		button.mouse_entered.connect(func() -> void:
			over = button
			hovered.emit())
		button.mouse_exited.connect(func() -> void:
			if over == button:
				over = null)
		column.add_child(button)
		buttons[action] = button
	return panel


static func _box(fill: Color, edge: Color, border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(18)
	return box


func _build_frame(parent: Node) -> void:
	root = Node3D.new()
	root.name = "WatchMenu"
	root.visible = false
	parent.add_child(root)
	var frame := (load(FRAME) as PackedScene).instantiate() as Node3D
	frame.scale = Vector3.ONE * FRAME_SCALE
	root.add_child(frame)

	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(content)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	var plane := QuadMesh.new()
	plane.size = INNER * FRAME_SCALE
	var quad := MeshInstance3D.new()
	quad.mesh = plane
	quad.material_override = material
	quad.position = Vector3(0, 0, FACE_Z * FRAME_SCALE)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(quad)

	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.albedo_color = ACCENT
	beam.no_depth_test = true
	beam.render_priority = 110
	var line := CylinderMesh.new()
	line.top_radius = 0.0015
	line.bottom_radius = 0.0015
	line.height = 1.0
	line.radial_segments = 6
	laser = MeshInstance3D.new()
	laser.mesh = line
	laser.material_override = beam
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	laser.top_level = true
	root.add_child(laser)
	var ball := SphereMesh.new()
	ball.radius = 0.008
	ball.height = 0.016
	ball.radial_segments = 8
	ball.rings = 4
	dot = MeshInstance3D.new()
	dot.mesh = ball
	dot.material_override = beam
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.top_level = true
	root.add_child(dot)


# Show it: in the headset hung in front of `head` (a world transform), on a flat screen over the game.
func open(head: Transform3D) -> void:
	is_open = true
	down_was = false
	over = null
	if vr:
		var forward := -head.basis.z
		forward.y = 0.0
		forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
		root.global_position = head.origin + forward * DISTANCE + Vector3(0.0, -DROP, 0.0)
		root.global_basis = Basis.looking_at(forward, Vector3.UP)   # the frame faces +Z: towards you
		root.visible = true
	else:
		layer.visible = true
		(buttons["resume"] as Button).grab_focus()


func close() -> void:
	is_open = false
	over = null
	if vr:
		root.visible = false
		viewport.push_input(_motion(Vector2(-10, -10)))   # (so no button stays lit for the next time)
	else:
		layer.visible = false


# Where a ray meets the menu's face, in pixels of the content (Vector2.INF if it points away or past the edge).
# `face`: the menu's transform in the world.
static func ray_to_pixel(face: Transform3D, origin: Vector3, direction: Vector3) -> Vector2:
	var inverse := face.affine_inverse()
	var o := inverse * origin
	var d := inverse.basis * direction
	if absf(d.z) < 1e-6:
		return Vector2.INF
	var t := (FACE_Z * FRAME_SCALE - o.z) / d.z
	if t < 0.0:
		return Vector2.INF
	var p := o + d * t
	var size := INNER * FRAME_SCALE
	var u := p.x / size.x + 0.5
	var v := 0.5 - p.y / size.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return Vector2.INF
	return Vector2(u * PIXELS.x, v * PIXELS.y)


static func _motion(at: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	return e


# Every frame while it is open (headset only): `origin` / `direction` the pointing hand's ray in the world, `down` the trigger.
func update(origin: Vector3, direction: Vector3, down: bool) -> void:
	if not vr or not is_open:
		return
	var pixel := ray_to_pixel(root.global_transform, origin, direction)
	var hit := pixel != Vector2.INF
	viewport.push_input(_motion(pixel if hit else Vector2(-10, -10)))
	if hit and down != down_was:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = pixel
		click.global_position = pixel
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		viewport.push_input(click)
	elif not hit and down_was and not down:
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		viewport.push_input(release)
	down_was = down
	# The laser runs from the hand to where it lands (or a little way into the distance).
	var reach := REACH
	if hit:
		var local := root.global_transform.affine_inverse() * origin
		var local_d := root.global_transform.affine_inverse().basis * direction
		reach = (FACE_Z * FRAME_SCALE - local.z) / local_d.z
	var end := origin + direction.normalized() * reach
	laser.global_transform = Transform3D(Basis.looking_at(direction.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0), origin.lerp(end, 0.5))
	laser.scale = Vector3(1.0, reach, 1.0)
	dot.global_position = end
	dot.visible = hit
