# The backyard's timber mini-ramp. Blender supplies the visible model and a separate
# collision surface; the game's loader still owns physics bodies and coping paths.
class_name HubRamp
extends RefCounted

const RAMP_SCENE := "res://assets/wooden_halfpipe/wooden_halfpipe.glb"
const RAMP_COLLISION := "res://assets/wooden_halfpipe/wooden_halfpipe_collision.tres"
# The stairs project to local +Z. Centre the whole footprint on the 9 m slab.
const ACROSS_OFFSET := -0.85


static func add_to(root: Node3D) -> bool:
	var pad := root.find_child("RampPad", true, false) as Node3D
	if pad == null:
		return false
	var packed := load(RAMP_SCENE) as PackedScene
	var shape := load(RAMP_COLLISION) as ConcavePolygonShape3D
	if packed == null or shape == null:
		push_error("The backyard half-pipe model or collision resource is missing")
		return false
	var heading: float = (pad.get_meta("extras", {}) as Dictionary).get("heading_radians", 0.0)
	var xf := Transform3D(Basis(Vector3.UP, heading + PI / 2.0), pad.position)
	xf = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, ACROSS_OFFSET))
	var model := packed.instantiate() as Node3D
	model.name = "HalfPipe"
	model.transform = xf
	root.add_child(model)

	# One static collision mesh, under the model so that build mode moves the two together.
	# There is no hidden wall behind either transition: the board's front wheels can extend
	# behind the riding skin near the lip.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = shape.get_faces()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var collider := MeshInstance3D.new()
	collider.name = "COL_WoodenHalfPipe"
	collider.mesh = mesh
	collider.set_meta("extras", {"role": "collision"})
	model.add_child(collider)

	# The GLB includes grind_path markers generated from both coping pipes and all
	# seven top handrails. LevelLoader discovers them under the model with its normal scan.
	return true
