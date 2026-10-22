extends Node
## The rules, one small board per idea: each must end exactly as the rules say.
## Run: godot --headless --path . res://tests/route_smoke.tscn

var failures: int = 0


func _ready() -> void:
	# Straight up into home, no dots: wins with no arrows.
	_expect("straight home", {"w": 3, "h": 4, "starts": [[1, 3, 3]], "home": [1, 0]}, [], RouteSim.WIN, 3)
	# Off the top edge.
	_expect("edge", {"w": 3, "h": 4, "starts": [[1, 3, 3]], "home": [0, 0]}, [], RouteSim.EDGE)
	# Into a block.
	_expect("block", {"w": 3, "h": 4, "starts": [[1, 3, 3]], "home": [0, 0], "blocks": [[1, 1]]}, [], RouteSim.CRASH)
	# An arrow turns it right into home.
	_expect("arrow", {"w": 3, "h": 4, "starts": [[0, 3, 3]], "home": [2, 1]}, [[0, 1, 0]], RouteSim.WIN, 4)
	# Home stays shut until the dot is taken: rolls over home, takes the dot, comes back.
	_expect("home waits for dots", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [1, 0], "dots": [[2, 0]]}, [[3, 0, 2]], RouteSim.WIN, 5)
	# Two arrows facing each other: round in circles.
	_expect("loop", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [3, 0], "dots": [[0, 0]]}, [[1, 0, 0], [2, 0, 2]], RouteSim.LOOP)
	# A sign does the turn.
	_expect("sign", {"w": 3, "h": 3, "starts": [[0, 2, 0]], "home": [1, 0], "signs": [[1, 2, 3]]}, [], RouteSim.WIN, 3)
	# Bends: "/" sends right-movers up, "\" sends up-movers left.
	_expect("bend /", {"w": 3, "h": 3, "starts": [[0, 2, 0]], "home": [1, 0], "bends": [[1, 2, 0]]}, [], RouteSim.WIN, 3)
	_expect("bend \\", {"w": 3, "h": 3, "starts": [[1, 2, 3]], "home": [0, 0], "bends": [[1, 0, 1]]}, [], RouteSim.WIN, 3)
	# A shut gate blocks; the switch first opens it.
	_expect("gate shut", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [3, 0], "gates": [[2, 0, 0]]}, [], RouteSim.CRASH)
	_expect("switch opens gate", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [3, 0], "switches": [[1, 0]], "gates": [[2, 0, 0]]}, [], RouteSim.WIN, 3)
	_expect("switch shuts gate", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [3, 0], "switches": [[1, 0]], "gates": [[2, 0, 1]]}, [], RouteSim.CRASH)
	# A spinner points up, then turns: on the way back it points right.
	_expect("spinner", {"w": 5, "h": 3, "starts": [[0, 2, 0]], "home": [4, 2], "spinners": [[2, 2, 3]], "dots": [[2, 1]]}, [[2, 0, 1]], RouteSim.WIN, 8)
	# A portal keeps the heading.
	_expect("portal", {"w": 5, "h": 3, "starts": [[0, 2, 0]], "home": [4, 0], "portals": [[1, 2, 2, 0]]}, [], RouteSim.WIN, 3)
	# Cracked floor: once is fine, twice is a fall.
	_expect("crack once", {"w": 3, "h": 1, "starts": [[0, 0, 0]], "home": [2, 0], "cracks": [[1, 0]]}, [], RouteSim.WIN, 2)
	_expect("crack twice", {"w": 4, "h": 1, "starts": [[0, 0, 0]], "home": [0, 0], "cracks": [[1, 0]], "dots": [[2, 0]]}, [[3, 0, 2]], RouteSim.CRASH)
	# Numbered dots: 2 before 1 doesn't count; coming back for it does.
	_expect("order", {"w": 5, "h": 1, "starts": [[0, 0, 0]], "home": [1, 0], "dots": [[2, 0, 2], [3, 0, 1]]}, [[4, 0, 2]], RouteSim.WIN, 7)
	# Two orbs: both home wins (even together); one cell or head-on elsewhere collides.
	_expect("twins", {"w": 3, "h": 4, "starts": [[0, 0, 0], [2, 3, 3]], "home": [2, 0]}, [], RouteSim.WIN, 3)
	_expect("twins home together", {"w": 3, "h": 3, "starts": [[0, 0, 0], [2, 2, 3]], "home": [2, 0]}, [], RouteSim.WIN, 2)
	_expect("twins meet", {"w": 3, "h": 3, "starts": [[0, 0, 0], [2, 2, 3]], "home": [0, 2], "dots": [[1, 1]]}, [], RouteSim.COLLIDE)
	_expect("collide", {"w": 4, "h": 1, "starts": [[0, 0, 0], [3, 0, 2]], "home": [1, 0], "dots": [[2, 0]]}, [], RouteSim.COLLIDE)
	# The guide stops after the first turn plus two cells.
	var lv: Dictionary = {"w": 5, "h": 5, "starts": [[0, 4, 3]], "home": [4, 4]}
	var arrows: Dictionary = {RouteSim.cell_of(lv, 0, 1): 0}
	var guide: Array = RouteSim.preview(lv, arrows, 1, 2)
	_check((guide[0]["cells"] as Array).size() == 6 and str(guide[0]["end"]) == "more", "guide: start, 3 up to the arrow, 2 after it")
	# Placeable cells: not on pieces.
	var lv2: Dictionary = {"w": 3, "h": 3, "starts": [[0, 0, 0]], "home": [2, 2], "dots": [[1, 1]], "cracks": [[2, 0]]}
	_check(not RouteSim.placeable(lv2, RouteSim.cell_of(lv2, 1, 1)), "no arrow on a dot")
	_check(RouteSim.placeable(lv2, RouteSim.cell_of(lv2, 2, 0)), "arrows may go on cracked floor")
	_check(not RouteSim.placeable(lv2, RouteSim.cell_of(lv2, 0, 0)), "no arrow on the start")
	# Every chapter's card scene wins (so the art shows a real run).
	for id: String in ChapterArt.SCENES:
		var sc: Array = ChapterArt.SCENES[id]
		var a: Dictionary = {}
		for q: Array in sc[1]:
			a[RouteSim.cell_of(sc[0], int(q[0]), int(q[1]))] = int(q[2])
		_check(str(RouteSim.run(sc[0], a)["result"]) == RouteSim.WIN, "the %s card shows a winning run" % id)
	print("ROUTE SMOKE: %s" % ("FAIL (%d)" % failures if failures > 0 else "PASS"))
	get_tree().quit(1 if failures > 0 else 0)


func _expect(what: String, lv: Dictionary, arrows: Array, result: String, ticks: int = -1) -> void:
	var a: Dictionary = {}
	for q: Array in arrows:
		a[RouteSim.cell_of(lv, int(q[0]), int(q[1]))] = int(q[2])
	var res: Dictionary = RouteSim.run(lv, a)
	var ok: bool = str(res["result"]) == result and (ticks < 0 or int(res["ticks"]) == ticks)
	_check(ok, "%s: expected %s%s, got %s in %d" % [what, result, "" if ticks < 0 else " in %d" % ticks, res["result"], int(res["ticks"])])


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error(what)
		print("  FAIL ", what)
