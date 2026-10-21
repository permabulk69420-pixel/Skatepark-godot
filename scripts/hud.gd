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
var score_label: Label
var time_label: Label
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

	score_label = make_label("", 20)
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	score_label.offset_top = 18.0
	score_label.offset_right = -24.0
	layer.add_child(score_label)
	set_score(0)

	time_label = make_label("", 20)
	time_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	time_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	time_label.offset_top = 46.0
	time_label.offset_right = -24.0
	layer.add_child(time_label)


static func make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f8f4e8"))
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", maxi(3, size / 4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# The balance meter: a dark rounded strip with a faint teal band in the middle (the steady zone) and a thin marker that is
# off-white, turning soft orange once you are drifting towards a fall. Returns [bar, marker].
const MARKER_OK := Color("f2eee2")
const MARKER_WARN := Color("e8864f")
const BAR_FILL := Color(0.05, 0.09, 0.11, 0.78)
const BAR_EDGE := Color(0.18, 0.32, 0.35, 0.9)
const BAR_ZONE := Color(0.37, 0.82, 0.75, 0.30)


static func _pill(fill: Color, edge: Color, border: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_corner_radius_all(radius)
	return box


static func make_balance_bar(width: float, height: float) -> Array:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	var track := Panel.new()
	track.size = Vector2(width, height)
	track.add_theme_stylebox_override("panel", _pill(BAR_FILL, BAR_EDGE, maxi(1, int(height / 10.0)), int(height / 2.0)))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)
	var zone := Panel.new()
	zone.size = Vector2(width * 0.4, height * 0.5)
	zone.position = Vector2(width * 0.3, height * 0.25)
	zone.add_theme_stylebox_override("panel", _pill(BAR_ZONE, Color(0, 0, 0, 0), 0, int(height / 4.0)))
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(zone)
	var marker := ColorRect.new()
	marker.color = MARKER_OK
	marker.size = Vector2(maxf(4.0, height * 0.4), height * 1.5)
	marker.position = Vector2(marker_x(width, 0.0) - marker.size.x / 2.0, -height * 0.25)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(marker)
	return [bar, marker]


# The x of the marker's centre for a balance of bal (−1..1, 0 = middle) on a bar that wide.
static func marker_x(width: float, bal: float) -> float:
	return width / 2.0 + clampf(bal, -1.0, 1.0) * width / 2.0


func say(text: String, seconds: float = 1.4) -> void:
	message = text
	message_time = seconds


# The running total, top right (a flat screen only: the headset shows a banked chain's points, and the watch will carry the total).
func set_score(total: int) -> void:
	score_label.text = "SCORE  %s" % Score.format(total)


# A run's clock under the score ("" for a level with no run).
func set_time(text: String) -> void:
	time_label.text = "" if text == "" else "TIME  " + text


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
