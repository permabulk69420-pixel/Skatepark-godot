# The skateboard as a loose object: what it does once nobody is standing on it or holding it. It falls, bounces a little, tumbles when
# it lands badly, rolls on its wheels if it lands upright on a slope, slides when it lands on its deck, and comes to rest.
#
# It is a small rigid body of its own (no Godot physics bodies): the board's contact points (the four wheels, the corners and the two
# tips of the deck) are tested against the same ground the skating uses, and a wall check stops it passing through walls. The
# board's own frame is the sim's: origin where the wheels meet the ground, nose toward -z, up +y.
class_name BoardProp
extends RefCounted

const BOARD = Config.Board

const GRAVITY := 9.81
const MASS := 2.6
const MAX_STEP := 1.0 / 180.0          # seconds: a frame is split into steps no longer than this
const RESTITUTION := 0.28              # how much of an impact speed comes back
const BOUNCE_MIN := 0.8                # m/s: softer impacts than this don't bounce at all
const WHEEL_ROLL := 0.03               # friction along the way a wheel rolls (very little)
const WHEEL_SIDE := 0.9                # and across it (a wheel doesn't slide sideways)
const DECK_FRICTION := 0.5             # the deck and its tips on the ground
const LINEAR_DAMP := 0.02              # 1/s
const ANGULAR_DAMP := 0.5              # 1/s
const SLEEP_SPEED := 0.06              # m/s and rad/s under which it counts as still...
const SLEEP_SPIN := 0.2
const SLEEP_TIME := 0.4                # ...for this long (with at least three points on the ground), and it stops being simulated
const CONTACT_SKIN := 0.004            # metres: a point this close to the ground counts as touching it
const LOST_BELOW := -300.0             # it fell out of the world
const COM_LOCAL := Vector3(0.0, 0.075, 0.0)   # centre of mass in the board's frame

# Contact points in the board's frame: wheels (kind 0, they roll) and the deck (kind 1, it slides).
const POINTS := [
	[Vector3(0.082, 0.0, 0.239), 0], [Vector3(-0.082, 0.0, 0.239), 0], [Vector3(0.082, 0.0, -0.239), 0], [Vector3(-0.082, 0.0, -0.239), 0],
	[Vector3(0.104, 0.145, 0.30), 1], [Vector3(-0.104, 0.145, 0.30), 1], [Vector3(0.104, 0.145, -0.30), 1], [Vector3(-0.104, 0.145, -0.30), 1],
	[Vector3(0.0, 0.15, 0.405), 1], [Vector3(0.0, 0.15, -0.405), 1],
	[Vector3(0.108, 0.02, 0.239), 1], [Vector3(-0.108, 0.02, 0.239), 1], [Vector3(0.108, 0.02, -0.239), 1], [Vector3(-0.108, 0.02, -0.239), 1],
]
# The tips are also swept against walls.
const NOSE := Vector3(0.0, 0.15, -0.405)
const TAIL := Vector3(0.0, 0.15, 0.405)

var world: SkateWorld
var com := Vector3.ZERO                # centre of mass, in the world
var quat := Quaternion.IDENTITY
var vel := Vector3.ZERO
var spin := Vector3.ZERO               # angular velocity, in the world (axis × radians per second)
var asleep := false
var touching := 0                      # how many contact points were on the ground in the last step
var _still := 0.0
var _inv_body := Vector3.ZERO          # inverse of the principal moments of inertia
var _hit := SkateWorld.Hit.new()
var _wall := SkateWorld.Hit.new()


func _init(p_world: SkateWorld) -> void:
	world = p_world
	var w := 0.21
	var h := 0.16
	var l := BOARD.length
	_inv_body = Vector3(12.0 / (MASS * (h * h + l * l)), 12.0 / (MASS * (w * w + l * l)), 12.0 / (MASS * (w * w + h * h)))


# Puts it down at `origin` (where the wheels would meet the ground) turned by q, moving and spinning as given, awake.
func place(origin: Vector3, q: Quaternion, v := Vector3.ZERO, w := Vector3.ZERO) -> void:
	quat = q.normalized()
	com = origin + quat * COM_LOCAL
	vel = v
	spin = w
	wake()


func origin() -> Vector3:
	return com - quat * COM_LOCAL


func transform() -> Transform3D:
	return Transform3D(Basis(quat), origin())


func speed() -> float:
	return vel.length()


# Wheels down (not on its side or upside down).
func upright() -> bool:
	return (quat * Vector3.UP).y > 0.85


func lost() -> bool:
	return com.y < LOST_BELOW


func wake() -> void:
	asleep = false
	_still = 0.0


func step(dt: float) -> void:
	if asleep or not (dt > 0.0):
		return
	var n := maxi(1, ceili(dt / MAX_STEP))
	var h := dt / n
	var com_was := com
	var nose_was := com + quat * (NOSE - COM_LOCAL)
	var tail_was := com + quat * (TAIL - COM_LOCAL)
	for i in n:
		_substep(h)
	_walls(com_was, nose_was, tail_was)
	if touching >= 3 and vel.length() < SLEEP_SPEED and spin.length() < SLEEP_SPIN:
		_still += dt
		if _still >= SLEEP_TIME:
			asleep = true
			vel = Vector3.ZERO
			spin = Vector3.ZERO
	else:
		_still = 0.0


func _substep(h: float) -> void:
	vel.y -= GRAVITY * h
	vel *= maxf(0.0, 1.0 - LINEAR_DAMP * h)
	spin *= maxf(0.0, 1.0 - ANGULAR_DAMP * h)
	com += vel * h
	var w := spin.length()
	if w > 1e-6:
		quat = (Quaternion(spin / w, w * h) * quat).normalized()
	touching = 0
	for pass_ in 2:
		for entry: Array in POINTS:
			_contact(entry[0], entry[1] == 0, pass_ == 0)


# The inverse inertia in the world: R · diag(1/I) · Rᵀ.
func _inv_inertia() -> Basis:
	var r := Basis(quat)
	return r * Basis.from_scale(_inv_body) * r.transposed()


func _contact(local: Vector3, wheel: bool, count: bool) -> void:
	var offset := quat * (local - COM_LOCAL)
	var p := com + offset
	var g := world.ground(p.x, p.z, p.y + 0.25, _hit, 2.0)
	if g == null:
		return
	var depth := g.y - p.y
	if depth <= -CONTACT_SKIN:
		return
	if count:
		touching += 1
	var normal := g.normal
	var inv := _inv_inertia()
	var v_point := vel + spin.cross(offset)
	var vn := v_point.dot(normal)
	var push := 0.0
	if vn < 0.0:
		var e := RESTITUTION if vn < -BOUNCE_MIN else 0.0
		push = -(1.0 + e) * vn / _push_gain(offset, normal, inv)
		vel += normal * push / MASS
		spin += inv * offset.cross(normal * push)
	# friction: a wheel rolls the way the board points and grips across it; the deck grips the same every way
	var forward := quat * Vector3(0, 0, -1)
	forward = (forward - normal * forward.dot(normal)).normalized() if absf(forward.dot(normal)) < 0.99 else Vector3.ZERO
	var along := forward if wheel else Vector3.ZERO
	var dirs: Array = []
	if wheel and along != Vector3.ZERO:
		dirs = [[along, WHEEL_ROLL], [normal.cross(along), WHEEL_SIDE]]
	else:
		var a := normal.cross(Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD).normalized()
		dirs = [[a, DECK_FRICTION], [normal.cross(a), DECK_FRICTION]]
	var limit_base := maxf(push, 0.0) + MASS * GRAVITY * 0.0005   # (a point at rest still has a little weight to grip with)
	for d: Array in dirs:
		var dir: Vector3 = d[0]
		var vt := (vel + spin.cross(offset)).dot(dir)
		var jt := -vt / _push_gain(offset, dir, inv)
		var limit: float = d[1] * limit_base
		jt = clampf(jt, -limit, limit)
		vel += dir * jt / MASS
		spin += inv * offset.cross(dir * jt)
	# and out of the ground
	if depth > 0.002:
		com += normal * minf(depth - 0.002, 0.03) * 0.4


# How much a unit push along `dir` at `offset` from the centre changes the speed of that point (the inverse of its effective mass).
func _push_gain(offset: Vector3, dir: Vector3, inv: Basis) -> float:
	return maxf(1.0 / MASS + dir.dot((inv * offset.cross(dir)).cross(offset)), 1e-6)


# Walls: the centre and the two tips are swept from where they were; whatever they hit stops them there.
func _walls(com_was: Vector3, nose_was: Vector3, tail_was: Vector3) -> void:
	var rays := [
		[com_was, com],
		[nose_was, com + quat * (NOSE - COM_LOCAL)],
		[tail_was, com + quat * (TAIL - COM_LOCAL)],
	]
	for ray: Array in rays:
		var from: Vector3 = ray[0]
		var to: Vector3 = ray[1]
		var d := to - from
		var length := d.length()
		if length < 1e-4:
			continue
		var dir := d / length
		var hit := world.cast(from, dir, length + 0.02, _wall)
		if hit == null or absf(hit.normal.y) > 0.7 or hit.normal.dot(dir) > 0.0:
			continue
		var into := length - hit.dist + 0.01
		com += hit.normal * maxf(into * absf(hit.normal.dot(dir)), 0.0)
		var along := vel.dot(hit.normal)
		if along < 0.0:
			vel -= hit.normal * along * (1.0 + 0.2)
		wake()
