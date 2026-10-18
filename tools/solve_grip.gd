# Works out how each hand closes round the edge of the board, once, ahead of time, and writes assets/hands/grip_solution.json.
#   godot --headless --path . -s res://tools/solve_grip.gd
#
# A port of the web build's adaptive grip (adaptive-grip.js + grip-contact.js). There, every grab slides an invisible plate (the
# board's edge: 10 cm out of the palm, 12 cm along the edge, 1.6 cm thick) out of the palm until it clears the open hand's skin, then
# closes each finger until its skin touches the plate. The plate is always the same shape in the same place in the hand, so the answer
# is always the same: this finds it here instead of in the headset. Re-run it if the hand models or the plate size change.
extends SceneTree

const CONTACT_MARGIN := 0.001   # one millimetre of clearance for the low-poly skin
const CLOSE_STEPS := 20
const REFINE_STEPS := 5
const MAX_PALM_SHIFT := 0.06
const PLATE_THICKNESS := 0.016
const PLATE_WIDTH := 0.1
const BAR_LENGTH := 0.12        # the plate's length along the edge: about a hand's width
const OUT := "res://assets/hands/grip_solution.json"


# A convex shape as planes: a point is inside when n·p − c < margin for every plane (the same test as the web build's hull).
class Contact:
	var normals: Array[Vector3] = []
	var constants: Array[float] = []
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)

	func contains(p: Vector3, margin: float) -> bool:
		if p.x <= bounds_min.x - margin or p.x >= bounds_max.x + margin or p.y <= bounds_min.y - margin or p.y >= bounds_max.y + margin or p.z <= bounds_min.z - margin or p.z >= bounds_max.z + margin:
			return false
		for i in normals.size():
			if normals[i].dot(p) - constants[i] >= margin:
				return false
		return true

	# Clips the triangle against every plane; whatever survives overlaps the shape (a thin edge passing between vertices counts).
	func intersects_triangle(a: Vector3, b: Vector3, c: Vector3, margin: float) -> bool:
		if maxf(maxf(a.x, b.x), c.x) <= bounds_min.x - margin or minf(minf(a.x, b.x), c.x) >= bounds_max.x + margin \
			or maxf(maxf(a.y, b.y), c.y) <= bounds_min.y - margin or minf(minf(a.y, b.y), c.y) >= bounds_max.y + margin \
			or maxf(maxf(a.z, b.z), c.z) <= bounds_min.z - margin or minf(minf(a.z, b.z), c.z) >= bounds_max.z + margin:
			return false
		var poly: Array[Vector3] = [a, b, c]
		for k in normals.size():
			var n := normals[k]
			var constant := constants[k]
			var next: Array[Vector3] = []
			var previous := poly[poly.size() - 1]
			var previous_distance := n.dot(previous) - constant - margin
			for point in poly:
				var distance := n.dot(point) - constant - margin
				var inside := distance < 0.0
				if inside != (previous_distance < 0.0):
					var t := previous_distance / (previous_distance - distance)
					next.append(previous.lerp(point, t))
				if inside:
					next.append(point)
				previous = point
				previous_distance = distance
			if next.is_empty():
				return false
			poly = next
		return true

	func translate(offset: Vector3) -> void:
		bounds_min += offset
		bounds_max += offset
		for i in normals.size():
			constants[i] += normals[i].dot(offset)


class Joint:
	var bone := -1
	var open: Quaternion
	var grip: Quaternion
	var fist: Quaternion


class Finger:
	var name := ""
	var joints: Array[Joint] = []
	var indices := PackedInt32Array()    # skin vertices that move with this finger
	var tris: Array[PackedInt32Array] = []
	var amounts: Array[float] = []
	var path: Array = []


var hand: HandModel
var to_socket := Transform3D.IDENTITY
var points := PackedVector3Array()
var all_tris: Array[PackedInt32Array] = []
var contact: Contact


func _init() -> void:
	run.call_deferred()


func run() -> void:
	var result := {"plate": {"width": PLATE_WIDTH, "thickness": PLATE_THICKNESS, "length": BAR_LENGTH}}
	var failed := false
	for handedness in ["left", "right"]:
		var solved := solve_hand(handedness)
		if solved.is_empty():
			push_error("could not solve the %s hand" % handedness)
			failed = true
			continue
		result[handedness] = solved
	if not failed:
		var f := FileAccess.open(OUT, FileAccess.WRITE)
		f.store_string(JSON.stringify(result))
		f.close()
		print("wrote ", OUT)
	quit(1 if failed else 0)


func apply_amounts(finger: Finger, amounts: Array[float]) -> void:
	for i in finger.joints.size():
		var j := finger.joints[i]
		hand.set_joint(j.bone, amounts[i], j.open, j.grip, j.fist)


# Every vertex of the skin in the open pose, in the grip socket's frame.
func skin_all() -> void:
	var m := hand.skin_matrices()
	for i in hand.verts.size():
		points[i] = to_socket * hand.skinned_vertex(i, m)


func collides(finger: Finger) -> bool:
	var m := hand.skin_matrices()
	for id in finger.indices:
		points[id] = to_socket * hand.skinned_vertex(id, m)
		if contact.contains(points[id], CONTACT_MARGIN):
			return true
	for t in finger.tris:
		if contact.intersects_triangle(points[t[0]], points[t[1]], points[t[2]], CONTACT_MARGIN):
			return true
	return false


func open_intersects() -> bool:
	for p in points:
		if contact.contains(p, CONTACT_MARGIN):
			return true
	for t in all_tris:
		if contact.intersects_triangle(points[t[0]], points[t[1]], points[t[2]], CONTACT_MARGIN):
			return true
	return false


# Close a finger's joints (jointIndices) towards a fist until its skin meets the plate. A binary search of the endpoints alone can
# jump through a thin shaft, so it walks forward in steps first and refines the step it first touches in.
func advance(finger: Finger, joint_indices: Array) -> void:
	var start := finger.amounts.duplicate()
	var low := 0.0
	var high := 1.0

	var sample := func(amount: float) -> bool:
		for index: int in joint_indices:
			var j := finger.joints[index]
			hand.set_joint(j.bone, lerpf(start[index], 1.0, amount), j.open, j.grip, j.fist)
		return collides(finger)

	for step in range(1, CLOSE_STEPS + 1):
		var next := float(step) / CLOSE_STEPS
		if sample.call(next):
			high = next
			for _i in REFINE_STEPS:
				var middle := (low + high) / 2.0
				if sample.call(middle):
					high = middle
				else:
					low = middle
			break
		low = next
		var pose := []
		for i in finger.joints.size():
			pose.append(lerpf(start[i], 1.0, low) if i in joint_indices else start[i])
		finger.path.append(pose)
	for index: int in joint_indices:
		finger.amounts[index] = lerpf(start[index], 1.0, low)
	apply_amounts(finger, finger.amounts)
	finger.path.append(finger.amounts.duplicate())


func solve_hand(handedness: String) -> Dictionary:
	hand = HandModel.create(handedness)
	all_tris.clear()
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(hand.root)
	hand.prepare_skinning()

	var fingers: Array[Finger] = []
	for finger_name in HandModel.FINGERS:
		var f := Finger.new()
		f.name = finger_name
		for bone: int in hand.finger_bones[finger_name]:
			var j := Joint.new()
			j.bone = bone
			j.open = hand.end_rotation("Open", bone)
			j.grip = hand.end_rotation("Grip", bone)
			j.fist = hand.end_rotation("Fist", bone)
			f.joints.append(j)
			f.amounts.append(0.0)
		if f.joints.size() < 3:
			return {}
		fingers.append(f)

	# which skin belongs to which finger: vertices weighted to any of its joints, and the triangles touching those
	var membership: Array = []
	for i in hand.verts.size():
		membership.append({})
		for channel in 4:
			if hand.vert_weights[i * 4 + channel] < 0.01:
				continue
			var bone := hand.skin_bone[hand.vert_bones[i * 4 + channel]]
			for f in fingers:
				for j in f.joints:
					if j.bone == bone:
						membership[i][f.name] = true
	for t in range(0, hand.triangles.size(), 3):
		all_tris.append(PackedInt32Array([hand.triangles[t], hand.triangles[t + 1], hand.triangles[t + 2]]))
	for f in fingers:
		var seen := {}
		for t in all_tris:
			if membership[t[0]].has(f.name) or membership[t[1]].has(f.name) or membership[t[2]].has(f.name):
				f.tris.append(t)
				for id in t:
					seen[id] = true
		f.indices = PackedInt32Array(seen.keys())

	# everything below is in the grip socket's frame, which is where a held thing is attached
	to_socket = hand.skeleton.get_bone_global_pose(hand.grip_bone).affine_inverse()
	points.resize(hand.verts.size())
	for f in fingers:
		f.path = [f.amounts.duplicate()]
		apply_amounts(f, f.amounts)
	skin_all()

	# The palm's normal as authored (down, in the hand rig), seen from the socket; the plate runs out of the palm along it.
	var normal := (hand.skeleton.get_bone_global_pose(hand.grip_bone).basis.inverse() * Vector3(0, -1, 0)).normalized()
	var out := Vector3(normal.x, 0.0, normal.z).normalized()
	var across := Vector3.UP.cross(out)
	contact = make_plate(out, across)
	var bar_offset := Vector3.ZERO

	# The socket can put the plate inside the palm or knuckles: slide it out along the palm's normal until it clears the open skin.
	var shift := 0.0
	while open_intersects() and shift < MAX_PALM_SHIFT:
		var step := minf(0.0015, MAX_PALM_SHIFT - shift)
		var offset := normal * step
		bar_offset += offset
		contact.translate(offset)
		shift += step
	if open_intersects():
		push_error("the open %s hand does not clear the plate" % handedness)
		return {}

	for f in fingers:
		var all_joints := []
		for i in f.joints.size():
			all_joints.append(i)
		advance(f, all_joints)
		# Once a proximal segment meets the plate, let distal joints carry on wrapping: locking the whole finger at its first contact
		# leaves the tips open.
		for i in range(f.joints.size() - 1, -1, -1):
			advance(f, [i])

	var result := {"bar_offset": [bar_offset.x, bar_offset.y, bar_offset.z], "plate_out": [out.x, out.y, out.z], "palm_shift": shift, "fingers": {}}
	var report := ""
	for f in fingers:
		result.fingers[f.name] = f.path
		apply_amounts(f, f.amounts)
		var clear := not collides(f)
		report += " %s%s(%s)" % [f.name, "" if clear else "!", ",".join(f.amounts.map(func(a): return "%.2f" % a))]
	print("%s hand: plate shifted %.1f mm out of the palm;%s" % [handedness, shift * 1000.0, report])
	holder.queue_free()
	return result


# The plate as a box: along `out` from the edge to `width`, ±length/2 along the edge, ±thickness/2 across. (An edge is a very thin
# handle: the fingers close onto one face, the thumb onto the other.)
func make_plate(out: Vector3, across: Vector3) -> Contact:
	var c := Contact.new()
	var half_len := BAR_LENGTH / 2.0
	var half_t := PLATE_THICKNESS / 2.0
	var faces := [[out, PLATE_WIDTH], [-out, 0.0], [Vector3.UP, half_len], [Vector3.DOWN, half_len], [across, half_t], [-across, half_t]]
	for face in faces:
		c.normals.append(face[0])
		c.constants.append(face[1])
	for x in [0.0, PLATE_WIDTH]:
		for y in [-half_len, half_len]:
			for z in [-half_t, half_t]:
				var p: Vector3 = out * x + Vector3.UP * y + across * z
				c.bounds_min = c.bounds_min.min(p)
				c.bounds_max = c.bounds_max.max(p)
	return c
