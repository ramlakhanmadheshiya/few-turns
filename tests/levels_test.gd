extends SceneTree
## Proves every shipped level is fair and the chapters are paced as designed:
## - the stored solution gets home with exactly the level's turns, every arrow on
##   a free cell, in the same number of ticks as the generator's run (so the
##   GDScript rules and tools/route_lab.py agree);
## - turns climb with the schedule: 1 at the start of a chapter, 5 at level 40;
## - difficulty rises strictly from level 2 to level 40 (level 1 is the tutorial);
## - every room uses its chapter's idea, and neighbours never play the same shape;
## - nothing sits off the board or on top of something else.
## The solver's proof that no room can be done with fewer turns lives in
## tools/route_lab.py (`--check`), which is too slow for every run.
## Run: godot --headless --path . -s res://tests/levels_test.gd

const CHAPTERS: int = 9
const IDEAS: Dictionary = {"ch2": "signs", "ch3": "bends", "ch4": "gates", "ch5": "spinners", "ch6": "portals", "ch7": "cracks", "ch8": "ordered", "ch9": "twin"}
var failures: int = 0


func _init() -> void:
	var ids: Dictionary = {}
	var count: int = 0
	for cid: String in Palette.ids():
		var path: String = "res://content/levels/%s.json" % cid
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			_fail("%s: missing or invalid" % path)
			continue
		var list: Array = data["levels"]
		if list.size() != 40:
			_fail("%s: has %d levels, expected 40" % [cid, list.size()])
			continue
		if not bool(list[0].get("intro", false)):
			_fail("%s: level 1 should be the chapter's tutorial room" % cid)
		if int(list[0]["turns"]) != 1:
			_fail("%s: the tutorial room should need one turn" % cid)
		for i: int in range(2, list.size()):
			if float(list[i]["difficulty"]) <= float(list[i - 1]["difficulty"]):
				_fail("%s: level %d is not harder than level %d" % [cid, i + 1, i])
			if str(list[i].get("sig", "")) == str(list[i - 1].get("sig", "")):
				_fail("%s: levels %d and %d play the same shape" % [cid, i, i + 1])
		if float(list[0]["difficulty"]) >= float(list[1]["difficulty"]):
			_fail("%s: the tutorial room is not the easiest" % cid)
		for i: int in list.size():
			var want: int = turn_goal(i + 1)
			if int(list[i]["turns"]) != want:
				_fail("%s: level %d gives %d turns, the schedule says %d" % [cid, i + 1, int(list[i]["turns"]), want])
		for lv: Dictionary in list:
			count += 1
			var id: String = str(lv["id"])
			if ids.has(id):
				_fail("duplicate id " + id)
			ids[id] = true
			_check_level(cid, lv)
	if count != CHAPTERS * 40:
		_fail("expected %d levels (%d chapters x 40), found %d" % [CHAPTERS * 40, CHAPTERS, count])
	print("LEVELS: %d checked, %s" % [count, "FAIL (%d)" % failures if failures > 0 else "PASS"])
	quit(1 if failures > 0 else 0)


## Arrows on level n (1-based): 1 at the start of a chapter, 5 at level 40.
static func turn_goal(n: int) -> int:
	return 1 + roundi(float(n - 1) * 4.0 / 39.0)


func _check_level(cid: String, lv: Dictionary) -> void:
	var id: String = str(lv["id"])
	var w: int = int(lv["w"])
	var h: int = int(lv["h"])
	# Nothing off the board, nothing stacked.
	var taken: Dictionary = {}
	for key: String in ["blocks", "signs", "spinners", "bends", "switches", "gates", "cracks", "dots"]:
		for q: Array in lv.get(key, []):
			_place(id, key, int(q[0]), int(q[1]), w, h, taken)
	for q: Array in lv.get("portals", []):
		_place(id, "portal", int(q[0]), int(q[1]), w, h, taken)
		_place(id, "portal", int(q[2]), int(q[3]), w, h, taken)
	for q: Array in lv["starts"]:
		_place(id, "start", int(q[0]), int(q[1]), w, h, taken)
	_place(id, "home", int(lv["home"][0]), int(lv["home"][1]), w, h, taken)
	# The solution: the right number of arrows, each on a free cell, and it wins.
	var sol: Array = lv.get("solution", [])
	if sol.size() != int(lv["turns"]):
		_fail("%s: the solution lays %d arrows for %d turns" % [id, sol.size(), int(lv["turns"])])
	var arrows: Dictionary = RouteSim.solution_arrows(lv)
	for c: Variant in arrows:
		if not RouteSim.placeable(lv, int(c)):
			_fail("%s: a solution arrow sits where arrows can't go" % id)
	var res: Dictionary = RouteSim.run(lv, arrows)
	if str(res["result"]) != RouteSim.WIN:
		_fail("%s: the stored solution doesn't get home (%s)" % [id, res["result"]])
	elif int(res["ticks"]) != int(lv["ticks"]):
		_fail("%s: home in %d ticks here, %d in the generator: the rules disagree" % [id, int(res["ticks"]), int(lv["ticks"])])
	# With no arrows at all it must not win.
	if str(RouteSim.run(lv, {})["result"]) == RouteSim.WIN:
		_fail("%s: wins with no arrows" % id)
	if IDEAS.has(cid) and not str(IDEAS[cid]) in (lv.get("uses", []) as Array):
		_fail("%s: doesn't use its chapter's idea (%s)" % [id, IDEAS[cid]])
	if (lv.get("dots", []) as Array).is_empty():
		_fail("%s: has no dots" % id)


func _place(id: String, what: String, x: int, y: int, w: int, h: int, taken: Dictionary) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		_fail("%s: a %s sits off the board" % [id, what])
		return
	var c: int = y * w + x
	if taken.has(c):
		_fail("%s: a %s sits on a %s" % [id, what, taken[c]])
	taken[c] = what


func _fail(msg: String) -> void:
	failures += 1
	push_error(msg)
	print("  ", msg)
