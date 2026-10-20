# Import and physics checks for the complete backyard ramp, including real grind entry.
# godot --headless --xr-mode off --path . -s res://tests/halfpipe_logic.gd
extends SceneTree

var failures := 0

func check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok: failures += 1

func _init() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var level_root := Node3D.new()
	var pad := Node3D.new()
	pad.name = "RampPad"
	pad.set_meta("extras", {"role": "ramp_pad", "heading_radians": -PI / 2.0})
	level_root.add_child(pad)
	check(HubRamp.add_to(level_root), "Ramp installs on a pad")
	var level := LevelLoader.from_root(level_root, world)
	await physics_frame
	await physics_frame
	check(level.render_meshes.size() == 9, "Nine material batches rather than hundreds of draw calls")
	check(level.collision_bodies.size() == 1, "One static collision body")
	var paths := GrindPath.parse(level.grind_nodes)
	check(paths.size() == 9, "Both copings and seven top handrails imported with grind paths")
	check(paths.filter(func(p: GrindPath) -> bool: return p.kind == "coping").size() == 2, "Both coping grind paths retained")
	check(paths.filter(func(p: GrindPath) -> bool: return p.kind == "rail").size() == 7, "Exactly seven top handrails are grindable")
	var space := world.get_world_3d().direct_space_state
	# All casts explicitly reject back faces to detect incorrect triangle winding.
	var offset := HubRamp.ACROSS_OFFSET
	var probes := [
		[Vector3(0,4,offset), .012, "flat bottom"],
		[Vector3(6,4,offset), 1.812, "raised right deck"],
		[Vector3(-6,4,offset), 1.812, "raised left deck"],
		[Vector3(6,4,offset+2.65), 1.632, "first stair tread"],
		[Vector3(6,4,offset+3.85), .912, "middle stair tread"],
		[Vector3(6,4,offset+5.05), .192, "bottom stair tread"],
		[Vector3(4.8,4,offset), 1.812-sqrt(1.8*1.8-1.2*1.2), "smooth right transition"],
	]
	for p in probes:
		var q := PhysicsRayQueryParameters3D.create(p[0], p[0]-Vector3(0,5,0))
		q.hit_back_faces = false
		var hit := space.intersect_ray(q)
		check(not hit.is_empty() and absf(hit.position.y-p[1]) < .006, "%s collision at expected height" % p[2])
	# A horizontal ray inside the transition volume must not hit a deck front wall.
	var q := PhysicsRayQueryParameters3D.create(Vector3(5.39,1.3,offset), Vector3(5.8,1.3,offset))
	q.hit_back_faces = false
	check(space.intersect_ray(q).is_empty(), "No hidden wall behind the transition")
	# Between the back guard bars, outside the upright positions, there must be air.
	# Collision follows the visible rails instead of filling their gaps.
	q = PhysicsRayQueryParameters3D.create(Vector3(6.3,2.28,offset+.5), Vector3(6.9,2.28,offset+.5))
	q.hit_back_faces = false
	check(space.intersect_ray(q).is_empty(), "Gaps between guard bars have no invisible wall")
	var skate_world := SkateWorld.new(space)
	for path: GrindPath in paths:
		# Independent collision rays check marker height against the physical rail surface.
		if path.kind == "rail":
			var centre := path.point_at(path.length * .5)
			q = PhysicsRayQueryParameters3D.create(centre+Vector3.UP*.1, centre-Vector3.UP*.1)
			q.hit_back_faces = false
			var hit := space.intersect_ray(q)
			check(not hit.is_empty() and absf(hit.position.y-centre.y-path.top_offset) < .003,
				"%s grind line matches its collision surface" % path.name)
		for direction in [-1.0, 1.0]:
			for slide in [false, true]:
				var sim := Skater.new(skate_world, paths, [], {}, true)
				sim.random_fn = func() -> float: return .5
				var tangent: Vector3 = path.segment_at(path.length*.5).dir * direction
				var yaw := Skater.yaw_of(tangent.x,tangent.z) + (PI/2.0 if slide else 0.0)
				var contact := path.slide_contact if slide else Config.Board.truckBottom
				var arrival := path.point_at(path.length*.5)+Vector3.UP*(path.top_offset-contact+.035)
				sim.set_spawn(arrival,yaw)
				sim.pos = arrival
				sim.vel = tangent*3.0+Vector3.DOWN*.15
				var command := Skater.Command.new()
				command.grind = true
				sim.update(command,1.0/72.0)
				var caught := sim.mode == Skater.Mode.GRIND and sim.grind.path == path
				check(caught,"%s catches a %s in direction %s" % [path.name,"boardslide" if slide else "50-50",direction])
				if caught:
					var before := sim.grind.s
					for frame in 6: sim.update(command,1.0/72.0)
					check(sim.mode == Skater.Mode.GRIND and (sim.grind.s-before)*direction > .05,
						"%s carries the board along the rail" % path.name)
	var bounds := AABB()
	var first := true
	for m: MeshInstance3D in level.render_meshes:
		var b := level_root.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		bounds=b if first else bounds.merge(b)
		first=false
	check(bounds.position.x > -8.0 and bounds.end.x < 8.0 and bounds.position.z > -4.5 and bounds.end.z < 4.5, "Visual footprint lies inside the backyard slab")
	print("HALFPIPE_VALIDATION failures=", failures)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)
