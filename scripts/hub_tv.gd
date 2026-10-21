# The level select: the TV in the lounge shows a picture of a level and its name; pick up the remote (squeeze a grip with your hand
# next to it) and push the stick left or right to change level, trigger to go. On a flat screen: E picks it up when you are near,
# left / right change the level, Enter goes, E puts it down.
class_name HubTv
extends RefCounted

signal chosen(level_id: String)

const PICK_DISTANCE := 0.35      # metres from the hand to the remote to pick it up (a flat screen: from the player)
const FLAT_PICK_DISTANCE := 3.0
const STICK_ON := 0.7
const STICK_OFF := 0.3
const PICTURES := "res://assets/previews/%s.jpg"
const HOLD_MODE := 1                       # how the remote sits in a hand (HubRemote.in_hand)
const REST := Vector3(0.0, 0.011, 0.0)   # the remote lies on the table, not in it

var screen: MeshInstance3D
var spot: Node3D                 # where the remote lies when nobody has it
var remote: Node3D
var viewport: SubViewport
var picture: TextureRect
var title: Label
var hint: Label
var channel := 0
var holder := ""                 # "left", "right", "key" or "" (nobody)
var held_state                    # the VrHands.HandState of the hand that has it (headset)
var _in_hand := Transform3D.IDENTITY
var vr := false
var _latched := false
var _trigger_was := false
var _squeeze_was := {}


# `parent` must be in the tree (the screen's picture is drawn by a viewport inside it). `start_id` is the level the TV opens on.
func _init(p_screen: MeshInstance3D, p_spot: Node3D, parent: Node, start_id: String, p_vr := false) -> void:
	vr = p_vr
	screen = p_screen
	spot = p_spot
	channel = maxi(0, Levels.PLAYABLE.find(start_id))
	remote = HubRemote.build()
	spot.add_child(remote)
	remote.position = REST

	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	parent.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.03, 0.04)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)
	picture = TextureRect.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	viewport.add_child(picture)
	title = Hud.make_label("", 44)
	title.position = Vector2(28, 270)
	viewport.add_child(title)
	hint = Hud.make_label("", 22)
	hint.position = Vector2(28, 322)
	viewport.add_child(hint)
	if screen != null:
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = viewport.get_texture()
		screen.material_override = material
	_show()


func level_id() -> String:
	return Levels.PLAYABLE[channel]


func _show() -> void:
	var id := level_id()
	var path := PICTURES % id
	picture.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	title.text = Levels.LEVELS[id].name
	if holder != "":
		hint.text = "< >  change level      trigger: play" if vr else "left / right: change level      Enter: play"
	else:
		hint.text = "pick up the remote (squeeze a grip next to it)" if vr else "pick up the remote (press E next to it)"
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func step(by: int) -> void:
	channel = posmod(channel + by, Levels.PLAYABLE.size())
	_show()


# `pointers`: one per hand (or one for the keyboard): { id, node (what the remote is held by), pos (world), squeeze, stick_x, trigger }.
# `held_by` is the node the remote should sit in while held.
func update(pointers: Array) -> void:
	if held_state != null:
		remote.global_transform = held_state.model.socket_global() * _in_hand
	if holder == "":
		for p: Dictionary in pointers:
			var was: bool = _squeeze_was.get(p.id, false)
			var reach := FLAT_PICK_DISTANCE if p.id == "key" else PICK_DISTANCE
			if p.squeeze and not was and (p.pos as Vector3).distance_to(remote.global_position) < reach:
				holder = p.id
				held_state = p.get("state")
				if held_state != null:
					# in the hand: the fingers close round it and it follows the hand's grip
					held_state.held = true
					held_state.held_pose = VrHands.GRIP_POSES["medium"]
					held_state.path_elapsed = 0.0
					_in_hand = HubRemote.in_hand(p.id, HOLD_MODE)
				else:
					remote.reparent(p.node, false)
					remote.transform = Transform3D(Basis(Vector3.UP, 0.25), Vector3(0.22, -0.2, -0.5))
				_latched = absf(p.stick_x) > STICK_ON   # a stick already pushed over does not change the channel the moment it is picked up
				_trigger_was = p.trigger
				_show()
		for p: Dictionary in pointers:
			_squeeze_was[p.id] = p.squeeze
		return
	for p: Dictionary in pointers:
		if p.id != holder:
			continue
		if not p.squeeze:
			_put_down()
			break
		var x: float = p.stick_x
		if absf(x) < STICK_OFF:
			_latched = false
		elif absf(x) > STICK_ON and not _latched:
			_latched = true
			step(1 if x > 0.0 else -1)
		if p.trigger and not _trigger_was:
			chosen.emit(level_id())
		_trigger_was = p.trigger
	for p: Dictionary in pointers:
		_squeeze_was[p.id] = p.squeeze


func _put_down() -> void:
	if held_state != null:
		held_state.held = false
		held_state.held_pose = null
		held_state = null
	holder = ""
	remote.reparent(spot, false)
	remote.transform = Transform3D(Basis.IDENTITY, REST)
	_show()
