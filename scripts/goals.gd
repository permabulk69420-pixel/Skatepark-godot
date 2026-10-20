# The goals of a park level. For now each is a score to reach in one visit (your banked total, once a chain has been landed and rolled
# out). A goal that has been reached stays ticked for good: they are kept in user://goals.cfg, a section per level.
#   goals are listed in the level's entry in levels.gd:  "goals": [{"id": "score_5000", "score": 5000}, ...]
class_name Goals
extends RefCounted

signal completed(text: String)   # a goal was reached just now

const FILE := "user://goals.cfg"

var level_id: String
var list: Array
var path: String
var done := {}                   # id -> true


func _init(p_level_id: String, definitions: Array, p_path := FILE) -> void:
	level_id = p_level_id
	list = definitions
	path = p_path
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for def: Dictionary in list:
			if cfg.get_value(level_id, def.id, false):
				done[def.id] = true


static func text_of(def: Dictionary) -> String:
	return "Score %s points" % Score.format(int(def.get("score", 0)))


# Your banked total has just gone up: tick off whatever it has reached.
func check_total(total: int) -> void:
	var reached: Array = []
	for def: Dictionary in list:
		if not done.has(def.id) and total >= int(def.get("score", 1 << 60)):
			done[def.id] = true
			reached.append(def)
	if reached.is_empty():
		return
	_save()
	for def: Dictionary in reached:
		completed.emit(text_of(def))


func done_count() -> int:
	var count := 0
	for def: Dictionary in list:
		if done.has(def.id):
			count += 1
	return count


# For the menu page: [{ text, done }, ...] in order.
func lines() -> Array:
	var out: Array = []
	for def: Dictionary in list:
		out.append({"text": text_of(def), "done": done.has(def.id)})
	return out


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	for def: Dictionary in list:
		if done.has(def.id):
			cfg.set_value(level_id, def.id, true)
	cfg.save(path)
