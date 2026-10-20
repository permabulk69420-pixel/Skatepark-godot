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


# The two gates as things you can see: a flat ribbon painted on the ground across the track, following the ground's shape.
# Start: a thin green line. Finish: a chequered strip.
func build_gates(parent: Node3D, world: SkateWorld) -> void:
	_build_ribbon(parent, world, start, "Start", 0.4, Color("2fd37a"), false)
	_build_ribbon(parent, world, finish, "Finish", 1.6, Color.WHITE, true)


static func _build_ribbon(parent: Node3D, world: SkateWorld, g: Gate, label: String, depth: float, colour: Color, checkered: bool) -> void:
	var side := g.side()
	var hit := SkateWorld.Hit.new()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := maxi(2, int(ceil(g.half_width * 2.0)))   # a column a metre across, each dropped onto the ground under it
	var square := 0.4
	var points: Array = []
	for i in columns + 1:
		var u := -g.half_width + (g.half_width * 2.0) * float(i) / float(columns)
		var edge := []
		for along in [depth * 0.5, -depth * 0.5]:
			var p: Vector3 = g.pos + side * u + g.forward * along
			var found := world.ground(p.x, p.z, g.pos.y + 1.5, hit, 4.0)
			edge.append(Vector3(p.x, (found.y if found != null else g.pos.y) + 0.04, p.z))
		points.append([edge, (u + g.half_width) / square])
	for i in columns:
		var a: Array = points[i]
		var b: Array = points[i + 1]
		var quad := [[a[0][0], Vector2(a[1], 0.0)], [a[0][1], Vector2(a[1], depth / square)], [b[0][0], Vector2(b[1], 0.0)],
			[b[0][0], Vector2(b[1], 0.0)], [a[0][1], Vector2(a[1], depth / square)], [b[0][1], Vector2(b[1], depth / square)]]
		for v in quad:
			tool.set_uv(v[1])
			tool.add_vertex(v[0])
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.albedo_color = colour
	if checkered:
		paint.albedo_texture = _checker_texture()
		paint.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var strip := MeshInstance3D.new()
	strip.mesh = tool.commit()
	strip.material_override = paint
	strip.name = label + "Line"
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(strip)


# Black and white squares, made here (no image file).
static func _checker_texture() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	for x in 2:
		for y in 2:
			image.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color(0.04, 0.04, 0.04))
	return ImageTexture.create_from_image(image)
