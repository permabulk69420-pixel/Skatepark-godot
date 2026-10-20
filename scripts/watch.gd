# The watch on the left wrist (assets/hud/watch.glb). Its screen is a small viewport showing the running score. Tapping the
# glass with the right index finger opens the menu (WatchMenu); the tap is worked out here from where the fingertip is.
class_name Watch
extends RefCounted

const MODEL := "res://assets/hud/watch.glb"
const PIXELS := 256
const BACKGROUND := Color(0.02, 0.04, 0.05)
const CAPTION_COLOUR := Color("6fb7ad")
const SCORE_COLOUR := Color("f8f4e8")
# A tap: the fingertip is over the glass and has come down to it. It cannot tap again until it has been lifted clear.
const POKE_RADIUS := 0.03     # metres from the middle of the glass, across it
const POKE_DEPTH := 0.012     # metres above the glass or nearer
const POKE_FLOOR := -0.02     # (and not through the wrist)
const POKE_CLEAR := 0.04      # metres above the glass that re-arms it
const POKE_AWAY := 0.06       # or this far across

var root: Node3D
var face: Node3D              # the middle of the glass, +Y out of it
var viewport: SubViewport
var caption: Label
var number: Label
var clock: Label              # a run's time, under the score (empty when the level has no run)
var armed := true


# `model`: the left hand. The watch sits on its wrist at the model's own origin.
func _init(model: HandModel) -> void:
	var scene := (load(MODEL) as PackedScene).instantiate() as Node3D
	root = scene
	root.name = "Watch"
	model.root.add_child(root)
	face = root.find_child("watch_face", true, false) as Node3D

	viewport = SubViewport.new()
	viewport.size = Vector2i(PIXELS, PIXELS)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	viewport.add_child(column)
	caption = _label("SCORE", 34, CAPTION_COLOUR)
	column.add_child(caption)
	number = _label("", 100, SCORE_COLOUR)
	column.add_child(number)
	clock = _label("", 50, CAPTION_COLOUR)
	column.add_child(clock)
	set_score(0)

	var screen := root.find_child("Watch_Screen", true, false) as MeshInstance3D
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	screen.material_override = material


static func _label(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func set_score(total: int) -> void:
	var text := Score.format(total)
	number.text = text
	number.add_theme_font_size_override("font_size", font_size_for(text))


func set_time(text: String) -> void:
	if clock.text != text:
		clock.text = text


# Big for a short number, smaller as it grows, so it always fits across the glass.
static func font_size_for(text: String) -> int:
	return clampi(int(210.0 / (maxf(1.0, float(text.length())) * 0.6)), 36, 100)


# Is a fingertip (in the glass's own frame: +Y out of it) on the glass?
static func poke_hit(local: Vector3) -> bool:
	return Vector2(local.x, local.z).length() < POKE_RADIUS and local.y < POKE_DEPTH and local.y > POKE_FLOOR


# Is it well clear of the glass again?
static func poke_clear(local: Vector3) -> bool:
	return local.y > POKE_CLEAR or Vector2(local.x, local.z).length() > POKE_AWAY


# `tip`: the right index fingertip in the world. True on the frame it taps the glass.
func update(tip: Vector3) -> bool:
	var local := face.global_transform.affine_inverse() * tip
	if armed and poke_hit(local):
		armed = false
		return true
	if not armed and poke_clear(local):
		armed = true
	return false
