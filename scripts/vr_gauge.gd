# The balance gauge and trick names in the headset. It is fixed to your head: always the same spot in your view, a little below
# straight ahead, wherever you look or lean.
class_name VrGauge
extends RefCounted

const BAR_W := 0.5           # metres wide
const DISTANCE := 1.1        # metres in front of your head
const DROP := 0.22           # and this far below straight ahead
const PIXELS := Vector2i(512, 192)

var viewport: SubViewport
var quad: MeshInstance3D
var label: Label
var bar: Control
var marker: ColorRect
var material: StandardMaterial3D


# `camera`: the headset camera it hangs from.
func _init(camera: Node3D) -> void:
	viewport = SubViewport.new()
	viewport.size = PIXELS
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	camera.add_child(viewport)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 14)
	viewport.add_child(column)
	label = Hud.make_label("", 52)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(PIXELS.x, 90)
	column.add_child(label)
	var parts := Hud.make_balance_bar(440.0, 22.0)
	bar = parts[0]
	marker = parts[1]
	var row := CenterContainer.new()
	row.add_child(bar)
	column.add_child(row)

	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = viewport.get_texture()
	material.no_depth_test = true
	material.render_priority = 100
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_repeat = false   # (so the bottom edge of the picture never shows as a line along the top)
	var plane := QuadMesh.new()
	plane.size = Vector2(BAR_W, BAR_W * PIXELS.y / PIXELS.x)
	quad = MeshInstance3D.new()
	quad.mesh = plane
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0.0, -DROP, -DISTANCE)
	quad.visible = false
	camera.add_child(quad)


func update(sim: Skater, message: String, message_time: float) -> void:
	var g = sim.balance
	var show_message := message_time > 0.0
	quad.visible = g != null or show_message
	if not quad.visible:
		return
	bar.visible = g != null
	if g != null:
		marker.position.x = Hud.marker_x(440.0, g.bal) - marker.size.x / 2.0
		var risk := absf(g.bal)
		marker.color = Hud.MARKER_WARN if risk > 0.5 else Hud.MARKER_OK
		label.text = "%s  %.1fs" % [g.name, g.time]
		label.add_theme_color_override("font_color", Color("f8f4e8"))
	else:
		label.text = message
		label.add_theme_color_override("font_color", Color("ff8573") if message == "BAIL" else Color("f4efe2"))
