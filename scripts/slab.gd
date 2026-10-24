# The Slab: a blank square of concrete in an open field, to build a park on yourself. It is made in code and read by LevelLoader like an
# imported file: the concrete and the field it sits in, their COL_ collision, the spawn, and whatever build mode has added (HubLayout).
class_name Slab
extends RefCounted

const SIZE := 100.0             # metres along each side of the concrete
const TILE := 4.0               # metres the concrete's texture covers before it repeats
const FIELD := 600.0            # metres along each side of the field round it
const FIELD_TILE := 8.0
const FIELD_DROP := 0.02        # the field lies this far below the concrete
const SPAWN := Vector3(0.0, 0.03, 20.0)   # on the concrete, facing its middle
const CONCRETE := ["res://assets/levels/switchyard_concrete_floor_base.webp", "res://assets/levels/switchyard_concrete_floor_normal.webp",
	"res://assets/levels/switchyard_concrete_floor_orm.webp"]
const GROUND := ["res://assets/levels/hub_ground_base.jpg", "res://assets/levels/hub_ground_normal.png", "res://assets/levels/hub_ground_orm.jpg"]


static func build_root() -> Node3D:
	var root := Node3D.new()
	root.name = "Slab"
	_add_floor(root, "Slab_Concrete", SIZE, 0.0, _material(CONCRETE, SIZE / TILE))
	_add_floor(root, "Slab_Field", FIELD, -FIELD_DROP, _material(GROUND, FIELD / FIELD_TILE))
	var spawn := Node3D.new()
	spawn.name = "Spawn_Entrance"
	spawn.position = SPAWN
	spawn.set_meta("extras", {"role": "spawn", "heading_radians": 0.0})
	root.add_child(spawn)
	HubLayout.apply(root, HubLayout.read(Levels.SLAB))
	return root


# A flat square `size` across at height `y`, drawn with `material`, and its collision.
static func _add_floor(root: Node3D, node_name: String, size: float, y: float, material: Material) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var floor := MeshInstance3D.new()
	floor.name = node_name
	floor.mesh = plane
	floor.material_override = material
	floor.position.y = y
	root.add_child(floor)
	var collider := MeshInstance3D.new()
	collider.name = "COL_" + node_name
	collider.mesh = plane
	collider.position.y = y
	collider.visible = false
	collider.set_meta("extras", {"role": "collision"})
	root.add_child(collider)


# `textures`: its colour, normal and ORM maps.
static func _material(textures: Array, repeats: float) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(textures[0])
	m.normal_enabled = true
	m.normal_texture = load(textures[1])
	m.orm_texture = load(textures[2])
	m.uv1_scale = Vector3(repeats, repeats, 1.0)
	return m
