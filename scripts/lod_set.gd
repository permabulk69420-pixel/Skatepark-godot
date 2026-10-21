# Distance LODs for chunked levels. Meshes that belong to one chunk share extras.lod.group; level 0 is the full detail, higher
# levels are cheaper copies that take over past their `from` distance. The distance is measured to the chunk's bounding box,
# so a big chunk keeps its detail while any part of it is close.
class_name LodSet
extends RefCounted


class LodGroup:
	var levels: Array = []   # [{ mesh: MeshInstance3D, from: float }], index = level
	var box := AABB()
	var has_box := false
	var current := -1


var hysteresis := 0.08
var groups: Array[LodGroup] = []


# `meshes`: the level's MeshInstance3D nodes, already in the scene tree (their world position is read here).
func _init(meshes: Array, p_hysteresis: float = 0.08) -> void:
	hysteresis = p_hysteresis
	var by_name := {}
	for mesh: MeshInstance3D in meshes:
		var extras: Dictionary = mesh.get_meta("extras", {})
		var lod = extras.get("lod")
		if lod == null:
			continue
		var group: LodGroup = by_name.get(lod.group)
		if group == null:
			group = LodGroup.new()
			by_name[lod.group] = group
			groups.append(group)
		var world_box := mesh.global_transform * mesh.get_aabb()
		if group.has_box:
			group.box = group.box.merge(world_box)
		else:
			group.box = world_box
			group.has_box = true
		var lvl := int(lod.level)
		while group.levels.size() <= lvl:
			group.levels.append(null)
		group.levels[lvl] = {"mesh": mesh, "from": float(lod.get("from", 0.0))}
	for group in groups:
		group.levels = group.levels.filter(func(l): return l != null)


static func box_distance(box: AABB, p: Vector3) -> float:
	var lo := box.position
	var hi := box.end
	var dx := maxf(maxf(lo.x - p.x, 0.0), p.x - hi.x)
	var dy := maxf(maxf(lo.y - p.y, 0.0), p.y - hi.y)
	var dz := maxf(maxf(lo.z - p.z, 0.0), p.z - hi.z)
	return sqrt(dx * dx + dy * dy + dz * dz)


# Picks the level of every chunk for a viewer at `position` (world space). Returns how many chunks changed.
func update(position: Vector3) -> int:
	var changed := 0
	for group in groups:
		var distance := box_distance(group.box, position)
		var levels := group.levels
		var want := 0
		for i in range(1, levels.size()):
			# Moving out needs a little more distance than moving in, so a chunk on the boundary does not flicker.
			var edge: float = levels[i].from * ((1.0 - hysteresis) if group.current >= i else (1.0 + hysteresis))
			if distance >= edge:
				want = i
		if want == group.current:
			continue
		group.current = want
		for i in levels.size():
			levels[i].mesh.visible = i == want
		changed += 1
	return changed


# How many chunks sit at each level right now.
func census() -> Array:
	var out := []
	for group in groups:
		while out.size() <= group.current:
			out.append(0)
		out[group.current] += 1
	return out
