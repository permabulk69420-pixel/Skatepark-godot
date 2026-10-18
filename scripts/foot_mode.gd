# Walking around on foot (the house): the stick moves you, the right stick turns you smoothly, and the floor and walls are the same collision
# the skating uses. In the headset the play space moves under you and you still walk about in it for real; on a flat screen the mouse
# looks and W A S D walk.
class_name FootMode
extends RefCounted

const RADIUS := 0.28             # how close the body may get to a wall
const STEP := 0.35               # the biggest step up that is just walked
const MIN_FLOOR_NORMAL := 0.55   # steeper than this is a wall, not a floor
const WALK_SPEED := 2.0
const RISE_RATE := 3.0           # metres per second the feet follow a step up
const FALL_RATE := 6.0
const EYE := 1.65                # flat screen
const TURN_RATE := deg_to_rad(120.0)   # radians per second with the stick right over (a guess: change it to taste)
const WALL_PROBES := [0.4, 1.0, 1.55]   # heights above the feet the walls are felt at (just above the biggest step)
const SETTLE_FRAMES := 24

var rig: Node3D
var camera: Camera3D
var world: SkateWorld
var vr := false
var floor_y := 0.0
var look_yaw := 0.0
var look_pitch := 0.0
var placed := false
var _settle := 0
var _want_pos := Vector3.ZERO
var _want_yaw := 0.0
var _hit := SkateWorld.Hit.new()
var _ground := SkateWorld.Hit.new()


func _init(p_rig: Node3D, p_camera: Camera3D, p_world: SkateWorld, p_vr: bool) -> void:
	rig = p_rig
	camera = p_camera
	world = p_world
	vr = p_vr
	camera.rotation_order = EULER_ORDER_YXZ


# Put the player on the floor at `pos`, facing `yaw` (the sim's heading: 0 faces -Z). In the headset it waits until tracking has settled
# so that the head really ends up over `pos`.
func place(pos: Vector3, yaw: float) -> void:
	_want_pos = pos
	_want_yaw = yaw
	placed = false
	_settle = 0


func _apply_place() -> void:
	floor_y = _want_pos.y
	if vr:
		var head_local := camera.position
		var forward_local := -camera.transform.basis.z
		var head_yaw := atan2(-forward_local.x, -forward_local.z)
		var basis := Basis(Vector3.UP, _want_yaw - head_yaw)
		rig.global_transform = Transform3D(basis, Vector3(_want_pos.x, floor_y, _want_pos.z) - basis * Vector3(head_local.x, 0.0, head_local.z))
	else:
		rig.global_transform = Transform3D(Basis.IDENTITY, _want_pos)
		look_yaw = _want_yaw
		look_pitch = 0.0
	placed = true


# Where the feet are (the head, straight down, in the headset).
func body() -> Vector3:
	if vr:
		return Vector3(camera.global_position.x, floor_y, camera.global_position.z)
	return Vector3(rig.global_position.x, floor_y, rig.global_position.z)


# Which way the player faces, as a sim heading.
func facing() -> float:
	if not vr:
		return look_yaw
	var f := -camera.global_transform.basis.z
	return atan2(-f.x, -f.z)


# Flat-screen mouse look.
func turn_view(dx: float, dy: float) -> void:
	look_yaw -= dx * 0.003
	look_pitch = clampf(look_pitch - dy * 0.003, -1.45, 1.45)


# `move`: x sideways, y forward (−1..1). `turn`: the turn stick (headset). Returns true while the player is on something solid.
func update(dt: float, move: Vector2, turn: float) -> bool:
	if not placed:
		if vr:
			_settle += 1
			if _settle <= SETTLE_FRAMES or camera.position.y < 0.4:
				return false
		_apply_place()
	if not vr:
		camera.position = Vector3(0.0, EYE, 0.0)
		camera.rotation = Vector3(look_pitch, look_yaw, 0.0)

	# smooth turn: about the head, so you stay where you are
	if vr and absf(turn) > 0.15:
		var at := body()
		var spin := Basis(Vector3.UP, -turn * TURN_RATE * dt)
		var origin := rig.global_position
		rig.global_transform = Transform3D(spin * rig.global_transform.basis, at + spin * (origin - at))
		rig.global_position.y = origin.y

	var start := body()
	var delta := Vector3.ZERO
	if move.length() > 0.05:
		var yaw := facing()
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		var m := move.limit_length(1.0)
		delta = (forward * m.y + right * m.x) * WALK_SPEED * dt
	var moved := _try(start, delta)
	if moved == start and delta != Vector3.ZERO:       # slide along a wall: try each axis on its own
		moved = _try(start, Vector3(delta.x, 0.0, 0.0))
		if moved == start:
			moved = _try(start, Vector3(0.0, 0.0, delta.z))
	# anything the player does physically (leaning into a wall) is held back the same way
	var pushed := _resolve(moved)
	var floor_under := _floor(pushed)
	var grounded := floor_under != null
	if grounded:
		if floor_under.y > floor_y:
			floor_y = minf(floor_under.y, floor_y + RISE_RATE * dt)
		else:
			floor_y = maxf(floor_under.y, floor_y - FALL_RATE * dt)
	else:
		floor_y -= FALL_RATE * dt
	var shift := Vector3(pushed.x - start.x, 0.0, pushed.z - start.z)
	rig.global_position += shift
	rig.global_position.y = floor_y
	return grounded


# The position after trying to move `delta` from `from`: unchanged if the way is blocked.
func _try(from: Vector3, delta: Vector3) -> Vector3:
	if delta == Vector3.ZERO:
		return from
	var target := _resolve(from + delta)
	var ground := _floor(target)
	if ground == null:
		return from
	if ground.y - floor_y > STEP:
		return from
	return target


# The floor under a spot: null if there is none (a drop into nothing) or it is too steep to stand on.
func _floor(at: Vector3) -> SkateWorld.Hit:
	# looked for from a little above a step, so something taller than a step is seen as that and not walked through to the floor behind it
	var hit := world.ground(at.x, at.z, floor_y + STEP + 0.1, _ground, 4.0)
	if hit == null or hit.normal.y < MIN_FLOOR_NORMAL:
		return null
	return hit


# Pushes a spot out of any wall it is inside.
func _resolve(at: Vector3) -> Vector3:
	var p := at
	for pass_ in 2:
		for i in 8:
			var a := TAU * float(i) / 8.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			for h: float in WALL_PROBES:
				var hit := world.cast(Vector3(p.x, floor_y + h, p.z), dir, RADIUS, _hit)
				if hit != null and absf(hit.normal.y) < 0.7:
					var out := Vector3(hit.normal.x, 0.0, hit.normal.z)
					if out.length() > 0.001:
						p += out.normalized() * (RADIUS - hit.dist + 0.002)
	return p
