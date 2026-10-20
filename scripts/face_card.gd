# A card in front of your face for a moment: "GO" as a run starts, the time and score as it finishes. In the headset it is fixed to your
# head (a little below straight ahead); on a flat screen it is a panel in the middle of the window.
class_name FaceCard
extends RefCounted

const PIXELS := Vector2i(640, 360)
const WIDTH := 0.8             # metres across, in the headset
const DISTANCE := 1.1
const DROP := 0.12
const FADE := 0.4

var vr: bool
var panel: Control             # what is drawn (in the headset inside a viewport)
var title: Label
var lines: Label
var quad: MeshInstance3D       # headset only
var seconds_left := 0.0


# `camera`: the headset camera the card hangs from (headset only). `layer`: the flat screen's overlay (flat screen only).
func _init(p_vr: bool, camera: Node3D, layer: CanvasLayer) -> void:
	vr = p_vr
	panel = Control.new()
	panel.custom_minimum_size = Vector2(PIXELS)
	panel.size = Vector2(PIXELS)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	title = Hud.make_label("", 110)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	lines = Hud.make_label("", 48)
	lines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(lines)
	if vr:
		var viewport := SubViewport.new()
		viewport.size = PIXELS
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		camera.add_child(viewport)
		viewport.add_child(panel)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = viewport.get_texture()
		material.no_depth_test = true
		material.render_priority = 100
		var plane := QuadMesh.new()
		plane.size = Vector2(WIDTH, WIDTH * PIXELS.y / PIXELS.x)
		quad = MeshInstance3D.new()
		quad.mesh = plane
		quad.material_override = material
		quad.position = Vector3(0.0, -DROP, -DISTANCE)
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		quad.visible = false
		camera.add_child(quad)
	else:
		panel.set_anchors_preset(Control.PRESET_CENTER)
		panel.position = -Vector2(PIXELS) / 2.0
		panel.visible = false
		layer.add_child(panel)


# Put it up for `seconds`. `title_text`: the big word; `body`: lines under it (one per entry).
func show_card(title_text: String, body: Array, seconds: float) -> void:
	title.text = title_text
	lines.text = "\n".join(PackedStringArray(body))
	lines.visible = not body.is_empty()
	seconds_left = seconds
	_set_alpha(1.0)
	if vr:
		quad.visible = true
	else:
		panel.visible = true


func hide_card() -> void:
	seconds_left = 0.0
	if vr:
		quad.visible = false
	else:
		panel.visible = false


func update(dt: float) -> void:
	if seconds_left <= 0.0:
		return
	seconds_left -= dt
	if seconds_left <= 0.0:
		hide_card()
	else:
		_set_alpha(clampf(seconds_left / FADE, 0.0, 1.0))


func _set_alpha(alpha: float) -> void:
	panel.modulate.a = alpha
