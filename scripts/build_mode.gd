# Build mode, in the house: point at a piece (the half pipe, the couch, the rug, or anything you have added), pick it up, carry it across
# the floor, turn it and put it down. New pieces come from the menu and arrive in your hand; one you added can be thrown away while you
# hold it. Nothing is final until you are done: then the layout is saved and the house loaded again, so every piece's collision and grind
# lines are read from where it now stands. (Until then a piece you have picked up has no collision anywhere.)
class_name BuildMode
extends RefCounted

const GRID := 0.25                 # metres: a piece is put down on this grid
const TURN_STEP := PI / 12.0       # each flick of the stick (or press of a key) turns a held piece 15°
const TURN_FLICK := 0.6            # how far over the stick goes to count as a flick (and it must come back past 0.3 for the next)
const REACH := 40.0                # metres the pointer reaches
const FLOOR_NORMAL := 0.7          # a surface this flat or flatter can have a piece stood on it
const HOVER_SLACK := 0.05          # a piece's box counts as pointed at up to this far beyond what the ray hits (the rug lies on the floor)
const OUTLINE_GROW := 0.03
const ACCENT := Color("5fd0c0")
const HELD := Color("f0c060")

static var come_back := {}         # where to stand once the house has been loaded again: {"pos", "yaw", "building"} (empty: at the door)

var active := false
var root: Node3D                   # the house
var world: SkateWorld              # build mode's own queries: they do not see the old collision of a piece that has been picked up
var bodies := {}                   # collision body name -> StaticBody3D
var owners := {}                   # collision body -> the piece it belongs to
var excluded: Array[RID] = []
var pieces: Array[Node3D] = []
var boxes := {}                    # piece -> its bounds in its own frame
var hovered: Node3D
var held: Node3D
var hold_offset := Vector3.ZERO    # from the floor point being pointed at to the held piece's origin (level)
var hold_lift := 0.0               # the held piece's origin above the floor it stands on
var hold_basis := Basis.IDENTITY   # its turn when it was picked up
var hold_yaw := 0.0                # and the turns made since
var aim := Vector3.INF             # the floor point being pointed at (INF: none)
var grab_was := false
var remove_was := false
var turn_armed := true
var vr: bool
var outline: MeshInstance3D
var outline_material: StandardMaterial3D
var laser: MeshInstance3D          # (headset only)
var dot: MeshInstance3D
var hit := SkateWorld.Hit.new()


func _init(level: LevelLoader, space: PhysicsDirectSpaceState3D, parent: Node3D, p_vr: bool) -> void:
	root = level.root
	vr = p_vr
	world = SkateWorld.new(space)
	for body in level.collision_bodies:
		bodies[String(body.name)] = body
	pieces = BuildPieces.find_all(root)
	for piece in pieces:
		boxes[piece] = BuildPieces.bounds(piece)
		for collider: String in BuildPieces.info(piece).get("colliders", []):
			if bodies.has(collider):
				owners[bodies[collider]] = piece
	_build_visuals(parent)


# Where to stand in the house just loaded (and whether to carry on building), once.
static func take_come_back() -> Dictionary:
	var spot := come_back
	come_back = {}
	return spot


func start() -> void:
	active = true
	grab_was = true     # (a trigger still down from choosing "Build" in the menu is not a grab)
	remove_was = true


# Every frame while building: `origin` / `direction` the pointer, `grab_down` the trigger (E), `turn_axis` the stick across (the arrow
# keys), `remove_down` B (X). Returns what happened: "", "picked", "placed", "turned", "removed" or "kept" (a house piece cannot be removed).
func update(origin: Vector3, direction: Vector3, grab_down: bool, turn_axis: float, remove_down: bool) -> String:
	direction = direction.normalized()
	var end := _cast(origin, direction)
	var happened := ""
	if held == null:
		hovered = _pointed_at(origin, direction)
		if grab_down and not grab_was and hovered != null:
			pick_up(hovered)
			happened = "picked"
	elif grab_down and not grab_was:
		put_down()
		happened = "placed"
	elif remove_down and not remove_was:
		happened = "removed" if remove_held() else "kept"
	else:
		if _turn(turn_axis):
			happened = "turned"
		_carry()
	grab_was = grab_down
	remove_was = remove_down
	_show(origin, direction, end)
	return happened


# Casts the pointer into the house. Sets `aim` (a floor it lands on, or INF) and returns where the ray ends (INF: on nothing).
func _cast(origin: Vector3, direction: Vector3) -> Vector3:
	aim = Vector3.INF
	if world.cast(origin, direction, REACH, hit) == null:
		return Vector3.INF
	var end := origin + direction * hit.dist
	if hit.normal.y >= FLOOR_NORMAL:
		aim = end
	return end


# The piece the pointer is on: the one whose collision it hits, or whose box it meets first (no further than what it hits).
func _pointed_at(origin: Vector3, direction: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := REACH
	if world.cast(origin, direction, REACH, hit) != null:
		best_d = hit.dist + HOVER_SLACK
		if owners.has(hit.collider):
			best = owners[hit.collider]
			best_d = hit.dist
	for piece in pieces:
		var inverse := piece.global_transform.affine_inverse()
		var local_origin := inverse * origin
		var box: AABB = boxes[piece]
		if box.has_point(local_origin):
			continue   # (standing inside a piece's box, the box says nothing; its collision does)
		var at = box.intersects_ray(local_origin, inverse.basis * direction)
		if at == null:
			continue
		var d := origin.distance_to(piece.global_transform * (at as Vector3))
		if d < best_d:
			best_d = d
			best = piece
	return best


func pick_up(piece: Node3D) -> void:
	held = piece
	hovered = piece
	for collider: String in BuildPieces.info(piece).get("colliders", []):
		var body: StaticBody3D = bodies.get(collider)
		if body == null or body.get_rid() in excluded:
			continue
		for shape in body.get_children():
			if shape is CollisionShape3D:
				(shape as CollisionShape3D).disabled = true   # (walking, and the board, go through where it was)
		excluded.append(body.get_rid())
	world.query.exclude = excluded
	var at := piece.global_position
	var floor_y: float = at.y + (boxes[piece] as AABB).position.y
	if world.ground(at.x, at.z, at.y + 0.5, hit, 3.0) != null:
		floor_y = hit.y
	hold_lift = at.y - floor_y
	hold_basis = piece.global_basis
	hold_yaw = 0.0
	hold_offset = Vector3.ZERO if aim == Vector3.INF else Vector3(at.x - aim.x, 0.0, at.z - aim.z)


func put_down() -> void:
	held = null


# Throws the held piece away, if it is one that was added (the house's own can only be moved). True if it went.
func remove_held() -> bool:
	if held == null or BuildPieces.info(held).kind == "":
		return false
	pieces.erase(held)
	boxes.erase(held)
	held.queue_free()
	held = null
	hovered = null
	return true


# A new piece of `kind`, in your hand: standing at `near`, turned to `facing` (a sim heading: its front, +Z, faces back towards you).
func add(kind: String, near: Vector3, facing: float) -> Node3D:
	var piece := BuildPieces.make(kind, _new_id(kind))
	root.add_child(piece)
	piece.global_transform = Transform3D(Basis(Vector3.UP, facing), near)
	pieces.append(piece)
	boxes[piece] = BuildPieces.bounds(piece)
	held = piece
	hovered = piece
	hold_basis = piece.global_basis
	hold_yaw = 0.0
	hold_offset = Vector3.ZERO
	hold_lift = -(boxes[piece] as AABB).position.y
	return piece


func _new_id(kind: String) -> String:
	var taken := {}
	for piece in pieces:
		taken[BuildPieces.info(piece).id] = true
	var n := 1
	while taken.has("%s_%d" % [kind, n]):
		n += 1
	return "%s_%d" % [kind, n]


# A flick of the stick turns the held piece a step about the point being pointed at.
func _turn(axis: float) -> bool:
	if absf(axis) < 0.3:
		turn_armed = true
		return false
	if not turn_armed or absf(axis) < TURN_FLICK:
		return false
	turn_armed = false
	var step := -signf(axis) * TURN_STEP   # (stick right: clockwise, seen from above)
	hold_yaw += step
	hold_offset = Basis(Vector3.UP, step) * hold_offset
	return true


# The held piece follows the floor point being pointed at, on the grid, standing on whatever floor is under it.
func _carry() -> void:
	if aim == Vector3.INF:
		_place_held(held.global_position)   # (pointing at a wall or the sky: it stays, but still turns)
		return
	var at := aim + hold_offset
	at.x = snappedf(at.x, GRID)
	at.z = snappedf(at.z, GRID)
	var floor_y := aim.y
	if world.ground(at.x, at.z, aim.y + 0.5, hit, 1.5) != null:
		floor_y = hit.y
	_place_held(Vector3(at.x, floor_y + hold_lift, at.z))


func _place_held(at: Vector3) -> void:
	held.global_transform = Transform3D(Basis(Vector3.UP, hold_yaw) * hold_basis, at)


# What to save: where each piece stands in the house.
func layout() -> Array:
	var entries: Array = []
	var inverse := root.global_transform.affine_inverse()
	for piece in pieces:
		var data := BuildPieces.info(piece)
		entries.append({"id": data.id, "kind": data.kind, "transform": inverse * piece.global_transform})
	return entries


func piece_name(piece: Node3D) -> String:
	return BuildPieces.info(piece).get("name", "")


func _build_visuals(parent: Node3D) -> void:
	outline_material = StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_material.albedo_color = Color(ACCENT, 0.2)
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	outline = MeshInstance3D.new()
	outline.name = "BuildOutline"
	outline.mesh = cube
	outline.material_override = outline_material
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline.visible = false
	parent.add_child(outline)

	var beam := StandardMaterial3D.new()
	beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.albedo_color = ACCENT
	if vr:
		var line := CylinderMesh.new()
		line.top_radius = 0.0015
		line.bottom_radius = 0.0015
		line.height = 1.0
		line.radial_segments = 6
		laser = MeshInstance3D.new()
		laser.name = "BuildLaser"
		laser.mesh = line
		laser.material_override = beam
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		laser.visible = false
		parent.add_child(laser)
	var ball := SphereMesh.new()
	ball.radius = 0.03
	ball.height = 0.06
	ball.radial_segments = 8
	ball.rings = 4
	dot = MeshInstance3D.new()
	dot.name = "BuildDot"
	dot.mesh = ball
	dot.material_override = beam
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.visible = false
	parent.add_child(dot)


# The pointer and the box are hidden while the menu is up (and the trigger that presses its buttons is not a grab when it closes).
func hide() -> void:
	grab_was = true
	remove_was = true
	outline.visible = false
	dot.visible = false
	if laser != null:
		laser.visible = false


# The box round the piece pointed at (or held), the laser, and the dot where it lands.
func _show(origin: Vector3, direction: Vector3, end: Vector3) -> void:
	var target := held if held != null else hovered
	outline.visible = target != null
	if target != null:
		var box := (boxes[target] as AABB).grow(OUTLINE_GROW)
		outline.global_transform = target.global_transform * Transform3D(Basis.from_scale(box.size), box.get_center())
		outline_material.albedo_color = Color(HELD if held != null else ACCENT, 0.2)
	dot.visible = end != Vector3.INF
	if dot.visible:
		dot.global_position = end
	if laser != null:
		var to := end if end != Vector3.INF else origin + direction * 3.0
		var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK
		laser.visible = true
		laser.global_transform = Transform3D(Basis.looking_at(direction, up) * Basis(Vector3.RIGHT, PI / 2.0), origin.lerp(to, 0.5))
		laser.scale = Vector3(1.0, origin.distance_to(to), 1.0)
