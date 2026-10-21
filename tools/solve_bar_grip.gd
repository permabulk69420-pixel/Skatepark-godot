# Works out how each hand closes round a dirt bike's handlebar grip, once, ahead of time, and writes assets/hands/bar_grip_solution.json.
#   godot --headless --path . -s res://tools/solve_bar_grip.gd
#
# The same as tools/solve_grip.gd (the board's edge), with a round grip in place of the plate: a tube along the grip socket's Y, slid out
# of the palm until it clears the open hand's skin, then each finger closed until its skin touches the tube. Re-run it if the hand
# models or the grip size change.
extends SceneTree

const CONTACT_MARGIN := 0.001   # one millimetre of clearance for the low-poly skin
const CLOSE_STEPS := 20
const REFINE_STEPS := 5
const MAX_PALM_SHIFT := 0.06
const GRIP_RADIUS := 0.0185      # the bike's rubber grips (assets/bike/dirt_bike.glb): 3.7 cm across
const BAR_LENGTH := 0.12        # the length of grip the hand can touch: about a hand's width
const OUT := "res://assets/hands/bar_grip_solution.json"


# The grip: a tube along `axis` through `centre`. A triangle is tested at its corners, edges and middle (fine enough for the hand's skin
# against a tube this size).
class Contact:
	var centre := Vector3.ZERO
	var axis := Vector3.UP
	var radius := 0.0
	var half_length := 0.0

	func contains(p: Vector3, margin: float) -> bool:
		var d := p - centre
		var along := d.dot(axis)
		if absf(along) > half_length + margin:
			return false
		return (d - axis * along).length() < radius + margin

	func intersects_triangle(a: Vector3, b: Vector3, c: Vector3, margin: float) -> bool:
		for p in [a, b, c, (a + b) * 0.5, (b + c) * 0.5, (c + a) * 0.5, (a + b + c) / 3.0,
				a.lerp(b, 0.25), a.lerp(b, 0.75), b.lerp(c, 0.25), b.lerp(c, 0.75), c.lerp(a, 0.25), c.lerp(a, 0.75)]:
			if contains(p, margin):
				return true
		return false

	func translate(offset: Vector3) -> void:
		centre += offset


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
	var result := {"grip": {"radius": GRIP_RADIUS, "length": BAR_LENGTH}}
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


# Close a finger's joints (jointIndices) towards a fist until its skin meets the grip. A binary search of the endpoints alone can
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

	# The palm's normal as authored (down, in the hand rig), seen from the socket; the grip is slid out of the palm along it.
	var normal := (hand.skeleton.get_bone_global_pose(hand.grip_bone).basis.inverse() * Vector3(0, -1, 0)).normalized()
	normal = Vector3(normal.x, 0.0, normal.z).normalized()   # (square to the grip's axis)
	var out := normal
	contact = Contact.new()
	contact.radius = GRIP_RADIUS
	contact.half_length = BAR_LENGTH / 2.0
	var bar_offset := Vector3.ZERO

	# The socket can put the grip inside the palm or knuckles: slide it out along the palm's normal until it clears the open skin.
	var shift := 0.0
	while open_intersects() and shift < MAX_PALM_SHIFT:
		var step := minf(0.0015, MAX_PALM_SHIFT - shift)
		var offset := normal * step
		bar_offset += offset
		contact.translate(offset)
		shift += step
	if open_intersects():
		push_error("the open %s hand does not clear the grip" % handedness)
		return {}

	for f in fingers:
		var all_joints := []
		for i in f.joints.size():
			all_joints.append(i)
		advance(f, all_joints)
		# Once a proximal segment meets the grip, let distal joints carry on wrapping: locking the whole finger at its first contact
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
	print("%s hand: grip %.1f mm out of the palm;%s" % [handedness, shift * 1000.0, report])
	holder.queue_free()
	return result
