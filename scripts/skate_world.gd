# Ground and wall queries against the park's invisible collision meshes (the "COL_" nodes in the level file).
# Rays only hit the front of a face, so a point inside solid geometry finds nothing: callers read that as "you are in a wall".
class_name SkateWorld
extends RefCounted


# What a query found. One instance is reused by each caller, so read it before asking again.
class Hit:
	var y := 0.0                  # ground(): height of the surface
	var dist := 0.0               # cast(): how far along the ray
	var normal := Vector3.UP
	var collider: Node = null     # which collision body (the sounds tell wood from concrete by its name)


var space: PhysicsDirectSpaceState3D
var query := PhysicsRayQueryParameters3D.new()


func _init(p_space: PhysicsDirectSpaceState3D) -> void:
	space = p_space
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_back_faces = false
	query.hit_from_inside = false


# Turns a level's collision meshes into one static body per mesh (named after it) in the given world.
static func add_colliders(parent: Node3D, meshes: Array) -> Array[StaticBody3D]:
	var bodies: Array[StaticBody3D] = []
	for mesh_instance: MeshInstance3D in meshes:
		var faces := mesh_instance.mesh.get_faces()
		var xf := mesh_instance.global_transform
		var world_faces := PackedVector3Array()
		world_faces.resize(faces.size())
		for i in faces.size():
			world_faces[i] = xf * faces[i]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = false
		shape.set_faces(world_faces)
		var body := StaticBody3D.new()
		body.name = mesh_instance.name
		var owner_shape := CollisionShape3D.new()
		owner_shape.shape = shape
		body.add_child(owner_shape)
		parent.add_child(body)
		bodies.append(body)
	return bodies


# First upward-facing surface below (x, from_y, z). Null when there is none, or the first thing hit faces away from up.
func ground(x: float, z: float, from_y: float, out: Hit, max_drop: float = 30.0) -> Hit:
	query.from = Vector3(x, from_y, z)
	query.to = Vector3(x, from_y - max_drop, z)
	var res := space.intersect_ray(query)
	if res.is_empty():
		return null
	var n: Vector3 = res.normal
	if n.y < 0.05:
		return null
	out.y = res.position.y
	out.normal = n
	out.collider = res.collider
	return out


# Any-direction ray against the collision meshes (front faces only). Fills out.dist and the surface normal.
func cast(origin: Vector3, dir: Vector3, far: float, out: Hit) -> Hit:
	query.from = origin
	query.to = origin + dir * far
	var res := space.intersect_ray(query)
	if res.is_empty():
		return null
	var hit_pos: Vector3 = res.position
	out.dist = origin.distance_to(hit_pos)
	out.normal = res.normal
	out.collider = res.collider
	return out
