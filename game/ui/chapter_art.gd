class_name ChapterArt
extends Control
## A looping mini-room that shows what a chapter is about: a tiny 6 x 3 level whose
## run plays out the chapter's one idea (a sign, a bend, a spinner, a portal...).
## The runs come from the real rules (RouteSim), so the art never lies. Used as the
## chapter card background and as the diagram in each chapter's tutorial card.

const STEP: float = 0.32
const HOLD: float = 1.3

## Each scene: a mini level and the arrows laid on it.
const SCENES: Dictionary = {
	"ch1": [{"w": 6, "h": 3, "starts": [[0, 2, 0]], "dots": [[1, 2], [3, 1]], "home": [5, 0]}, [[3, 2, 3], [3, 0, 0]]],
	"ch2": [{"w": 6, "h": 3, "starts": [[0, 0, 0]], "signs": [[2, 0, 1]], "dots": [[2, 1]], "home": [5, 2]}, [[2, 2, 0]]],
	"ch3": [{"w": 6, "h": 3, "starts": [[0, 2, 0]], "bends": [[3, 2, 0], [3, 0, 0]], "dots": [[1, 2], [3, 1]], "home": [5, 0]}, []],
	"ch4": [{"w": 6, "h": 3, "starts": [[0, 1, 0]], "switches": [[1, 1]], "gates": [[4, 1, 0]], "dots": [[2, 1]], "home": [5, 1]}, []],
	"ch5": [{"w": 6, "h": 3, "starts": [[0, 1, 0]], "spinners": [[2, 1, 3]], "dots": [[4, 1]], "home": [5, 1]}, [[2, 0, 1]]],
	"ch6": [{"w": 6, "h": 3, "starts": [[0, 2, 0]], "portals": [[2, 2, 3, 0]], "dots": [[1, 2], [4, 0]], "home": [5, 0]}, []],
	"ch7": [{"w": 6, "h": 3, "starts": [[0, 0, 0]], "cracks": [[1, 0], [2, 0], [3, 1]], "dots": [[2, 2]], "home": [1, 2]}, [[3, 0, 1], [3, 2, 2]]],
	"ch8": [{"w": 6, "h": 3, "starts": [[0, 1, 0]], "dots": [[1, 1, 2], [3, 1, 1]], "home": [3, 2]}, [[4, 1, 3], [4, 0, 2], [1, 0, 1], [1, 2, 0]]],
	"ch9": [{"w": 6, "h": 3, "starts": [[0, 0, 0], [3, 2, 3]], "dots": [[4, 0]], "home": [5, 0]}, [[3, 0, 0]]],
}

var chapter_id: String = "ch1"
var pal: Dictionary = Palette.get_palette("ch1")
## Where to draw, in local pixels. Empty = the full control.
var area: Rect2 = Rect2()
var playing: bool = true
var line_scale: float = 1.0
var _t: float = 0.0
var _lv: Dictionary = {}
var _arrows: Dictionary = {}
var _states: Array = []
var _frames: Array = []
var _s: float = 10.0
var _o: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scene: Array = SCENES.get(chapter_id, SCENES["ch1"])
	_lv = scene[0]
	for a: Array in scene[1]:
		_arrows[RouteSim.cell_of(_lv, int(a[0]), int(a[1]))] = int(a[2])
	# Every tick's board, so drawing any moment is a lookup.
	var s: Dictionary = RouteSim.initial_state(_lv)
	_states.append(RouteSim.copy_state(s))
	for t: int in 40:
		var ev: Array = []
		var moves: Array = []
		var r: String = RouteSim.tick(_lv, s, _arrows, ev, moves)
		_frames.append(moves.duplicate(true))
		_states.append(RouteSim.copy_state(s))
		if not r.is_empty():
			break
	_t = randf() * _period()


func _period() -> float:
	return float(_frames.size()) * STEP + HOLD


func _process(delta: float) -> void:
	if playing and is_visible_in_tree():
		_t += delta
		queue_redraw()


func _c(c: int) -> Vector2:
	var p: Vector2i = RouteSim.xy(_lv, c)
	return _o + (Vector2(p) + Vector2(0.5, 0.5)) * _s


func _draw() -> void:
	if _lv.is_empty():
		return
	var r: Rect2 = area if area.size != Vector2.ZERO else Rect2(Vector2.ZERO, size)
	var w: float = float(_lv["w"])
	var h: float = float(_lv["h"])
	_s = minf(r.size.x / w, r.size.y / h)
	_o = r.position + (r.size - Vector2(w, h) * _s) * 0.5
	var u: float = fmod(_t, _period())
	var k: int = mini(int(u / STEP), _frames.size())
	var frac: float = clampf(u / STEP - float(k), 0.0, 1.0)
	var alpha: float = clampf(u / 0.25, 0.0, 1.0) * clampf((_period() - u) / 0.3, 0.0, 1.0)
	# The board as it stands after the ticks already rolled.
	var st: Dictionary = _states[mini(k, _states.size() - 1)]
	var b: Dictionary = RouteSim.board(_lv)
	var ink: Color = pal["ink"]
	var lw: float = maxf(1.5, _s * 0.07) * line_scale
	for c: int in int(w * h):
		draw_circle(_c(c), maxf(1.0, _s * 0.035), Color(ink, 0.18 * alpha), true, -1.0, true)
	# The path so far, dotted.
	for t: int in mini(k, _frames.size()):
		for m: Dictionary in _frames[t]:
			if int(m["to"]) != int(m["from"]) and int(m["via"]) < 0:
				_dots(_c(int(m["from"])), _c(int(m["to"])), Color(ink, 0.3 * alpha))
	for c: Variant in b["cracks"]:
		var rr: Rect2 = Rect2(_c(int(c)) - Vector2(_s, _s) * 0.4, Vector2(_s, _s) * 0.8)
		if RouteSim.is_hole(_lv, st, int(c)):
			draw_rect(rr, Color(ink, 0.8 * alpha))
		else:
			draw_rect(rr, Color(ink, 0.3 * alpha), false, maxf(1.0, lw * 0.5))
			draw_line(rr.position + rr.size * Vector2(0.2, 0.3), rr.position + rr.size * Vector2(0.8, 0.7), Color(ink, 0.35 * alpha), maxf(1.0, lw * 0.5), true)
	for c: Variant in b["gates"]:
		var rr2: Rect2 = Rect2(_c(int(c)) - Vector2(_s, _s) * 0.4, Vector2(_s, _s) * 0.8)
		var open: bool = RouteSim.gate_open(_lv, st, int(c))
		draw_rect(rr2, Color(pal["special"], (0.15 if open else 0.45) * alpha))
		draw_rect(rr2, Color(pal["special"], (0.4 if open else 0.95) * alpha), false, maxf(1.0, lw * 0.6))
	for c: Variant in b["switches"]:
		var p: Vector2 = _c(int(c))
		var q: float = _s * 0.22
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0)]), Color(pal["special"], alpha))
	for p4: Array in _lv.get("portals", []):
		for side: int in 2:
			var pp: Vector2 = _c(RouteSim.cell_of(_lv, int(p4[side * 2]), int(p4[side * 2 + 1])))
			draw_arc(pp, _s * 0.3, 0.0, TAU, 28, Color(pal["special"], alpha), lw, true)
			draw_circle(pp, _s * 0.08, Color(pal["special"], alpha), true, -1.0, true)
	for c: Variant in b["bends"]:
		var p2: Vector2 = _c(int(c))
		var hh: float = _s * 0.32
		var kind: int = int(b["bends"][c])
		var a0: Vector2 = p2 + (Vector2(-hh, hh) if kind == 0 else Vector2(-hh, -hh))
		var a1: Vector2 = p2 + (Vector2(hh, -hh) if kind == 0 else Vector2(hh, hh))
		draw_line(a0, a1, Color(pal["wall"], alpha), lw * 1.3, true)
	for c: Variant in b["signs"]:
		_chevron(_c(int(c)), int(b["signs"][c]) * 90.0, Color(ink, 0.9 * alpha), lw)
	for c: Variant in b["spinners"]:
		var i: int = int(b["spinners"][c])
		draw_arc(_c(int(c)), _s * 0.38, 0.0, TAU, 28, Color(pal["special"], 0.8 * alpha), maxf(1.0, lw * 0.6), true)
		_chevron(_c(int(c)), int(st["spin"][i]) * 90.0, Color(pal["special"], alpha), lw)
	for c: Variant in _arrows:
		var ar: Rect2 = Rect2(_c(int(c)) - Vector2(_s, _s) * 0.4, Vector2(_s, _s) * 0.8)
		draw_rect(ar, Color(pal["accent"], 0.2 * alpha))
		_chevron(_c(int(c)), int(_arrows[c]) * 90.0, Color(pal["accent"], alpha), lw)
	var dots: Array = _lv.get("dots", [])
	for i2: int in dots.size():
		var d: Array = dots[i2]
		var dp: Vector2 = _c(RouteSim.cell_of(_lv, int(d[0]), int(d[1])))
		if RouteSim.dot_taken(st, i2):
			draw_circle(dp, _s * 0.06, Color(pal["target"], 0.35 * alpha), true, -1.0, true)
			continue
		draw_circle(dp, _s * (0.24 if d.size() > 2 else 0.19), Color(pal["target"], alpha), true, -1.0, true)
		if d.size() > 2:
			var f: Font = UIKit.font(700)
			var fs: int = maxi(8, int(_s * 0.3))
			var txt: String = str(int(d[2]))
			var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(f, dp + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(pal["top"], alpha))
	var home: Vector2 = _c(int(b["home"]))
	var open_home: bool = RouteSim.dots_left(_lv, st) == 0
	draw_arc(home, _s * 0.32, 0.0, TAU, 32, Color(ink, (0.9 if open_home else 0.35) * alpha), lw * 0.8, true)
	draw_circle(home, _s * 0.08, Color(ink, (0.9 if open_home else 0.35) * alpha), true, -1.0, true)
	for s0: Array in b["starts"]:
		draw_arc(_c(int(s0[0])), _s * 0.3, 0.0, TAU, 28, Color(ink, 0.8 * alpha), maxf(1.0, lw * 0.7), true)
	# The orbs on their move.
	for i3: int in (st["cells"] as Array).size():
		var pos: Vector2 = _c(int(_states[0]["cells"][i3]))
		var home_now: bool = false
		if k < _frames.size():
			var m2: Dictionary = _frames[k][i3]
			var from: Vector2 = _c(int(m2["from"]))
			if int(m2["via"]) >= 0:
				pos = from.lerp(_c(int(m2["via"])), frac * 2.0) if frac < 0.5 else _c(int(m2["to"]))
			else:
				pos = from.lerp(_c(int(m2["to"])), frac)
			home_now = int(m2["status"]) == 1 and int(m2["from"]) == int(m2["to"])
		else:
			home_now = true
		if home_now:
			continue
		draw_circle(pos, _s * 0.3, Color(pal["orb"], 0.12 * alpha), true, -1.0, true)
		draw_circle(pos, _s * 0.17, Color(pal["orb"], alpha), true, -1.0, true)
	if k >= _frames.size():
		var kk: float = clampf((u - float(_frames.size()) * STEP) / 0.5, 0.0, 1.0)
		draw_arc(home, _s * (0.3 + 0.5 * kk), 0.0, TAU, 32, Color(pal["accent"], (1.0 - kk) * alpha), lw, true)


func _chevron(p: Vector2, deg: float, col: Color, width: float) -> void:
	var fwd: Vector2 = Vector2.from_angle(deg_to_rad(deg))
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var sz: float = _s * 0.36
	var tip: Vector2 = p + fwd * sz
	draw_line(p - fwd * sz, tip, col, width, true)
	draw_polyline(PackedVector2Array([tip - fwd * sz * 0.6 + side * sz * 0.6, tip, tip - fwd * sz * 0.6 - side * sz * 0.6]), col, width, true)


func _dots(a: Vector2, b: Vector2, col: Color) -> void:
	var n: int = 4
	for i: int in n:
		draw_circle(a.lerp(b, (float(i) + 0.5) / float(n)), maxf(1.0, _s * 0.04), col, true, -1.0, true)
