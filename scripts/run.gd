# A timed run down a level (Flightline): the clock starts as you cross the start gate and stops as you cross the finish gate.
# `update` says when either happened; what to show and what to do about it is main.gd's business.
class_name Run
extends RefCounted

enum State { WAITING, RUNNING, DONE }

const MAX_STEP := 30.0     # metres in one frame: more than that is a teleport (a respawn), not riding across a gate

var state := State.WAITING
var time := 0.0            # seconds since the start gate (frozen once the run is done)
var final_score := 0       # what the run was worth, set by whoever hears "finish"
var start: Gate
var finish: Gate


# A line across the way: crossed once, in the direction of `forward`, inside its width and at least `min_y` high.
class Gate:
	var pos := Vector3.ZERO
	var forward := Vector3(0, 0, -1)
	var half_width := 8.0
	var min_y := -1e9

	static func from_info(info: Dictionary) -> Gate:
		var g := Gate.new()
		g.pos = Vector3(info.pos[0], info.pos[1], info.pos[2])
		g.forward = Vector3(info.forward[0], 0.0, info.forward[2]).normalized()
		g.half_width = float(info.half_width)
		g.min_y = float(info.get("min_y", -1e9))
		return g

	func side() -> Vector3:
		return Vector3.UP.cross(forward)

	# Did the move from `a` to `b` cross it, the right way?
	func crossed(a: Vector3, b: Vector3) -> bool:
		var d0 := (a - pos).dot(forward)
		var d1 := (b - pos).dot(forward)
		if not (d0 < 0.0 and d1 >= 0.0):
			return false
		var at := a.lerp(b, d0 / (d0 - d1)) if d0 != d1 else b
		return absf((at - pos).dot(side())) <= half_width and at.y >= min_y


func _init(info: Dictionary) -> void:
	start = Gate.from_info(info.start)
	finish = Gate.from_info(info.finish)


# Back to the start line, the clock at nothing.
func reset() -> void:
	state = State.WAITING
	time = 0.0
	final_score = 0


# Once a frame while riding. `from` / `to`: where the skater was and is. Returns "start", "finish" or "".
func update(dt: float, from: Vector3, to: Vector3) -> String:
	if state == State.RUNNING:
		time += dt
	if from.distance_to(to) > MAX_STEP:
		return ""
	if state == State.WAITING and start.crossed(from, to):
		state = State.RUNNING
		time = 0.0
		return "start"
	if state == State.RUNNING and finish.crossed(from, to):
		state = State.DONE
		return "finish"
	return ""


# 72.4 -> "1:12.4".
static func format_time(seconds: float) -> String:
	var tenths := int(floor(maxf(seconds, 0.0) * 10.0))
	return "%d:%02d.%d" % [tenths / 600, (tenths / 10) % 60, tenths % 10]


# The two gates as things you can see: just a bright line across the way.
func build_gates(parent: Node3D) -> void:
	_build_line(parent, start, "Start", Color("2fd37a"))
	_build_line(parent, finish, "Finish", Color("f8f4e8"))


static func _build_line(parent: Node3D, g: Gate, label: String, colour: Color) -> void:
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = colour
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(g.half_width * 2.0, 0.05, 0.4)
	strip.mesh = box
	strip.material_override = paint
	strip.name = label + "Line"
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(strip)
	strip.global_position = g.pos + Vector3(0.0, 0.05, 0.0)
	strip.global_basis = Basis.looking_at(g.forward, Vector3.UP)
