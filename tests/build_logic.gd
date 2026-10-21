# Build mode in the house: pointing at a piece, picking it up, carrying and turning it, putting it down, adding an arcade machine and a
# rail, removing what was added, and the layout surviving the house being loaded again (collision and grind lines where things now stand).
# Runs the real game scene on a flat screen and drives build mode directly.
#   godot --headless --path . -s res://tests/build_logic.gd
extends SceneTree

const LAYOUT := "user://build_test_layout.cfg"

var failures := 0
var main: Node
var hit := SkateWorld.Hit.new()


func _init() -> void:
	run.call_deferred()


func check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures += 1


func open_house() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1


func piece(id: String) -> Node3D:
	for p in main.build.pieces:
		if BuildPieces.info(p).id == id:
			return p
	return null


# Points straight down at (x, z) from above the floor.
func point(x: float, z: float, grab := false, turn := 0.0, remove := false) -> String:
	return main.build.update(Vector3(x, 2.5, z), Vector3.DOWN, grab, turn, remove)


# Picks up whatever is at `from`, carries it to `to` and puts it down.
func move(from: Vector2, to: Vector2) -> void:
	point(from.x, from.y)
	point(from.x, from.y, true)
	point(to.x, to.y, true)
	point(to.x, to.y)
	point(to.x, to.y, true)
	point(to.x, to.y)


func floor_at(x: float, z: float) -> float:
	var h = main.world.ground(x, z, 2.5, hit, 5.0)
	return NAN if h == null else h.y


func collider_at(x: float, z: float) -> String:
	var h = main.world.ground(x, z, 2.5, hit, 5.0)
	return "" if h == null or h.collider == null else String(h.collider.name)


func walk(move_by: Vector2, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		main.foot.update(0.05, move_by, 0.0)
		t += 0.05


func run() -> void:
	HubLayout.path = LAYOUT
	HubLayout.clear()
	await open_house()
	var build: BuildMode = main.build
	check(build != null, "the house has build mode")
	var ids: Array = []
	for p in build.pieces:
		ids.append(BuildPieces.info(p).id)
	ids.sort()
	check(ids == ["couch", "halfpipe", "rug"], "the half pipe, the couch and the rug can be moved (%s)" % [ids])
	var couch := piece("couch")
	var couch_from: Vector3 = couch.global_position
	check(collider_at(couch_from.x, couch_from.z) == "COL_Couch", "the couch has its own collision, cut out of the walls (%s)" % collider_at(couch_from.x, couch_from.z))
	check(couch.find_child("COL_Couch", false, false) == null and (couch.get_meta(BuildPieces.META).colliders as Array).size() == 1, "(its collision mesh is read into a body like the rest)")
	check(absf(floor_at(-4.5, -3.0) - 0.3) < 0.02 and absf(floor_at(2.0, -12.0)) < 0.05 and absf(floor_at(5.0, 3.0) - 0.3) < 0.02,
		"the spots used below are open floor (%.2f, %.2f, %.2f)" % [floor_at(-4.5, -3.0), floor_at(2.0, -12.0), floor_at(5.0, 3.0)])

	main.set_process(false)   # (the test drives build mode itself)
	main._on_menu_chosen("build")
	check(build.active and main.watch_menu.building, "the menu's Build mode starts it, and the menu turns to the build page")

	# pick the couch up and put it down across the room
	point(couch_from.x, couch_from.z)
	check(build.hovered == couch, "pointing at the couch picks it out")
	check(point(couch_from.x, couch_from.z, true) == "picked" and build.held == couch, "the trigger picks it up")
	await physics_frame
	check(absf(floor_at(couch_from.x, couch_from.z) - 0.3) < 0.02, "while it is carried there is nothing left where it stood")
	point(-4.5, -3.0, true)
	check(couch.global_position.distance_to(Vector3(-4.5, couch_from.y, -3.0)) < 0.01, "it follows the pointer across the floor, at the same height (%s)" % couch.global_position)
	point(-4.5, -3.0)
	check(point(-4.5, -3.0, true) == "placed" and build.held == null, "the trigger again puts it down")

	# turning: one step a flick
	var facing_before: Vector3 = couch.global_basis.z
	point(-4.5, -3.0)
	point(-4.5, -3.0, true)
	check(point(-4.5, -3.0, false, 1.0) == "turned", "a flick of the stick turns it")
	check(point(-4.5, -3.0, false, 1.0) == "", "holding the stick over does not keep turning it")
	point(-4.5, -3.0, false, 0.0)
	point(-4.5, -3.0, false, 1.0)
	point(-4.5, -3.0, true)
	var turned := facing_before.signed_angle_to(couch.global_basis.z, Vector3.UP)
	check(absf(turned + PI / 6.0) < 0.01, "two flicks right: 30 degrees clockwise (%.1f)" % rad_to_deg(turned))
	point(-4.5, -3.0)
	point(-4.5, -3.0, true)
	check(point(-4.5, -3.0, false, 0.0, true) == "kept" and is_instance_valid(couch), "the house's own pieces cannot be removed")
	point(-4.5, -3.0, true)
	point(-4.5, -3.0)

	# add a rail in the yard and an arcade machine in the shop
	main._on_menu_chosen("add_rail")
	var rail: Node3D = build.held
	check(rail != null and BuildPieces.info(rail).kind == "rail", "Add a flat rail puts one in your hand")
	point(2.0, -12.0)
	check(point(2.0, -12.0, true) == "placed" and rail.global_position.distance_to(Vector3(2.0, 0.0, -12.0)) < 0.05, "and it goes down in the yard (%s)" % rail.global_position)
	point(2.0, -12.0)
	main._on_menu_chosen("add_arcade")
	var arcade: Node3D = build.held
	point(5.0, 3.0)
	check(point(5.0, 3.0, true) == "placed" and arcade.global_position.distance_to(Vector3(5.0, 0.3, 3.0)) < 0.02, "an arcade machine goes down in the shop (%s)" % arcade.global_position)
	point(5.0, 3.0)
	main._on_menu_chosen("add_rail")
	var spare: Node3D = build.held
	point(0.0, -12.0)
	check(point(0.0, -12.0, false, 0.0, true) == "removed" and build.pieces.size() == 5 and not spare in build.pieces, "B removes a piece that was added")
	check(BuildPieces.info(arcade).id == "arcade_1" and BuildPieces.info(rail).id == "rail_1", "added pieces have their own names")

	# done: saved, and the house loaded again
	var couch_to: Vector3 = couch.global_position
	var couch_basis: Basis = couch.global_basis
	HubLayout.write(build.layout())
	check(HubLayout.read().size() == 5, "the layout is saved: three pieces of the house and two added")
	BuildMode.come_back = {"pos": Vector3(3.5, 0.3, 3.0), "yaw": -PI / 2.0, "building": false}
	main.queue_free()
	await process_frame
	await open_house()
	build = main.build
	main.set_process(false)
	main.foot.update(0.05, Vector2.ZERO, 0.0)
	check(main.on_foot and main.foot.body().distance_to(Vector3(3.5, 0.3, 3.0)) < 0.05, "you come back standing where you were (%s)" % main.foot.body())
	check(not build.active, "and build mode is over")
	couch = piece("couch")
	check(couch.global_position.distance_to(couch_to) < 0.01 and couch.global_basis.z.distance_to(couch_basis.z) < 0.01, "the couch is where it was put, turned as it was")
	check(collider_at(couch_to.x, couch_to.z) == "COL_Couch" and absf(floor_at(couch_from.x, couch_from.z) - 0.3) < 0.02, "its collision moved with it")
	check(piece("rail_1") != null and piece("arcade_1") != null and main.level.grind_nodes.size() == 10, "the rail and the arcade machine are back, and the rail is grindable")
	var line: GrindPath = null
	for path in main.sim.paths:
		if path.name == "PATH_Build_rail_1":
			line = path
	check(line != null and absf(line.points[0].y - (BuildPieces.RAIL_HEIGHT - BuildPieces.RAIL_RADIUS)) < 0.02 and absf(line.length - BuildPieces.RAIL_LENGTH) < 0.01,
		"its grind line runs along the top of the bar")
	if line != null:
		var sim: Skater = main.sim
		var tangent: Vector3 = line.segment_at(line.length * 0.5).dir
		var arrival := line.point_at(line.length * 0.5) + Vector3.UP * (line.top_offset - Config.Board.truckBottom + 0.035)
		sim.set_spawn(arrival, Skater.yaw_of(tangent.x, tangent.z))
		sim.pos = arrival
		sim.vel = tangent * 3.0 + Vector3.DOWN * 0.15
		var command := Skater.Command.new()
		command.grind = true
		sim.update(command, 1.0 / 72.0)
		var caught := sim.mode == Skater.Mode.GRIND and sim.grind.path == line
		var s0: float = sim.grind.s if caught else 0.0
		for frame in 6:
			sim.update(command, 1.0 / 72.0)
		check(caught and sim.mode == Skater.Mode.GRIND and sim.grind.s - s0 > 0.05, "the board catches a 50-50 on it and grinds along")
	var arcade_mesh := piece("arcade_1").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var rail_mesh := piece("rail_1").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(arcade_mesh.layers == Hub.INDOOR_LAYER and rail_mesh.layers == 1, "the arcade machine is lit as indoors, the rail in the yard by the sun")
	main.foot.update(0.05, Vector2.ZERO, 0.0)
	walk(Vector2(0, 1), 3.0)
	var at: Vector3 = main.foot.body()
	check(at.x > 3.6 and at.x < 4.7, "walking into the arcade machine stops you (x %.2f)" % at.x)

	HubLayout.clear()
	check(HubLayout.read().is_empty(), "Put everything back clears the layout")

	print("\n%s" % ("all build checks pass" if failures == 0 else "%d failed" % failures))
	main.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
