# Grind paths come from the park file as polylines stored in node extras (role "grind_path").
# Each becomes a list of segments with cumulative arc length so a grind can be a single number, s.
class_name GrindPath
extends RefCounted

const T = Config.Tuning
const BOARD = Config.Board


class Segment:
	var a: Vector3
	var b: Vector3
	var dir: Vector3
	var dir_h: Vector2
	var h_len: float
	var length: float
	var start: float
	var pit_known := false   # the side of the lip that is the drop is worked out once per segment (see Skater.pit_direction)
	var pit = null           # Vector2 or null


var name := ""
var kind := "rail"
var closed := false
var radius := 0.025
var points: Array[Vector3] = []
var segments: Array[Segment] = []
var cumulative: Array[float] = [0.0]
var bounds: AABB
var length := 0.0
var friction := 0.0
var top_offset := 0.0       # height of the surface the board actually touches above the stored line
var slide_contact := 0.0    # a ledge is solid underneath, so a board across it rides on its wheels rather than on the deck underside


func _init(p_name: String, p_kind: String, p_closed: bool, p_radius: float, p_points: Array[Vector3]) -> void:
	name = p_name
	kind = p_kind if p_kind in ["rail", "coping", "ledge"] else "rail"
	closed = p_closed
	radius = p_radius if p_radius > 0.0 else 0.025
	points = p_points
	var n := points.size()
	var seg_count := n if closed else n - 1
	bounds = AABB(points[0], Vector3.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	for i in seg_count:
		var a := points[i]
		var b := points[(i + 1) % n]
		var dir := b - a
		var seg_length := dir.length()
		if seg_length < 1e-6:
			continue
		dir = dir / seg_length
		var dir_h := Vector2(dir.x, dir.z)
		var h_len := dir_h.length()
		if h_len > 1e-6:
			dir_h = dir_h / h_len
		var seg := Segment.new()
		seg.a = a
		seg.b = b
		seg.dir = dir
		seg.dir_h = dir_h
		seg.h_len = h_len
		seg.length = seg_length
		seg.start = cumulative[cumulative.size() - 1]
		segments.append(seg)
		cumulative.append(cumulative[cumulative.size() - 1] + seg_length)
	length = cumulative[cumulative.size() - 1]
	bounds = bounds.grow(0.6)
	friction = T.grindFriction[kind]
	top_offset = radius * T.railTopOffset[kind]
	slide_contact = 0.0 if kind == "ledge" else BOARD.deckBottom


func segment_at(s: float) -> Segment:
	var lo := 0
	var hi := segments.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if segments[mid].start <= s:
			lo = mid
		else:
			hi = mid - 1
	return segments[lo]


func point_at(s: float) -> Vector3:
	var seg := segment_at(s)
	var t := clampf((s - seg.start) / seg.length, 0.0, 1.0)
	return seg.a.lerp(seg.b, t)


# Builds the paths from the park's "grind_path" nodes. Their points are stored in each node's local space, so the nodes must be in the tree.
static func parse(nodes: Array) -> Array[GrindPath]:
	var paths: Array[GrindPath] = []
	for node: Node3D in nodes:
		var data: Dictionary = node.get_meta("extras", {})
		var raw = data.get("points")
		if raw == null or raw.size() < 6:
			continue
		var xf := node.global_transform
		var pts: Array[Vector3] = []
		var i := 0
		while i + 2 < raw.size():
			pts.append(xf * Vector3(raw[i], raw[i + 1], raw[i + 2]))
			i += 3
		var is_closed: bool = data.get("closed", false)
		# A closed loop that repeats its first point would add a zero-length segment; drop the duplicate.
		if is_closed and pts.size() > 2 and pts[0].distance_squared_to(pts[pts.size() - 1]) < 1e-8:
			pts.pop_back()
		var path := GrindPath.new(node.name, data.get("kind", "rail"), is_closed, data.get("radius", 0.0), pts)
		if path.segments.size() > 0:
			paths.append(path)
	return paths
