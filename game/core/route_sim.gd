class_name RouteSim
extends RefCounted
## The rules of Few Turns, as a pure, deterministic simulation on a grid.
## tools/route_lab.py holds the same rules (it generates and solves the levels);
## tests/levels_test.gd replays every stored solution here and checks the tick
## count against the generator's, so the two must change together.
##
## Grid cells are indices (y * w + x). Directions: 0 right, 1 down, 2 left, 3 up;
## turning clockwise is d + 1. A run, tick by tick:
## 1. every rolling orb leaves its cell (a cracked cell it leaves crumbles);
## 2. it moves one cell on. Off the board, into a block, a closed gate or a hole:
##    crash. Two orbs into one cell (but an open home), or through each other: crash;
## 3. a portal sends it to its twin, same heading;
## 4. it takes a dot (numbered dots only in order);
## 5. home takes it once every dot is taken (until then it rolls over home);
## 6. it turns: an arrow or a sign points it, a spinner points it and then turns
##    clockwise, a bend (/ or \) deflects it;
## 7. a switch flips every gate.
## Every orb home wins; a crash loses; so does the board repeating itself.

const DX: Array[int] = [1, 0, -1, 0]
const DY: Array[int] = [0, 1, 0, -1]
## Bends: 0 is "/", 1 is "\". BEND[kind][heading in] = heading out.
const BEND: Array = [[3, 2, 1, 0], [1, 0, 3, 2]]
const MAX_TICKS: int = 400

## How a run ended.
const WIN: String = "win"
const CRASH: String = "crash"
const EDGE: String = "edge"
const COLLIDE: String = "collide"
const LOOP: String = "loop"

static var _cache: Dictionary = {}


static func dir_vec(d: int) -> Vector2i:
	return Vector2i(DX[d], DY[d])


## The fixed parts of a level as fast lookups (cached per level dictionary).
static func board(lv: Dictionary) -> Dictionary:
	var key: int = lv.hash()
	if _cache.has(key):
		return _cache[key]
	var w: int = int(lv["w"])
	var h: int = int(lv["h"])
	var b: Dictionary = {"w": w, "h": h, "blocks": {}, "signs": {}, "spinners": {}, "spin0": [], "bends": {},
		"switches": {}, "gates": {}, "portals": {}, "cracks": {}, "dots": {}, "ordered": false, "starts": []}
	for p: Array in lv.get("blocks", []):
		b["blocks"][int(p[1]) * w + int(p[0])] = true
	for p: Array in lv.get("signs", []):
		b["signs"][int(p[1]) * w + int(p[0])] = int(p[2])
	var spins: Array = lv.get("spinners", [])
	for i: int in spins.size():
		var p: Array = spins[i]
		b["spinners"][int(p[1]) * w + int(p[0])] = i
		(b["spin0"] as Array).append(int(p[2]))
	for p: Array in lv.get("bends", []):
		b["bends"][int(p[1]) * w + int(p[0])] = int(p[2])
	for p: Array in lv.get("switches", []):
		b["switches"][int(p[1]) * w + int(p[0])] = true
	for p: Array in lv.get("gates", []):
		b["gates"][int(p[1]) * w + int(p[0])] = int(p[2])
	for p: Array in lv.get("portals", []):
		var a: int = int(p[1]) * w + int(p[0])
		var c: int = int(p[3]) * w + int(p[2])
		b["portals"][a] = c
		b["portals"][c] = a
	var cracks: Array = lv.get("cracks", [])
	for i: int in cracks.size():
		b["cracks"][int(cracks[i][1]) * w + int(cracks[i][0])] = i
	var dots: Array = lv.get("dots", [])
	for i: int in dots.size():
		var d: Array = dots[i]
		var order: int = int(d[2]) if d.size() > 2 else 0
		b["dots"][int(d[1]) * w + int(d[0])] = [i, order]
		if order > 0:
			b["ordered"] = true
	b["all_dots"] = (1 << dots.size()) - 1
	var home: Array = lv["home"]
	b["home"] = int(home[1]) * w + int(home[0])
	for s: Array in lv["starts"]:
		(b["starts"] as Array).append([int(s[1]) * w + int(s[0]), int(s[2])])
	_cache[key] = b
	return b


static func cell_of(lv: Dictionary, x: int, y: int) -> int:
	return y * int(lv["w"]) + x


static func xy(lv: Dictionary, c: int) -> Vector2i:
	var w: int = int(lv["w"])
	return Vector2i(c % w, c / w)


## True where the player may put an arrow: plain floor (cracked floor too).
static func placeable(lv: Dictionary, c: int) -> bool:
	var b: Dictionary = board(lv)
	if c < 0 or c >= int(b["w"]) * int(b["h"]):
		return false
	if b["blocks"].has(c) or b["signs"].has(c) or b["spinners"].has(c) or b["bends"].has(c):
		return false
	if b["switches"].has(c) or b["gates"].has(c) or b["portals"].has(c) or b["dots"].has(c):
		return false
	if c == int(b["home"]):
		return false
	for s: Array in b["starts"]:
		if int(s[0]) == c:
			return false
	return true


## A fresh board, before the first tick.
static func initial_state(lv: Dictionary) -> Dictionary:
	var b: Dictionary = board(lv)
	var cells: Array = []
	var dirs: Array = []
	var status: Array = []
	for s: Array in b["starts"]:
		cells.append(int(s[0]))
		dirs.append(int(s[1]))
		status.append(0)
	return {"cells": cells, "dirs": dirs, "status": status, "got": 0, "nxt": 1,
		"spin": (b["spin0"] as Array).duplicate(), "flip": 0, "holes": 0, "tick": 0}


static func copy_state(s: Dictionary) -> Dictionary:
	return s.duplicate(true)


static func gate_open(lv: Dictionary, s: Dictionary, c: int) -> bool:
	var b: Dictionary = board(lv)
	return (int(b["gates"][c]) ^ int(s["flip"])) == 1


static func is_hole(lv: Dictionary, s: Dictionary, c: int) -> bool:
	var b: Dictionary = board(lv)
	return b["cracks"].has(c) and ((int(s["holes"]) >> int(b["cracks"][c])) & 1) == 1


static func dot_taken(s: Dictionary, index: int) -> bool:
	return ((int(s["got"]) >> index) & 1) == 1


static func dots_left(lv: Dictionary, s: Dictionary) -> int:
	var n: int = 0
	for i: int in (lv.get("dots", []) as Array).size():
		if not dot_taken(s, i):
			n += 1
	return n


## One tick. `arrows` maps cell -> direction. Appends what happened to `events`
## ({"type", "orb", "cell"}) and each orb's move to `moves` ({"from", "to", "via",
## "dir", "status"}). Returns "" while the run goes on, else how it ended.
static func tick(lv: Dictionary, s: Dictionary, arrows: Dictionary, events: Array, moves: Array) -> String:
	var b: Dictionary = board(lv)
	var w: int = int(b["w"])
	var h: int = int(b["h"])
	s["tick"] = int(s["tick"]) + 1
	var cells: Array = s["cells"]
	var dirs: Array = s["dirs"]
	var status: Array = s["status"]
	var n: int = cells.size()
	moves.clear()
	for i: int in n:
		moves.append({"from": int(cells[i]), "to": int(cells[i]), "via": -1, "dir": int(dirs[i]), "status": int(status[i]), "bump": -1})
	var movers: Array = []
	for i: int in n:
		if int(status[i]) == 0:
			movers.append(i)
	for i: int in movers:
		var c: int = cells[i]
		if b["cracks"].has(c) and not is_hole(lv, s, c):
			s["holes"] = int(s["holes"]) | (1 << int(b["cracks"][c]))
			events.append({"type": "crumble", "orb": i, "cell": c})
	var targets: Dictionary = {}
	var ended: String = ""
	for i: int in movers:
		var c: int = cells[i]
		var x: int = c % w + DX[int(dirs[i])]
		var y: int = c / w + DY[int(dirs[i])]
		if x < 0 or y < 0 or x >= w or y >= h:
			status[i] = 2
			ended = EDGE
			moves[i]["status"] = 2
			moves[i]["bump"] = -2
			events.append({"type": "edge", "orb": i, "cell": c})
			continue
		targets[i] = y * w + x
	if targets.size() > 1:
		var ids: Array = targets.keys()
		for a: int in ids.size():
			for k: int in range(a + 1, ids.size()):
				var i: int = ids[a]
				var j: int = ids[k]
				# Rolling into an open home together is fine; anywhere else it's a crash.
				var home_open: bool = int(targets[i]) == int(b["home"]) and int(s["got"]) == int(b["all_dots"])
				var together: bool = int(targets[i]) == int(targets[j]) and not home_open
				if together or (int(targets[i]) == int(cells[j]) and int(targets[j]) == int(cells[i])):
					status[i] = 2
					status[j] = 2
					moves[i]["status"] = 2
					moves[j]["status"] = 2
					moves[i]["bump"] = targets[i]
					moves[j]["bump"] = targets[j]
					ended = COLLIDE
					events.append({"type": "collide", "orb": i, "cell": int(targets[i])})
		for i: Variant in targets.keys():
			if int(status[i]) == 2:
				targets.erase(i)
	for i: int in movers:
		if not targets.has(i):
			continue
		var c: int = targets[i]
		var blocked: bool = b["blocks"].has(c)
		if not blocked and b["gates"].has(c):
			blocked = not gate_open(lv, s, c)
		if not blocked and is_hole(lv, s, c):
			blocked = true
		if blocked:
			status[i] = 2
			moves[i]["status"] = 2
			moves[i]["bump"] = c
			if ended.is_empty():
				ended = CRASH
			events.append({"type": "crash", "orb": i, "cell": c})
			continue
		cells[i] = c
		moves[i]["to"] = c
		if b["portals"].has(c):
			moves[i]["via"] = c
			c = int(b["portals"][c])
			cells[i] = c
			moves[i]["to"] = c
			events.append({"type": "portal", "orb": i, "cell": c, "from": int(moves[i]["via"])})
		if b["dots"].has(c):
			var dot: Array = b["dots"][c]
			if not dot_taken(s, int(dot[0])) and (int(dot[1]) == 0 or int(dot[1]) == int(s["nxt"])):
				s["got"] = int(s["got"]) | (1 << int(dot[0]))
				if int(dot[1]) > 0:
					s["nxt"] = int(s["nxt"]) + 1
				events.append({"type": "dot", "orb": i, "cell": c, "index": int(dot[0])})
		if c == int(b["home"]) and int(s["got"]) == int(b["all_dots"]):
			status[i] = 1
			moves[i]["status"] = 1
			events.append({"type": "home", "orb": i, "cell": c})
			continue
		var d: int = dirs[i]
		if arrows.has(c):
			if int(arrows[c]) != d:
				events.append({"type": "arrow", "orb": i, "cell": c})
			d = int(arrows[c])
		elif b["signs"].has(c):
			if int(b["signs"][c]) != d:
				events.append({"type": "sign", "orb": i, "cell": c})
			d = int(b["signs"][c])
		elif b["spinners"].has(c):
			var k: int = b["spinners"][c]
			d = int(s["spin"][k])
			s["spin"][k] = (d + 1) % 4
			events.append({"type": "spinner", "orb": i, "cell": c, "index": k})
		elif b["bends"].has(c):
			d = int(BEND[int(b["bends"][c])][d])
			events.append({"type": "bend", "orb": i, "cell": c})
		dirs[i] = d
		moves[i]["dir"] = d
		if b["switches"].has(c):
			s["flip"] = int(s["flip"]) ^ 1
			events.append({"type": "switch", "orb": i, "cell": c})
	if 2 in status:
		return ended if not ended.is_empty() else CRASH
	var all_home: bool = true
	for st: Variant in status:
		if int(st) != 1:
			all_home = false
	return WIN if all_home else ""


static func _key(s: Dictionary) -> String:
	return "%s|%s|%s|%d|%d|%s|%d|%d" % [s["cells"], s["dirs"], s["status"], int(s["got"]), int(s["nxt"]), s["spin"], int(s["flip"]), int(s["holes"])]


## Plays a whole run. Returns {"result", "ticks", "frames", "events", "state"}:
## frames[t] is the list of orb moves during tick t + 1 (see `tick`), events carry
## the tick they happened on.
static func run(lv: Dictionary, arrows: Dictionary) -> Dictionary:
	var s: Dictionary = initial_state(lv)
	var seen: Dictionary = {_key(s): true}
	var frames: Array = []
	var events: Array = []
	var result: String = ""
	while true:
		var ev: Array = []
		var moves: Array = []
		result = tick(lv, s, arrows, ev, moves)
		for e: Dictionary in ev:
			e["t"] = int(s["tick"])
			events.append(e)
		frames.append(moves.duplicate(true))
		if not result.is_empty():
			break
		var k: String = _key(s)
		if seen.has(k) or int(s["tick"]) >= MAX_TICKS:
			result = LOOP
			events.append({"type": "loop", "orb": 0, "cell": int(s["cells"][0]), "t": int(s["tick"])})
			break
		seen[k] = true
	return {"result": result, "ticks": int(s["tick"]), "frames": frames, "events": events, "state": s}


## The stored solution as {cell: dir}.
static func solution_arrows(lv: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for a: Array in lv.get("solution", []):
		out[cell_of(lv, int(a[0]), int(a[1]))] = int(a[2])
	return out


## The guide while placing arrows: each orb's path (cells, starting at its start)
## until it has turned `turns` times, then `stub` cells more, or until it would
## crash or go home. Also says where each path ends and why.
static func preview(lv: Dictionary, arrows: Dictionary, turns: int, stub: int = 2) -> Array:
	var out: Array = []
	var s: Dictionary = initial_state(lv)
	var n: int = (s["cells"] as Array).size()
	var paths: Array = []
	var turned: Array = []
	var left: Array = []
	var ends: Array = []
	for i: int in n:
		paths.append([int(s["cells"][i])])
		turned.append(0)
		left.append(-1)
		ends.append("")
	for t: int in 160:
		var ev: Array = []
		var moves: Array = []
		var r: String = tick(lv, s, arrows, ev, moves)
		for i: int in n:
			if not ends[i].is_empty():
				continue
			var m: Dictionary = moves[i]
			if int(m["via"]) >= 0:
				(paths[i] as Array).append(-1 - int(m["via"]))
			if int(m["to"]) != int(m["from"]) or int(m["via"]) >= 0:
				(paths[i] as Array).append(int(m["to"]))
			if int(m["status"]) == 2:
				ends[i] = "crash"
				if int(m["bump"]) >= 0:
					(paths[i] as Array).append(-1000 - int(m["bump"]))
				continue
			if int(m["status"]) == 1:
				ends[i] = "home"
				continue
			if int(left[i]) > 0:
				left[i] = int(left[i]) - 1
				if int(left[i]) == 0:
					ends[i] = "more"
		for e: Dictionary in ev:
			var i2: int = int(e["orb"])
			if str(e["type"]) in ["arrow", "sign", "spinner", "bend"] and ends[i2].is_empty():
				turned[i2] = int(turned[i2]) + 1
				if int(turned[i2]) >= turns and int(left[i2]) < 0:
					left[i2] = stub
					if stub == 0:
						ends[i2] = "more"
		if not r.is_empty() and r != WIN:
			for i: int in n:
				if ends[i].is_empty():
					ends[i] = "crash" if r != COLLIDE else "collide"
			break
		var done: bool = true
		for i: int in n:
			if ends[i].is_empty():
				done = false
		if done or r == WIN:
			break
	for i: int in n:
		out.append({"cells": paths[i], "end": ends[i] if not str(ends[i]).is_empty() else "more"})
	return out
