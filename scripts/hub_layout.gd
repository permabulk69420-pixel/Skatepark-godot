# Where build mode left things in the house: kept in user://layout.cfg, a section per piece (its id) with its kind ("" for the house's
# own half pipe, couch and rug) and where it stands. Read each time the house is built. Any other level that can be built in (the Slab)
# keeps its own, in user://layout_<level>.cfg.
class_name HubLayout
extends RefCounted

const FILE := "user://layout.cfg"

static var path := FILE   # (a test points it somewhere else)


static func file(level := Levels.HUB) -> String:
	return path if level == Levels.HUB else "user://layout_%s.cfg" % level


# [{"id", "kind", "transform"}], or empty when nothing has been moved yet.
static func read(level := Levels.HUB) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(file(level)) != OK:
		return []
	var entries: Array = []
	for id in cfg.get_sections():
		entries.append({"id": id, "kind": cfg.get_value(id, "kind", ""), "transform": cfg.get_value(id, "transform", Transform3D.IDENTITY)})
	return entries


static func write(entries: Array, level := Levels.HUB) -> void:
	var cfg := ConfigFile.new()
	for entry: Dictionary in entries:
		cfg.set_value(entry.id, "kind", entry.kind)
		cfg.set_value(entry.id, "transform", entry.transform)
	cfg.save(file(level))


# Everything back where the house had it (or, on the Slab, nothing there).
static func clear(level := Levels.HUB) -> void:
	if FileAccess.file_exists(file(level)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file(level)))


# Puts the house's own pieces where they were left and adds the pieces that were added (`root`: the house, already marked).
static func apply(root: Node3D, entries: Array) -> void:
	var own := {}
	for piece in BuildPieces.find_all(root):
		own[BuildPieces.info(piece).id] = piece
	for entry: Dictionary in entries:
		if entry.kind == "":
			if own.has(entry.id):
				(own[entry.id] as Node3D).transform = entry.transform
		elif entry.kind in BuildPieces.ADDABLE:
			var piece := BuildPieces.make(entry.kind, entry.id)
			piece.transform = entry.transform
			root.add_child(piece)
