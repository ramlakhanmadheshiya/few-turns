extends Node
## Chapter and level catalogue, plus the unlock rules.

const LEVEL_DIR: String = "res://content/levels/"
## Clears needed in the previous chapter to open the next one.
const CHAPTER_GATE: int = 15

var chapters: Array[Dictionary] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	chapters.clear()
	for id: String in Palette.ids():
		var path: String = LEVEL_DIR + id + ".json"
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			chapters.append(parsed)


func chapter(id: String) -> Dictionary:
	for c: Dictionary in chapters:
		if str(c["id"]) == id:
			return c
	return {}


func chapter_index(id: String) -> int:
	for i: int in chapters.size():
		if str(chapters[i]["id"]) == id:
			return i
	return -1


func level(chapter_id: String, index: int) -> Dictionary:
	var c: Dictionary = chapter(chapter_id)
	var list: Array = c.get("levels", [])
	if index < 0 or index >= list.size():
		return {}
	return list[index]


func level_count(chapter_id: String) -> int:
	return (chapter(chapter_id).get("levels", []) as Array).size()


func total_levels() -> int:
	var n: int = 0
	for c: Dictionary in chapters:
		n += (c.get("levels", []) as Array).size()
	return n


func cleared_in(chapter_id: String) -> int:
	var n: int = 0
	for lv: Dictionary in chapter(chapter_id).get("levels", []):
		if SaveSystem.is_cleared(str(lv["id"])):
			n += 1
	return n


func total_cleared() -> int:
	var n: int = 0
	for c: Dictionary in chapters:
		n += cleared_in(str(c["id"]))
	return n


func stars_in(chapter_id: String) -> int:
	var n: int = 0
	for lv: Dictionary in chapter(chapter_id).get("levels", []):
		n += SaveSystem.stars_for(str(lv["id"]))
	return n


func chapter_open(chapter_id: String) -> bool:
	var i: int = chapter_index(chapter_id)
	if i <= 0:
		return true
	return cleared_in(str(chapters[i - 1]["id"])) >= CHAPTER_GATE


## Rooms open strictly one at a time: clear room N to open room N + 1. A level
## key opens any single room for good (even in a chapter that is still locked);
## clearing it then opens the next one as usual.
func level_open(chapter_id: String, index: int) -> bool:
	var list: Array = chapter(chapter_id).get("levels", [])
	if index < 0 or index >= list.size():
		return false
	var id: String = str(list[index]["id"])
	if SaveSystem.key_unlocked(id) or SaveSystem.is_cleared(id):
		return true
	if index == 0:
		return chapter_open(chapter_id)
	return SaveSystem.is_cleared(str(list[index - 1]["id"]))


## How many rooms of a chapter are open right now.
func open_in(chapter_id: String) -> int:
	var n: int = 0
	for i: int in level_count(chapter_id):
		if level_open(chapter_id, i):
			n += 1
	return n


## The level "Play" should open: the first unbeaten room near where the player was.
func continue_target() -> Dictionary:
	var last: Dictionary = SaveSystem.last_played()
	var cid: String = str(last.get("chapter", "ch1"))
	if chapter(cid).is_empty():
		cid = "ch1"
	var list: Array = chapter(cid).get("levels", [])
	for i: int in list.size():
		if not SaveSystem.is_cleared(str(list[i]["id"])) and level_open(cid, i):
			return {"chapter": cid, "index": i}
	# Chapter finished: move on to the next open chapter with work left.
	for c: Dictionary in chapters:
		var id: String = str(c["id"])
		if not chapter_open(id):
			continue
		var lv: Array = c.get("levels", [])
		for i: int in lv.size():
			if not SaveSystem.is_cleared(str(lv[i]["id"])) and level_open(id, i):
				return {"chapter": id, "index": i}
	return {"chapter": cid, "index": clampi(int(last.get("index", 0)), 0, maxi(0, list.size() - 1))}


## The level after (chapter, index), or {} at the very end.
func next_after(chapter_id: String, index: int) -> Dictionary:
	if index + 1 < level_count(chapter_id):
		return {"chapter": chapter_id, "index": index + 1}
	var ci: int = chapter_index(chapter_id)
	if ci + 1 < chapters.size():
		var nid: String = str(chapters[ci + 1]["id"])
		if chapter_open(nid):
			return {"chapter": nid, "index": 0}
	return {}
