# The menu: Resume, Retry, Return to house, the two balance-hand choices, Exit (and in the house, Build mode, with its own page). In the headset it is the big frame from the watch (assets/hud/menu_frame.glb) hung
# in front of you, with a laser from the right hand to point and the trigger to press. On a flat screen it is a plain overlay
# (M opens it, the mouse or Up / Down / Enter choose).
class_name WatchMenu
extends RefCounted

signal chosen(action: String)   # "resume", "retry", "home", "build", "grind_hand", "manual_hand" or "exit", or one of BUILD_ACTIONS (the goals page is handled inside the menu)
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
const PANEL := Color(0.043, 0.063, 0.078, 1.0)
const ROW := Color(0.075, 0.105, 0.127, 1.0)           # a button at rest
const ROW_LIT := Color(0.1, 0.17, 0.2, 1.0)            # a button the pointer is on
const TEXT := Color("e9eef0")
const TEXT_DIM := Color("7f9298")
const ROW_HEIGHT := 56
const FONT := 32
const BUILD_ACTIONS := ["build_resume", "add_arcade", "add_rail", "add_bike", "add_funbox", "build_done", "build_cancel", "build_reset"]
const BUILD_HINT := "Trigger: pick up / put down · stick: turn 15° · hold grip: fine control · B: remove one you added"

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
var main_page: VBoxContainer       # the buttons
var goals_page: VBoxContainer      # the goals list (levels with goals), with a Back button
var goals_rows: VBoxContainer
var build_page: VBoxContainer      # build mode's page (the house only)
var building := false              # while building, the menu opens on that page


func _init(parent: Node, p_vr: bool, in_house: bool, title: String, has_goals := false) -> void:
	vr = p_vr
	content = _build(in_house, title, has_goals)
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


# The buttons the menu has for this place (the house has nothing to retry and nowhere to go back to, but it can be built in).
static func actions_for(in_house: bool, has_goals := false) -> Array:
	if in_house:
		return ["resume", "build", "grind_hand", "manual_hand", "exit"]
	if has_goals:
		return ["resume", "retry", "goals", "home", "grind_hand", "manual_hand", "exit"]
	return ["resume", "retry", "home", "grind_hand", "manual_hand", "exit"]


static func caption_for(action: String) -> String:
	match action:
		"resume": return "Resume"
		"retry": return "Retry"
		"goals": return "Goals"
		"home": return "Return to house"
		"build": return "Build mode"
		"build_resume": return "Keep building"
		"add_arcade": return "Add an arcade machine"
		"add_rail": return "Add a flat rail"
		"add_bike": return "Add a dirt bike"
		"add_funbox": return "Add the funbox"
		"build_done": return "Done: save it"
		"build_cancel": return "Cancel: undo the changes"
		"build_reset": return "Put everything back"
		"grind_hand": return "Grind balance"
		"manual_hand": return "Manual balance"
		_: return "Exit"


# The two balance buttons say which hand, raised, moves the meter to the right (pressing one switches it).
func set_hands(grind: String, manual: String) -> void:
	(buttons["grind_hand"] as Button).text = "%s: %s hand up = right" % [caption_for("grind_hand"), grind]
	(buttons["manual_hand"] as Button).text = "%s: %s hand up = right" % [caption_for("manual_hand"), manual]


# The goals page: what each goal is and whether it is done. (Called each time the menu opens.)
func set_goals(lines: Array) -> void:
	if goals_rows == null:
		return
	for child in goals_rows.get_children():
		goals_rows.remove_child(child)
		child.queue_free()
	var done := 0
	for line: Dictionary in lines:
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		row.add_theme_stylebox_override("panel", _row_box(ROW, 0))
		var inner := HBoxContainer.new()
		inner.add_theme_constant_override("separation", 18)
		row.add_child(inner)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(22, 22)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ring := StyleBoxFlat.new()
		ring.bg_color = ACCENT if line.done else Color(0, 0, 0, 0)
		ring.border_color = ACCENT if line.done else TEXT_DIM
		ring.set_border_width_all(3)
		ring.set_corner_radius_all(11)
		dot.add_theme_stylebox_override("panel", ring)
		inner.add_child(dot)
		var text := Label.new()
		text.text = line.text
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", FONT)
		text.add_theme_color_override("font_color", TEXT if line.done else TEXT_DIM)
		inner.add_child(text)
		goals_rows.add_child(row)
		if line.done:
			done += 1
	(buttons["goals"] as Button).text = "%s   %d / %d" % [caption_for("goals"), done, lines.size()]


func _show_goals(show: bool) -> void:
	main_page.visible = not show
	goals_page.visible = show
	over = null
	if not vr:
		(buttons["goals_back" if show else "resume"] as Button).grab_focus()


# Into build mode (or out): the menu opens on the build page, and shows it now if it is up.
func set_building(on: bool) -> void:
	building = on
	if build_page == null:
		return
	main_page.visible = not on
	build_page.visible = on
	over = null
	if is_open and not vr:
		(buttons["build_resume" if on else "resume"] as Button).grab_focus()


func _build(in_house: bool, title: String, has_goals: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PIXELS)
	panel.add_theme_stylebox_override("panel", _box(PANEL, Color(0.14, 0.2, 0.23), 2, 22))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(column)
	main_page = column
	_add_heading(column, title)
	for action: String in actions_for(in_house, has_goals):
		var button := _make_button(caption_for(action))
		if action == "goals":
			button.pressed.connect(func() -> void: _show_goals(true))
		else:
			button.pressed.connect(func() -> void: chosen.emit(action))
		column.add_child(button)
		buttons[action] = button
	if has_goals:
		goals_page = VBoxContainer.new()
		goals_page.add_theme_constant_override("separation", 8)
		goals_page.alignment = BoxContainer.ALIGNMENT_CENTER
		goals_page.visible = false
		margin.add_child(goals_page)
		_add_heading(goals_page, "Goals")
		goals_rows = VBoxContainer.new()
		goals_rows.add_theme_constant_override("separation", 8)
		goals_page.add_child(goals_rows)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 10)
		goals_page.add_child(gap)
		var back := _make_button("Back")
		back.pressed.connect(func() -> void: _show_goals(false))
		goals_page.add_child(back)
		buttons["goals_back"] = back
	if in_house:
		build_page = VBoxContainer.new()
		build_page.add_theme_constant_override("separation", 8)
		build_page.alignment = BoxContainer.ALIGNMENT_CENTER
		build_page.visible = false
		margin.add_child(build_page)
		_add_heading(build_page, "Build")
		var adds := GridContainer.new()   # (the "Add …" buttons two to a row, so the page still fits the frame)
		adds.columns = 2
		adds.add_theme_constant_override("h_separation", 8)
		adds.add_theme_constant_override("v_separation", 8)
		for action: String in BUILD_ACTIONS:
			var button := _make_button(caption_for(action))
			button.pressed.connect(func() -> void: chosen.emit(action))
			if action.begins_with("add_"):
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if adds.get_parent() == null:
					build_page.add_child(adds)
				adds.add_child(button)
			else:
				build_page.add_child(button)
			buttons[action] = button
		var hint := Label.new()
		hint.text = BUILD_HINT
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 18)
		hint.add_theme_color_override("font_color", TEXT_DIM)
		build_page.add_child(hint)
	return panel


# The small title at the top of a page, with a thin line under it.
func _add_heading(parent: Control, text: String) -> void:
	var heading := Label.new()
	heading.text = text.to_upper()
	heading.add_theme_font_size_override("font_size", 26)
	heading.add_theme_color_override("font_color", ACCENT)
	heading.add_theme_constant_override("outline_size", 0)
	parent.add_child(heading)
	var line := ColorRect.new()
	line.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	line.custom_minimum_size = Vector2(0, 2)
	parent.add_child(line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	parent.add_child(gap)


# A menu button: a flat dark row with the text on the left; the one the pointer is on gets a lighter fill and a bar of colour on its left.
func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE if vr else Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", FONT)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	var idle := _row_box(ROW, 0)
	var lit := _row_box(ROW_LIT, 6)
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("hover", lit)
	button.add_theme_stylebox_override("focus", lit)
	button.add_theme_stylebox_override("pressed", _row_box(Color(0.16, 0.3, 0.32), 6))
	button.mouse_entered.connect(func() -> void:
		over = button
		hovered.emit())
	button.mouse_exited.connect(func() -> void:
		if over == button:
			over = null)
	return button


static func _row_box(fill: Color, bar: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(12)
	box.border_color = ACCENT
	box.border_width_left = bar
	box.content_margin_left = 28
	box.content_margin_right = 28
	return box


static func _box(fill: Color, edge: Color, border: int, radius := 18) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(radius)
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
	if goals_page != null:
		goals_page.visible = false
	main_page.visible = not building
	if build_page != null:
		build_page.visible = building
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
		(buttons["build_resume" if building else "resume"] as Button).grab_focus()


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
