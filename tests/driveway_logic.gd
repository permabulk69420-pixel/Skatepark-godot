# Exercise the imported fence opening and the route in the real hub, including
# the original collision wall, outside ground, gate leaves and skateboard travel.
extends SceneTree

var failures := 0

func _init() -> void:
	run.call_deferred()

func check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok: failures += 1

func run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.level_id = "hub"
	root.add_child(main)
	var guard := 0
	while not main.ready_to_play and guard < 3000:
		await process_frame
		guard += 1
	check(main.ready_to_play, "Hub becomes ready with driveway installed")
	if not main.ready_to_play:
		quit(1)
		return
	main.set_process(false)
	await physics_frame
	await physics_frame
	var driveway: Node3D = main.level.root.find_child("Driveway", true, false)
	check(driveway != null, "Driveway is installed in the real hub")
	check(main.level.grind_nodes.size() == 9, "Existing two coping and seven rail paths remain")
	var pavement := driveway.get_node("Driveway_Concrete") as MeshInstance3D
	var bounds := pavement.get_aabb()
	check(bounds.end.z > 17.9, "Paving extends six metres beyond the front fence")
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	# A horizontal ray through the complete opening must pass from either side;
	# the uncut boundary triangles used to span the entire width of the property.
	for x in [-14.7, -13.5, -12.5, -11.5, -10.3]:
		for dir in [-1.0, 1.0]:
			var a := Vector3(x, 0.8, 12.0 + dir * 3.0)
			var b := Vector3(x, 0.8, 12.0 - dir * 3.0)
			var query := PhysicsRayQueryParameters3D.create(a, b)
			query.hit_back_faces = false
			check(space.intersect_ray(query).is_empty(), "Gate is clear at x %.1f from side %.0f" % [x, dir])
	for x in [-17.0, -8.0]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 0.8, 10), Vector3(x, 0.8, 14))
		check(not space.intersect_ray(query).is_empty(), "Fence still blocks beside opening at x %.0f" % x)
	for p in [Vector2(-16, -16), Vector2(-8, -16), Vector2(-12.5, -19),
		Vector2(-21, 0), Vector2(21, 0), Vector2(0, 31)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 1, -p.y), Vector3(p.x, -1, -p.y))
		var hit := space.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y) < 0.002,
			"Exterior dirt is solid at %s" % p)
	for p in [Vector2(-12.5, -17.5), Vector2(-12.5, -12.0), Vector2(-12.5, 0.0),
		Vector2(-12.5, 10.0), Vector2(-10, 13), Vector2(-5, 13), Vector2(1, 14.5), Vector2(-8, 18)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(p.x, 2, -p.y), Vector3(p.x, -1, -p.y))
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y - HubDriveway.HEIGHT) < 0.002,
			"Driveway has upward-facing collision at %s" % p)
	# Each open leaf must be solid, while its full extent stays out of the opening.
	for label in ["OpenGate_Left", "OpenGate_Right"]:
		var marker := driveway.get_node(label) as Marker3D
		var side := -1.0 if label.ends_with("Left") else 1.0
		var centre := marker.global_transform * Vector3(-side * 1.24, 0.8, 0)
		var normal := marker.global_basis.z
		var query := PhysicsRayQueryParameters3D.create(centre - normal, centre + normal)
		check(not space.intersect_ray(query).is_empty(), "%s has physical collision" % label)
	# Walk out of the property, then back in through the same gate.
	main.foot.place(Vector3(-12.5, HubDriveway.HEIGHT, 9.0), PI)
	for i in 70: main.foot.update(0.05, Vector2(0, 1), 0.0)
	check(main.foot.body().z > 14.0 and not main.foot.air, "Can walk outside through the open gate")
	main.foot.place(Vector3(-12.5, HubDriveway.HEIGHT, 16.0), 0.0)
	for i in 70: main.foot.update(0.05, Vector2(0, 1), 0.0)
	check(main.foot.body().z < 11.0 and not main.foot.air, "Can walk back inside through the gate")
	# A rolling board crosses the old boundary without hitting an invisible wall.
	var sim := Skater.new(main.world, [], [], Levels.LEVELS[Levels.HUB].bounds, true)
	sim.set_spawn(Vector3(-12.5, HubDriveway.HEIGHT, 9.0), PI)
	sim.vel = Vector3(0, 0, 4.0)
	var command := Skater.Command.new()
	for i in 144: sim.update(command, 1.0 / 72.0)
	check(sim.pos.z > 13.0, "Skateboard rolls through the gate without snagging")
	check(sim.pos.z > 15.0, "Actual hub play bounds allow riding onto the outside driveway")
	main.foot.place(Vector3(-12.5, HubDriveway.HEIGHT, -8.0), 0.0)
	for i in 55: main.foot.update(0.05, Vector2(0, 1), 0.0)
	main.foot.look_yaw = -PI / 2.0
	for i in 115: main.foot.update(0.05, Vector2(0, 1), 0.0)
	check(main.foot.body().x > -2.0 and not main.foot.air, "Can follow the driveway around the house to the ramp apron")
	main.foot.look_yaw = 0.0
	for i in 25: main.foot.update(0.05, Vector2(0, 1), 0.0)
	check(main.foot.body().z < -15.0 and not main.foot.air, "Driveway joins the original ramp slab without a gap")
	print("DRIVEWAY_VALIDATION failures=", failures)
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
