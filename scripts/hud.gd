# The flat-screen overlay: the park's name, the trick or balance readout, speed, and the controls hint.
# (The VR gauge that hangs in the play space comes with the headset layer.)
class_name Hud
extends RefCounted

const OUTLINE := Color(0.06, 0.15, 0.16, 0.9)

var layer: CanvasLayer
var fade_rect: ColorRect
var sim: Skater
var trick_label: Label
var speed_label: Label
var balance_bar: Control
var balance_marker: ColorRect
var hint_label: Label
var status_label: Label
var message := ""
var message_time := 0.0
var hint_time := 14.0


func _init(parent: Node, p_sim: Skater, level_name: String, hint: String) -> void:
	sim = p_sim
	layer = CanvasLayer.new()
	layer.name = "Hud"
	layer.layer = 10
	parent.add_child(layer)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	layer.add_child(fade_rect)

	var title := make_label("SKATE PARK  ·  %s" % level_name.to_upper(), 13)
	title.position = Vector2(24, 20)
	layer.add_child(title)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -28.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom)

	trick_label = make_label("", 24)
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_label.custom_minimum_size = Vector2(500, 32)
	bottom.add_child(trick_label)

	var bar_parts := make_balance_bar(240.0, 10.0)
	balance_bar = bar_parts[0]
	balance_marker = bar_parts[1]
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(balance_bar)
	bottom.add_child(bar_row)

	speed_label = make_label("", 13)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(speed_label)

	hint_label = make_label(hint, 12)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.custom_minimum_size = Vector2(440, 0)
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_label.offset_left = 24.0
	hint_label.offset_bottom = -24.0
	hint_label.offset_top = -120.0
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	layer.add_child(hint_label)

	status_label = make_label("", 16)
	status_label.set_anchors_preset(Control.PRESET_CENTER)
	status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(status_label)


static func make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f8f4e8"))
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", maxi(3, size / 4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# The balance meter: a strip that goes red - amber - green - amber - red, with a white marker. Returns [bar, marker].
static func make_balance_bar(width: float, height: float) -> Array:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.30, 0.70, 0.88, 1.0])
	gradient.colors = PackedColorArray([Color("b5412f"), Color("b08a2e"), Color("2f7d63"), Color("2f7d63"), Color("b08a2e"), Color("b5412f")])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = int(width)
	var strip := TextureRect.new()
	strip.texture = texture
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.size = Vector2(width, height)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(strip)
	var marker := ColorRect.new()
	marker.color = Color.WHITE
	marker.size = Vector2(maxf(4.0, height * 0.4), height * 2.0)
	marker.position = Vector2(marker_x(width, 0.0) - marker.size.x / 2.0, -height * 0.5)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(marker)
	return [bar, marker]


# The x of the marker's centre for a balance of bal (−1..1, 0 = middle) on a bar that wide.
static func marker_x(width: float, bal: float) -> float:
	return width / 2.0 + clampf(bal, -1.0, 1.0) * width / 2.0


func say(text: String, seconds: float = 1.4) -> void:
	message = text
	message_time = seconds


func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


func update(dt: float) -> void:
	message_time -= dt
	hint_time -= dt
	hint_label.modulate.a = clampf(hint_time / 2.0, 0.0, 1.0)
	var g = sim.balance
	var show_message := message_time > 0.0
	var text := ""
	if g != null:
		text = "%s %.1fs" % [g.name, g.time]
	elif show_message:
		text = message
	elif sim.mode == Skater.Mode.AIR:
		text = "air"
	trick_label.text = text
	speed_label.text = "%.1f m/s" % sim.speed
	balance_bar.visible = g != null
	if g != null:
		balance_marker.position.x = marker_x(240.0, g.bal) - balance_marker.size.x / 2.0
