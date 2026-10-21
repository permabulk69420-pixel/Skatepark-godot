# The dirt bike (assets/bike/dirt_bike.glb): its look (wheels that turn, a front end that steers, a lean into turns) and how it rides.
# It is a simple bike, not a full one. It steers two ways, either or both at once: by its bars (the turn follows the speed and the angle of
# the front wheel, like a bicycle's, and the bike stays upright), and by the rider leaning (the bike leans as far as the rider does, and a
# leaning bike on the move turns the way it leans, tighter the further it leans and the slower it goes). It stands on
# whatever is under its two tyres (so it pitches up a ramp and down off it), it flies off what drops away faster than gravity would let it
# follow, and stops at walls. A five-speed box changes gear by itself; the engine's revs follow the back wheel (or the throttle, with the
# clutch slipping at a standstill or in the air).
#
# The model is built facing +Z; here it is turned round to face -Z (the game's forward). (It has its exhaust and front brake lever on the
# rider's left, and its grip empties are named the other way round from where they sit: the grips are told apart by which side they are
# on. Mirroring it would put the exhaust right but write its numbers backwards.)
class_name DirtBike
extends RefCounted

const MODEL := "res://assets/bike/dirt_bike.glb"
const WHEELBASE := 1.49
const FRONT_RADIUS := 0.355
const REAR_RADIUS := 0.338
const PEG_HEIGHT := 0.413          # the footpegs above the ground
# Each rubber grip's own axis (it is swept back off the straight line between them), in the frame of the model's grip empties: measured
# from the model, through the middle of the grip, where the empty is.
const GRIP_AXES := {"Right_Grip": Vector3(0.990, 0.039, -0.132), "Left_Grip": Vector3(0.989, -0.045, 0.142)}
const RIDER := Vector3(0.0, 0.0, 0.12)   # where the rider's head is over, in the bike's frame (just behind the middle)
const STEER_LIMIT := deg_to_rad(35.0)    # (the model's own suggestion) at a walk,
const STEER_LIMIT_FAST := deg_to_rad(5.0)   # narrowing to this at speed
const STEER_NARROWS := 14.0        # (m/s by which it has narrowed all the way)
const STEER_RATE := 3.0            # rad/s the bars turn at with a key or stick at a walk (less at speed),
const HAND_STEER_RATE := 6.0       # and following the rider's hands
const HAND_DEAD := deg_to_rad(1.5) # the rider's hands: this much either side of straight is straight,
const HAND_CURVE := 1.5            # and the turn grows as this power of how far they turn (small moves, small turns)
const GEAR_TOPS := [9.0, 14.0, 19.0, 24.0, 29.0]   # m/s at the red line in each gear
const GEAR_PULL := [6.5, 5.2, 4.1, 3.2, 2.5]        # m/s² of push at full throttle in each
const IDLE := 1600.0
const RED_LINE := 11500.0
const SHIFT_UP := 10200.0
const SHIFT_DOWN := 4800.0
const BRAKE := 9.0                 # m/s² with the brake fully on
const ROLLING := 0.35              # m/s² rolling along with the throttle shut
const DRAG := 0.0028               # air, per (m/s)²
const GRAVITY := 9.81
const PADDLE_SPEED := 1.2          # m/s you can walk it along, sitting on it, when it is all but stopped
const MAX_CLIMB := deg_to_rad(62.0)   # steeper than this under the front wheel is a wall
const WALL_PROBES := [0.3, 0.75]   # heights above the ground the bike feels walls at
const FRONT_REACH := 0.95          # from the middle to the front of the front tyre
const LIFT_PROBE := 0.7            # the ground is looked for from this far above the bike
const AIR_PITCH := 0.7             # rad/s the throttle (nose up) or the brake (nose down) turns it in the air
const LEAN_CLEARANCE := deg_to_rad(2.0)   # the bike leans as far as the rider does, up to this short of touching the ground,
const LEAN_PIVOT := 0.075          # about the line its tyres roll on (the middle of their round tread), as a real bike: you lean with it
const LEAN_TURNS_FROM := 1.5       # m/s: slower than this leaning does not turn it; by this speed it fully does
const LEAN_TURNS_FULL := 5.0
const LEAN_TIGHTEST := 3.0         # metres: the tightest turn leaning makes

class Controls:
	var throttle := 0.0            # 0..1
	var brake := 0.0               # 0..1
	var steer := 0.0               # -1..1 (a key or stick: left is +), unless `steer_to` is set
	var steer_to := NAN            # an angle for the bars (radians, left +): the rider's hands
	var paddle := 0.0              # -1..1: walking it forwards or back while (nearly) stopped
	var lean := 0.0                # the lean the rider is asking for (radians, left +); it goes as far as lean_limit()

var node: Node3D                   # the piece: everything moves with it
var model: Node3D
var pivot: Node3D
var pivot_rest: Transform3D
var front_wheel: Node3D
var front_rest: Transform3D
var rear_wheel: Node3D
var rear_rest: Transform3D
var grip_nodes := {}               # "left" / "right" -> the model's grip empties
var grip_markers := {}             # "left" / "right" -> a plain marker on each grip for a hand to hold (see update_grips)

var world: SkateWorld
var bounds: Dictionary
var pos := Vector3.ZERO            # on the ground, halfway between the tyres' contact points
var yaw := 0.0                     # a sim heading: forward is (-sin, 0, -cos)
var speed := 0.0                   # m/s along the way it points (negative: rolling back)
var vy := 0.0
var air := false
var pitch := 0.0                   # nose up +
var lean := 0.0                    # to the left +: only ever the rider's doing
var steer := 0.0                   # the bars, left +
var throttle := 0.0
var rpm := IDLE
var gear := 0
var spin_front := 0.0
var spin_rear := 0.0
var last_impact := 0.0
var hit := SkateWorld.Hit.new()


# A new bike piece (BuildPieces), standing at its own origin facing -Z.
static func make_model() -> Node3D:
	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 0.01))
	return model


# Rides the bike piece `p_node` (in the tree). `p_bounds`: the level's play area.
func _init(p_node: Node3D, p_world: SkateWorld, p_bounds: Dictionary = {}) -> void:
	node = p_node
	world = p_world
	bounds = p_bounds
	model = node.find_child("Model", false, false)
	pivot = model.find_child("Steering_Pivot", true, false)
	pivot_rest = pivot.transform
	front_wheel = model.find_child("Front_Wheel", true, false)
	front_rest = front_wheel.transform
	rear_wheel = model.find_child("Rear_Wheel", true, false)
	rear_rest = rear_wheel.transform
	var a: Node3D = model.find_child("Left_Grip", true, false)
	var b: Node3D = model.find_child("Right_Grip", true, false)
	var a_side: float = (model.transform * (a.get_parent() as Node3D).transform * a.transform).origin.x   # (the bike's frame: its right is +X)
	grip_nodes = {"left": a, "right": b} if a_side < 0.0 else {"left": b, "right": a}
	for side in ["left", "right"]:
		var marker: Node3D = node.find_child("Hold_" + side, false, false)
		if marker == null:
			marker = Node3D.new()
			marker.name = "Hold_" + side
			node.add_child(marker)
		grip_markers[side] = marker
	pos = node.global_position
	yaw = BuildPieces.yaw_of(node.global_basis)   # (the piece stands turned by its heading)
	update_grips()


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


# The bike's frame turned only about the vertical.
func level_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


# The frame the rider rides in: the bike's own, every way it turns, pitches and leans (as the board carries the skater).
func ride_transform() -> Transform3D:
	var pivot_up := Transform3D(Basis.IDENTITY, Vector3(0.0, LEAN_PIVOT, 0.0))
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos) * pivot_up * Transform3D(Basis(Vector3.BACK, lean), Vector3.ZERO) \
		* pivot_up.affine_inverse()


# Where the rider's head goes over (on the ground).
func rider_point() -> Vector3:
	return level_transform() * RIDER


func steer_limit() -> float:
	return steer_limit_at(speed)


static func steer_limit_at(at_speed: float) -> float:
	return lerpf(STEER_LIMIT, STEER_LIMIT_FAST, clampf(absf(at_speed) / STEER_NARROWS, 0.0, 1.0))


# The front wheel's angle for the angle the rider's hands hold the bars at: nothing near straight, then growing gently, up to the full
# lock at any speed.
static func hand_steer(bar: float, at_speed: float) -> float:
	var x := clampf((absf(bar) - HAND_DEAD) / (STEER_LIMIT - HAND_DEAD), 0.0, 1.0)
	return signf(bar) * pow(x, HAND_CURVE) * STEER_LIMIT


# One step. Returns what happened: "" or "land" / "hit" (how hard: `last_impact`, m/s) / "shift".
func update(c: Controls, dt: float) -> String:
	var happened := ""
	throttle = move_toward(throttle, clampf(c.throttle, 0.0, 1.0), dt * 6.0)
	# the bars
	var limit := steer_limit()
	if is_nan(c.steer_to):
		var rate := STEER_RATE * lerpf(1.0, 0.35, clampf(absf(speed) / STEER_NARROWS, 0.0, 1.0))
		steer = move_toward(steer, clampf(c.steer, -1.0, 1.0) * limit, dt * rate)
	else:
		steer = move_toward(steer, clampf(c.steer_to, -STEER_LIMIT, STEER_LIMIT), dt * HAND_STEER_RATE)   # (the hands: the full lock at any speed)
	# the engine and the box
	var wheel_rpm: float = IDLE + (RED_LINE - IDLE) * absf(speed) / GEAR_TOPS[gear]
	var want: float = wheel_rpm
	if air:
		want = IDLE + throttle * (RED_LINE - IDLE)
	elif gear == 0 and wheel_rpm < IDLE + throttle * 6000.0:
		want = IDLE + throttle * 6000.0   # (the clutch slipping)
	rpm = lerpf(rpm, clampf(want, IDLE * 0.9, RED_LINE), 1.0 - exp(-dt * 12.0))
	if not air:
		if wheel_rpm > SHIFT_UP and gear < GEAR_TOPS.size() - 1 and throttle > 0.2:
			gear += 1
			happened = "shift"
		elif wheel_rpm < SHIFT_DOWN and gear > 0:
			gear -= 1
	# speed along the ground
	if not air:
		var push: float = throttle * GEAR_PULL[gear] * (1.0 - clampf(wheel_rpm / RED_LINE, 0.0, 1.0) * 0.35)
		if speed < GEAR_TOPS[GEAR_TOPS.size() - 1] and speed >= -0.1:
			speed += push * dt
		var slow := (clampf(c.brake, 0.0, 1.0) * BRAKE + ROLLING * (1.0 - throttle)) * dt + DRAG * speed * speed * dt
		speed = move_toward(speed, 0.0, slow)
		speed -= GRAVITY * sin(pitch) * dt   # (uphill slows it, downhill runs it on; it rolls back off a slope)
		if absf(speed) < PADDLE_SPEED * 1.2 and absf(c.paddle) > 0.2 and throttle < 0.05:
			speed = move_toward(speed, c.paddle * PADDLE_SPEED, dt * 3.0)
		yaw = wrapf(yaw + (speed * tan(steer) / WHEELBASE + lean_turn_rate()) * dt, -PI, PI)
	# where it goes
	var along := forward() * signf(speed)
	var step := absf(speed) * cos(pitch) * dt if not air else absf(speed) * dt
	if step > 0.0 and _blocked(along, step):
		last_impact = absf(speed)
		speed = -speed * 0.15
		step = 0.0
		happened = "hit"
	var next := pos + along * step
	next = _clamp_to_bounds(next)
	var front := next + forward() * WHEELBASE * 0.5
	var rear := next - forward() * WHEELBASE * 0.5
	var from_y := pos.y + LIFT_PROBE
	var hf = _ground_y(front, from_y)
	var hr = _ground_y(rear, from_y)
	if not air:
		if hf == null and hr == null:
			_take_off()
		else:
			var yf: float = hf if hf != null else hr
			var yr: float = hr if hr != null else hf
			var ground_y := (yf + yr) / 2.0
			var ground_pitch := atan2(yf - yr, WHEELBASE)
			if ground_pitch > MAX_CLIMB and speed > 0.0:
				# (too steep to ride up: a wall)
				last_impact = absf(speed)
				speed = -speed * 0.15
				happened = "hit"
				next = pos
			else:
				var falling_to := pos.y + vy * dt - 0.5 * GRAVITY * dt * dt
				if ground_y < falling_to - 0.03:
					_take_off()   # (the ground falls away faster than it could follow: off a lip, or over a crest going up)
				else:
					vy = (ground_y - pos.y) / dt if dt > 0.0 else 0.0
					next.y = ground_y
					pitch = lerpf(pitch, ground_pitch, 1.0 - exp(-dt * 20.0))
	if air:
		vy -= GRAVITY * dt
		next.y = pos.y + vy * dt
		pitch = clampf(pitch + (throttle - clampf(c.brake, 0.0, 1.0)) * AIR_PITCH * dt, -0.6, 0.6)
		var ground_here = _ground_y(next, maxf(pos.y, next.y) + LIFT_PROBE)
		if ground_here != null and next.y <= ground_here and vy <= 0.0:
			last_impact = -vy
			next.y = ground_here
			vy = 0.0
			air = false
			speed *= 1.0 - clampf((last_impact - 4.0) * 0.04, 0.0, 0.4)   # (a heavy landing scrubs some speed)
			happened = "land"
	pos = next
	# how it looks
	lean = clampf(c.lean, -lean_limit(), lean_limit())   # (exactly with the rider, every frame)
	spin_front = wrapf(spin_front + speed / FRONT_RADIUS * dt, -PI, PI)   # (about the wheel's X: its top goes forward)
	spin_rear = wrapf(spin_rear + speed / REAR_RADIUS * dt, -PI, PI)
	apply()
	return happened


# How far it can lean before any of it (but its tyres, which roll over on to their sides) would touch the ground, less LEAN_CLEARANCE:
# worked out once from the model. For each point of it, out `a` to the side and `y` up, leaning by θ about the pivot line at height h
# puts it at h + (y − h)·cos θ − a·sin θ, which is 0 at θ = acos(−h / R) − φ (R, φ: the point's distance and direction from the pivot).
static var _lean_limit := -1.0
static func lean_limit() -> float:
	if _lean_limit >= 0.0:
		return _lean_limit
	var piece := BuildPieces.make("bike", "measure")
	var first := PI / 2.0
	var stack: Array = [[piece, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D and not String(node.name).ends_with("_Wheel"):
			for v in (node as MeshInstance3D).mesh.get_faces():
				var p := xf * v
				var a := absf(p.x)
				var up := p.y - LEAN_PIVOT
				var r := Vector2(a, up).length()
				if a < 0.01 or r < LEAN_PIVOT:
					continue
				first = minf(first, acos(-LEAN_PIVOT / r) - atan2(a, up))
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	piece.free()
	_lean_limit = maxf(first - LEAN_CLEARANCE, 0.0)
	return _lean_limit


# How fast leaning turns it (rad/s, left +): as a real bike balanced in a turn, g·tan(lean) / speed, coming in from LEAN_TURNS_FROM,
# and never tighter than LEAN_TIGHTEST.
func lean_turn_rate() -> float:
	var going := absf(speed)
	var share := clampf((going - LEAN_TURNS_FROM) / (LEAN_TURNS_FULL - LEAN_TURNS_FROM), 0.0, 1.0)
	var rate := GRAVITY * tan(lean) / maxf(going, LEAN_TURNS_FULL) * share * signf(speed)
	return clampf(rate, -going / LEAN_TIGHTEST, going / LEAN_TIGHTEST)


# Puts the bike where it is: its pose, the front end turned, the wheels round.
func apply() -> void:
	node.global_transform = ride_transform()
	pivot.transform = Transform3D(pivot_rest.basis * Basis(Vector3.UP, steer), pivot_rest.origin)
	front_wheel.transform = front_rest * Transform3D(Basis(Vector3.RIGHT, spin_front), Vector3.ZERO)
	rear_wheel.transform = rear_rest * Transform3D(Basis(Vector3.RIGHT, spin_rear), Vector3.ZERO)
	update_grips()


# The grip markers follow the grips: on the middle of each, its X along that grip's own axis, its Y as near upright as that allows.
func update_grips() -> void:
	for side in ["left", "right"]:
		var grip: Node3D = grip_nodes[side]
		var along: Vector3 = (grip.global_basis * GRIP_AXES.get(String(grip.name), Vector3.RIGHT)).normalized()
		var up := node.global_basis.y
		up = (up - along * up.dot(along)).normalized()
		(grip_markers[side] as Node3D).global_transform = Transform3D(Basis(along, up, along.cross(up)), grip.global_position)


# Into the air: from here on it carries on with the speed it had along the ground, split into across and up.
func _take_off() -> void:
	air = true
	speed *= cos(pitch)


func _ground_y(at: Vector3, from_y: float):
	var h := world.ground(at.x, at.z, from_y, hit, LIFT_PROBE + 6.0)
	return null if h == null else h.y


# Is there a wall within `step` (plus the bike's own length) the way it is going?
func _blocked(along: Vector3, step: float) -> bool:
	for h: float in WALL_PROBES:
		var from := pos + Vector3.UP * h
		if world.cast(from, along, step + FRONT_REACH, hit) != null and absf(hit.normal.y) < 0.6:
			return true
	return false


func _clamp_to_bounds(p: Vector3) -> Vector3:
	if bounds.is_empty():
		return p
	var cx: float = bounds.get("cx", 0.0)
	var cz: float = bounds.get("cz", 0.0)
	p.x = clampf(p.x, cx - bounds.x, cx + bounds.x)
	p.z = clampf(p.z, cz - bounds.z, cz + bounds.z)
	return p
