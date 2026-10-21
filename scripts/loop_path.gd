# Loops (a full 360° loop-the-loop). A loop is a ribbon: a centreline on the riding surface plus, at every point, the surface's
# normal (pointing into the loop, the way the board's wheels point away from). The park file stores it in node extras
# (role "loop_path": points, normals, width). While the board is on the ribbon the sim rides it as a single number s along the
# centreline, like a grind, because a heading-plus-up board cannot describe riding upside down.
class_name LoopPath
extends RefCounted


# A point on the ribbon: the centreline position, tangent t, normal n, across-the-track b, and curvature k towards the normal.
class Frame:
	var p := Vector3.ZERO
	var t := Vector3.ZERO
	var n := Vector3.UP
	var b := Vector3.ZERO
	var k := 0.0


var name := "loop"
var width := 2.4
var p: Array[Vector3] = []
var n: Array[Vector3] = []
var t: Array[Vector3] = []
var b: Array[Vector3] = []
var k: Array[float] = []
var s: Array[float] = [0.0]
var length := 0.0
var across := Vector3.ZERO   # across the lanes, flat: the run in and the run out both point square to it
var bounds: AABB
var top := 0.0
var s_in := 0.0              # the riding window (see window()), set by the Skater
var s_out := 0.0


# points / normals: flat [x, y, z, …] arrays (world space); width: of the riding surface.
func _init(p_name: String, points: Array, normals: Array, p_width: float) -> void:
	name = p_name
	width = p_width
	var count := points.size() / 3
	for i in count:
		p.append(Vector3(points[i * 3], points[i * 3 + 1], points[i * 3 + 2]))
		n.append(Vector3(normals[i * 3], normals[i * 3 + 1], normals[i * 3 + 2]).normalized())
	for i in range(1, count):
		s.append(s[i - 1] + p[i].distance_to(p[i - 1]))
	length = s[count - 1]
	for i in count:
		var a := p[maxi(0, i - 1)]
		var c := p[mini(count - 1, i + 1)]
		var tv := (c - a).normalized()
		var nn := n[i]
		nn = (nn - tv * nn.dot(tv)).normalized()   # keep the normal square to the track
		n[i] = nn
		t.append(tv)
		b.append(tv.cross(nn).normalized())          # across the track, to the right of travel
	# Curvature towards the normal (how hard the surface turns the board), from the change of tangent.
	for i in count:
		var i0 := maxi(0, i - 1)
		var i1 := mini(count - 1, i + 1)
		var span := s[i1] - s[i0]
		k.append((t[i1] - t[i0]).dot(n[i]) / span if span > 1e-6 else 0.0)
	across = Vector3(b[0].x, 0.0, b[0].z).normalized()
	bounds = AABB(p[0], Vector3.ZERO)
	top = p[0].y
	for q in p:
		bounds = bounds.expand(q)
		top = maxf(top, q.y)
	bounds = bounds.grow(width / 2.0 + 0.6)


# The riding window: from the first to the last point whose normal has tilted past ny (0.97 by default). Outside it the ribbon is
# ordinary ground (the run in and the run out, lying on the floor).
func window(enter_ny: float) -> Vector2:
	var count := n.size()
	var lo := 0
	var hi := count - 1
	while lo < count - 1 and n[lo].y >= enter_ny:
		lo += 1
	while hi > 0 and n[hi].y >= enter_ny:
		hi -= 1
	return Vector2(s[maxi(0, lo - 1)], s[mini(count - 1, hi + 1)])


func index(at: float) -> int:
	var lo := 0
	var hi := s.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if s[mid] <= at:
			lo = mid
		else:
			hi = mid - 1
	return lo


func frame(at: float) -> Frame:
	var out := Frame.new()
	at = minf(maxf(at, 0.0), length)
	var i := index(at)
	var span := s[i + 1] - s[i]
	var f := (at - s[i]) / span if span > 1e-9 else 0.0
	out.p = p[i].lerp(p[i + 1], f)
	out.t = t[i].lerp(t[i + 1], f).normalized()
	out.n = n[i].lerp(n[i + 1], f)
	out.n = (out.n - out.t * out.n.dot(out.t)).normalized()
	out.b = out.t.cross(out.n).normalized()
	out.k = k[i] + (k[i + 1] - k[i]) * f
	return out


# Where a point is on the ribbon, between arc lengths s_min and s_max: s, l (across, + to the right), h (height above the surface
# along its normal). Picks the stretch the point is closest to the surface of. Null if it is not over the ribbon.
func project(pos: Vector3, s_min: float, s_max: float, max_h: float = 0.3):
	var best := INF
	var half := width / 2.0
	var out = null
	var i := index(s_min)
	while i < p.size() - 1 and s[i] <= s_max:
		var a := p[i]
		var seg := p[i + 1] - a
		var len2 := seg.length_squared()
		if len2 < 1e-12:
			i += 1
			continue
		var r := pos - a
		var f := r.dot(seg) / len2
		if f < -0.02 or f > 1.02:
			i += 1
			continue
		var fc := minf(maxf(f, 0.0), 1.0)
		var q := pos - (a + seg * fc)
		var h := q.dot(n[i])
		var l := q.dot(b[i])
		if absf(h) > max_h or absf(l) > half:
			i += 1
			continue
		if absf(h) < best:
			best = absf(h)
			out = {"s": s[i] + fc * (s[i + 1] - s[i]), "l": l, "h": h}
		i += 1
	return out


static func parse(nodes: Array) -> Array[LoopPath]:
	var loops: Array[LoopPath] = []
	for node: Node3D in nodes:
		var data: Dictionary = node.get_meta("extras", {})
		var points = data.get("points")
		var normals = data.get("normals")
		if points == null or normals == null or points.size() < 12:
			continue
		# Stored in world space by the park builder; a moved node would need its matrix applied (none is).
		loops.append(LoopPath.new(node.name, points, normals, data.get("width", 2.4)))
	return loops
