class_name Board
extends Control
## The play field: draws the room on its dot grid, lets the player lay arrows
## (tap a cell, tap again to turn it, or swipe the way it should point), shows the
## guide, plays the run back from the deterministic simulation, and layers on the
## feedback (rings, particles, shake, pitched dots, slow motion going home).

signal run_started
signal run_finished(won: bool)
signal arrows_changed(left: int)
## The player touched the board to lay or turn an arrow.
signal edit_started
## Tapped with no arrows left.
signal out_of_arrows

## Seconds per cell at the start of a run, and the quickest it gets.
const TICK_SLOW: float = 0.2
const TICK_FAST: float = 0.12
const SWIPE: float = 0.32

var pal: Dictionary = Palette.get_palette("ch1")
var level: Dictionary = {}
var demo: bool = false
var quiet: bool = false
var input_enabled: bool = true
## Orb look from the shop's Orb pack (see OrbStyles).
var orb_style: String = "classic"
## Playing a won run again for the player to watch: no input, no result.
var replaying: bool = false

## The player's arrows: cell -> direction.
var arrows: Dictionary = {}
## Cells in the order they were laid (undo / the hand in the tutorial).
var _order: Array = []

# Layout (pixels).
var cell_size: float = 64.0
var view_offset: Vector2 = Vector2.ZERO
var _shake: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _clock: float = 0.0

# Playback.
var playing: bool = false
var last_result: Dictionary = {}
var _run: Dictionary = {}
var _live: Dictionary = {}
var _tick_i: int = 0
var _tick_t: float = 0.0
var _tick_len: float = TICK_SLOW
var _moves: Array = []
var _pending: Array = []
var _settle: float = -1.0
var _slowmo: float = 0.0
var _rate: float = 1.0
var _fast: float = 1.0
var _combo: int = 0
var _trails: Array = []
var _orb_pos: Array = []
var _shown: Dictionary = {}

# Effects.
var _particles: Array = []
var _rings: Array = []
var _flash: Dictionary = {}
var _pops: Dictionary = {}
var _placed_t: Dictionary = {}
var _spin_shown: Array = []
var _gate_shown: Dictionary = {}
var _home_open: float = 0.0
var _screen_flash: float = 0.0
var _kick: float = 0.0
var _deny: Dictionary = {}
var _intro: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Guides.
var _preview: Array = []
var _preview_dirty: bool = true
var _hint: Dictionary = {}
var _hint_t: float = 0.0
## The path of the last missed run, kept faintly visible so the next try can adjust.
var _ghost: Array = []
var _ghost_end: Array = []
## A solid path drawn over the room (the share card shows the winning run).
var _path: Array = []
## Cells to ring softly (a chapter's new element, the tutorial's target cell).
var spotlight: Array = []

# Input.
var _press_cell: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _swiped: bool = false
var cursor: int = -1

# Demo / attract mode.
var _demo_step: int = 0
var _demo_wait: float = 1.0


func _ready() -> void:
	Events.setting_changed.connect(func(key: String, _v: Variant) -> void:
		if key == "orb_style" and not demo:
			orb_style = SaveSystem.orb_style()
		if key == "long_guide":
			_preview_dirty = true
	)
	Events.purchases_changed.connect(func() -> void:
		if not demo:
			orb_style = SaveSystem.orb_style()
	)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(_layout)
	_rng.randomize()
	_layout()


func setup(level_data: Dictionary, palette: Dictionary) -> void:
	level = level_data
	pal = palette
	orb_style = SaveSystem.orb_style() if not demo else "classic"
	_layout()
	reset()


## A fresh room: no arrows, no trace of an earlier miss.
func reset() -> void:
	arrows.clear()
	_order.clear()
	_placed_t.clear()
	_ghost = []
	_ghost_end = []
	_hint = {}
	_hint_t = 0.0
	_intro = 0.0
	replaying = false
	_restore()
	arrows_changed.emit(arrows_left())


## Back to the start for the next try: arrows and the missed path stay.
func retry() -> void:
	_restore()


func _restore() -> void:
	_stop_playback()
	_live = RouteSim.initial_state(level) if not level.is_empty() else {}
	_particles.clear()
	_rings.clear()
	_pops.clear()
	_shown.clear()
	_orb_pos.clear()
	if not _live.is_empty():
		for c: Variant in _live["cells"]:
			_orb_pos.append(center(int(c)))
		_spin_shown.clear()
		for d: Variant in _live["spin"]:
			_spin_shown.append(float(d) * 90.0)
		_gate_shown.clear()
		var b: Dictionary = RouteSim.board(level)
		for g: Variant in b["gates"]:
			_gate_shown[g] = 1.0 if RouteSim.gate_open(level, _live, int(g)) else 0.0
	_home_open = 1.0 if (level.get("dots", []) as Array).is_empty() else 0.0
	_preview_dirty = true
	queue_redraw()


func _stop_playback() -> void:
	playing = false
	_run = {}
	_settle = -1.0
	_slowmo = 0.0
	_rate = 1.0
	_fast = 1.0
	_trails.clear()
	_pending.clear()


func turns() -> int:
	return int(level.get("turns", 0))


func arrows_left() -> int:
	return turns() - arrows.size()


# --- Layout ------------------------------------------------------------------

func _layout() -> void:
	if level.is_empty():
		return
	var w: float = float(level["w"])
	var h: float = float(level["h"])
	# A little room around the grid for the card's edge.
	cell_size = floorf(minf(size.x / (w + 0.6), size.y / (h + 0.6)))
	cell_size = maxf(cell_size, 8.0)
	view_offset = ((size - Vector2(w, h) * cell_size) * 0.5).floor()
	_preview_dirty = true
	if not _live.is_empty() and not playing:
		_orb_pos.clear()
		for c: Variant in _live["cells"]:
			_orb_pos.append(center(int(c)))
	queue_redraw()


## Pixel centre of a cell.
func center(c: int) -> Vector2:
	var p: Vector2i = RouteSim.xy(level, c)
	return view_offset + (Vector2(p) + Vector2(0.5, 0.5)) * cell_size


func cell_rect(c: int) -> Rect2:
	var p: Vector2i = RouteSim.xy(level, c)
	return Rect2(view_offset + Vector2(p) * cell_size, Vector2(cell_size, cell_size))


func cell_at(pos: Vector2) -> int:
	var g: Vector2 = (pos - view_offset) / cell_size
	var x: int = floori(g.x)
	var y: int = floori(g.y)
	if x < 0 or y < 0 or x >= int(level["w"]) or y >= int(level["h"]):
		return -1
	return y * int(level["w"]) + x


func grid_rect() -> Rect2:
	return Rect2(view_offset, Vector2(float(level["w"]), float(level["h"])) * cell_size)


# --- Input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if playing and event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not demo:
		fast_forward()
		accept_event()
		return
	if demo or playing or replaying or not input_enabled or level.is_empty():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			_press_cell = cell_at(mb.position)
			_press_pos = mb.position
			_swiped = false
			if _press_cell >= 0:
				edit_started.emit()
		elif _press_cell >= 0:
			if not _swiped:
				tap_cell(_press_cell)
			_press_cell = -1
		accept_event()
	elif event is InputEventMouseMotion and _press_cell >= 0 and not _swiped:
		var d: Vector2 = (event as InputEventMouseMotion).position - _press_pos
		if d.length() > cell_size * SWIPE:
			_swiped = true
			var dir: int = 0
			if absf(d.x) > absf(d.y):
				dir = 0 if d.x > 0.0 else 2
			else:
				dir = 1 if d.y > 0.0 else 3
			point_cell(_press_cell, dir)
		accept_event()


## A tap: lays an arrow (pointing where the orb would turn), turns it a quarter,
## and after four turns takes it away again.
func tap_cell(c: int) -> void:
	if not RouteSim.placeable(level, c):
		_deny_cell(c)
		return
	if arrows.has(c):
		var first: int = int(_placed_t.get(c, {}).get("first", arrows[c]))
		var nd: int = (int(arrows[c]) + 1) % 4
		if nd == first:
			remove_arrow(c)
		else:
			_set_arrow(c, nd)
		return
	if arrows_left() <= 0:
		_deny_cell(c)
		out_of_arrows.emit()
		return
	_set_arrow(c, _default_dir(c))


## A swipe: lays (or re-aims) the arrow on this cell to point `dir`.
func point_cell(c: int, dir: int) -> void:
	if not RouteSim.placeable(level, c):
		_deny_cell(c)
		return
	if not arrows.has(c) and arrows_left() <= 0:
		_deny_cell(c)
		out_of_arrows.emit()
		return
	_set_arrow(c, dir)


func remove_arrow(c: int) -> void:
	if not arrows.has(c):
		return
	arrows.erase(c)
	_order.erase(c)
	_placed_t.erase(c)
	_sound("ui_back", 1.1, -4.0)
	_haptic(6)
	_add_ring(center(c), cell_size * 0.32, cell_size * 0.1, 0.25, Color(pal["accent"], 0.7), 3.0)
	_after_edit()


func clear_arrows() -> void:
	arrows.clear()
	_order.clear()
	_placed_t.clear()
	_after_edit()


func _set_arrow(c: int, dir: int) -> void:
	var fresh: bool = not arrows.has(c)
	arrows[c] = dir
	if fresh:
		_order.append(c)
		_placed_t[c] = {"t": 0.0, "first": dir, "spin": 0.0}
		_sound("aim_tick", 1.0, -2.0)
		_add_ring(center(c), cell_size * 0.12, cell_size * 0.5, 0.3, pal["accent"], 3.0)
	else:
		var rec: Dictionary = _placed_t[c]
		rec["t"] = 0.35
		_sound("aim_tick", 1.25, -4.0)
	_haptic(8)
	_after_edit()


func _after_edit() -> void:
	_preview_dirty = true
	arrows_changed.emit(arrows_left())
	queue_redraw()


## The new arrow points the way the orb would turn there: clockwise from the way
## the guide crosses this cell (or up, off the guide).
func _default_dir(c: int) -> int:
	var path: Array = RouteSim.preview(level, arrows, 99, 0)
	for p: Dictionary in path:
		var cells: Array = p["cells"]
		for k: int in range(1, cells.size()):
			if int(cells[k]) == c and int(cells[k - 1]) >= 0:
				var a: Vector2i = RouteSim.xy(level, int(cells[k - 1]))
				var b: Vector2i = RouteSim.xy(level, c)
				var step: Vector2i = b - a
				for d: int in 4:
					if RouteSim.dir_vec(d) == step:
						return (d + 1) % 4
	return 3


func _deny_cell(c: int) -> void:
	_deny[c] = 1.0
	_sound("ui_back", 0.8, -6.0)
	_haptic(10)


## Keyboard / gamepad: move a cursor over the cells.
func move_cursor(dx: int, dy: int) -> void:
	if level.is_empty():
		return
	var w: int = int(level["w"])
	var h: int = int(level["h"])
	if cursor < 0:
		cursor = RouteSim.board(level)["starts"][0][0]
	var p: Vector2i = RouteSim.xy(level, cursor)
	p.x = clampi(p.x + dx, 0, w - 1)
	p.y = clampi(p.y + dy, 0, h - 1)
	cursor = p.y * w + p.x
	_sound("aim_tick", 1.4, -10.0)
	queue_redraw()


# --- Runs ----------------------------------------------------------------------

## Rolls the orb with the arrows as they are.
func go() -> void:
	if playing or level.is_empty():
		return
	_restore()
	_run = RouteSim.run(level, arrows)
	last_result = _run
	_live = RouteSim.initial_state(level)
	_tick_i = 0
	_tick_t = 0.0
	_tick_len = TICK_SLOW
	_moves = _next_moves()
	_ghost = []
	_ghost_end = []
	_hint_t = 0.0
	_combo = 0
	_fast = 1.0
	playing = true
	_trails.clear()
	for i: int in _orb_pos.size():
		_trails.append([])
	_kick = 1.0
	_add_trauma(0.06)
	_sound("launch")
	_haptic(8)
	for c: Variant in _live["cells"]:
		_add_ring(center(int(c)), cell_size * 0.2, cell_size * 0.55, 0.3, pal["orb"], 3.0)
	run_started.emit()


## Plays the given arrows again from a fresh room so the player can watch.
func replay(with_arrows: Dictionary) -> void:
	arrows = with_arrows.duplicate()
	_ghost = []
	_ghost_end = []
	replaying = true
	go()


func fast_forward() -> void:
	if playing:
		_fast = 3.0


func _next_moves() -> Array:
	var ev: Array = []
	var moves: Array = []
	RouteSim.tick(level, _live, arrows, ev, moves)
	_pending = ev
	return moves


func _process(delta: float) -> void:
	_clock += delta
	_intro = minf(1.0, _intro + delta * 2.4)
	if playing:
		_advance(delta)
	elif demo:
		_demo_tick(delta)
	_update_fx(delta)
	queue_redraw()


func _advance(delta: float) -> void:
	if _slowmo > 0.0:
		_slowmo -= delta
		_rate = lerpf(_rate, 0.25, minf(1.0, delta * 16.0))
	else:
		_rate = lerpf(_rate, 1.0, minf(1.0, delta * 5.0))
	if _settle >= 0.0:
		_settle += delta
		for tr: Array in _trails:
			if not tr.is_empty():
				tr.pop_front()
		if _settle >= 0.45:
			_finish_run()
		return
	_tick_t += delta * _rate * _fast / _tick_len
	# Crashes land mid-move (the orb bumps and springs back).
	if _tick_t >= 0.4:
		_fire_events(["crash", "edge", "collide"])
	while _tick_t >= 1.0:
		_tick_t -= 1.0
		_fire_events([])
		_tick_i += 1
		if _tick_i >= int(_run["ticks"]):
			_tick_t = 1.0
			_settle = 0.0
			if str(_run["result"]) == RouteSim.LOOP:
				_on_loop()
			break
		_tick_len = maxf(TICK_FAST, _tick_len * 0.97)
		_moves = _next_moves()
	_place_orbs()


## Where each orb is drawn this frame, on its move from one cell to the next.
func _place_orbs() -> void:
	var k: float = clampf(_tick_t, 0.0, 1.0)
	for i: int in _moves.size():
		var m: Dictionary = _moves[i]
		var from: Vector2 = center(int(m["from"]))
		var p: Vector2 = from
		if int(m["bump"]) != -1:
			# Rolls into the obstacle and springs back.
			var dirv: Vector2 = Vector2(RouteSim.dir_vec(int(m["dir"])))
			if int(m["bump"]) >= 0:
				dirv = (center(int(m["bump"])) - from).normalized()
			var b: float = sin(minf(k, 0.8) / 0.8 * PI) * 0.42
			p = from + dirv * cell_size * b
		elif int(m["via"]) >= 0:
			if k < 0.5:
				p = from.lerp(center(int(m["via"])), k * 2.0)
			else:
				p = center(int(m["to"]))
		elif int(m["to"]) != int(m["from"]):
			p = from.lerp(center(int(m["to"])), k)
		if i < _orb_pos.size():
			_orb_pos[i] = p
		if i < _trails.size():
			var tr: Array = _trails[i]
			if int(m["via"]) >= 0 and k >= 0.5 and not tr.is_empty() and (tr[-1] as Vector2).distance_to(p) > cell_size:
				tr.clear()
			if int(m["status"]) == 1 and _tick_t >= 1.0:
				if not tr.is_empty():
					tr.pop_front()
			else:
				tr.append(p)
			if tr.size() > OrbStyles.trail_length(orb_style):
				tr.pop_front()


## Applies the current tick's events (only those of `types`, or all if empty).
func _fire_events(types: Array) -> void:
	var keep: Array = []
	for e: Dictionary in _pending:
		if types.is_empty() or str(e["type"]) in types:
			_apply_event(e)
		else:
			keep.append(e)
	_pending = keep


func _apply_event(e: Dictionary) -> void:
	var c: int = int(e["cell"])
	var pos: Vector2 = center(c)
	match str(e["type"]):
		"arrow", "sign":
			_flash[c] = 1.0
			_add_ring(pos, cell_size * 0.15, cell_size * 0.5, 0.3, Color(pal["ink"], 0.5), 3.0)
			_sound("bounce", 1.0 + 0.04 * float(_combo % 5))
			_add_trauma(0.04)
			_haptic(5)
		"bend":
			_flash[c] = 1.0
			_add_ring(pos, cell_size * 0.15, cell_size * 0.45, 0.3, Color(pal["ink"], 0.5), 3.0)
			_burst(pos, 4, Color(pal["ink"], 0.6), cell_size * 1.2, 2.5)
			_sound("bounce")
			_add_trauma(0.05)
			_haptic(5)
		"spinner":
			_flash[c] = 1.0
			_add_ring(pos, cell_size * 0.15, cell_size * 0.5, 0.35, pal["special"], 3.5)
			_sound("bounce")
			_sound("undo", 1.4, -6.0)
			_add_trauma(0.06)
			_haptic(8)
		"dot":
			var idx: int = int(e.get("index", 0))
			_shown["dot%d" % idx] = true
			_pops[idx] = 0.0
			_add_ring(pos, cell_size * 0.2, cell_size * 0.75, 0.55, pal["target"], 5.0)
			_burst(pos, 14, pal["target"], cell_size * 3.2, 4.5)
			if not quiet:
				AudioManager.play_note("pop", _combo)
			_combo += 1
			_add_trauma(0.18)
			_haptic(14)
			if RouteSim.dots_left(level, _live) == 0:
				_open_home()
		"home":
			var hp: Vector2 = center(c)
			_add_ring(hp, cell_size * 0.2, cell_size * 1.1, 0.6, pal["accent"], 6.0)
			_burst(hp, 18, pal["accent"], cell_size * 3.6, 5.0)
			_sound("star", 1.5, -4.0)
			_haptic(24)
			var all_home: bool = true
			for st: Variant in _live["status"]:
				if int(st) != 1:
					all_home = false
			if all_home:
				_slowmo = 0.4
				_screen_flash = 1.0
				_add_trauma(0.3)
		"portal":
			var p2: Vector2 = center(c)
			_add_ring(center(int(e.get("from", c))), cell_size * 0.5, cell_size * 0.08, 0.3, pal["special"], 4.0)
			_add_ring(p2, cell_size * 0.08, cell_size * 0.6, 0.4, pal["special"], 4.0)
			_sound("portal")
			_haptic(8)
		"switch":
			_add_ring(pos, cell_size * 0.15, cell_size * 0.9, 0.5, pal["special"], 5.0)
			_burst(pos, 10, pal["special"], cell_size * 2.6, 3.5)
			_sound("unlock", 1.0, -3.0)
			_add_trauma(0.1)
			_haptic(12)
		"crumble":
			_shown["hole%d" % c] = true
			var r: Rect2 = cell_rect(c)
			for i: int in 14:
				var p: Vector2 = r.position + Vector2(_rng.randf(), _rng.randf()) * r.size
				var life: float = _rng.randf_range(0.4, 0.8)
				_particles.append({"p": p, "v": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(20, 90) + Vector2(0, 60), "life": life, "max": life, "c": Color(pal["ink"], 0.7), "r": _rng.randf_range(2.5, 5.0), "shard": true, "rot": _rng.randf() * TAU})
			_sound("glass_break", 0.8, -8.0)
			_haptic(6)
		"crash", "edge", "collide":
			var at: Vector2 = _orb_pos[int(e["orb"])] if int(e["orb"]) < _orb_pos.size() else pos
			_add_ring(at, cell_size * 0.1, cell_size * 0.6, 0.4, pal["target"], 5.0)
			_burst(at, 10, Color(pal["orb"], 0.8), cell_size * 2.0, 3.0)
			if c >= 0 and str(e["type"]) == "crash":
				_flash[c] = 1.0
			_sound("absorb", 1.0, -2.0)
			_add_trauma(0.3)
			_haptic(24)


func _open_home() -> void:
	var hp: Vector2 = center(int(RouteSim.board(level)["home"]))
	_add_ring(hp, cell_size * 0.15, cell_size * 0.8, 0.5, pal["accent"], 4.0)
	_sound("unlock", 1.3, -8.0)


func _on_loop() -> void:
	for p: Vector2 in _orb_pos:
		_add_ring(p, cell_size * 0.5, cell_size * 0.1, 0.4, pal["target"], 4.0)
	_sound("fizzle", -1.0, -4.0)
	_add_trauma(0.15)
	_haptic(16)


func _finish_run() -> void:
	var won: bool = str(_run.get("result", "")) == RouteSim.WIN
	var was_replay: bool = replaying
	if not won:
		_remember_miss(_run)
	playing = false
	_settle = -1.0
	_trails.clear()
	replaying = false
	if not was_replay:
		run_finished.emit(won)


func _remember_miss(res: Dictionary) -> void:
	_ghost = []
	_ghost_end = []
	var paths: Array = []
	var s: Dictionary = RouteSim.initial_state(level)
	for c: Variant in s["cells"]:
		paths.append([center(int(c))])
	for moves: Array in res["frames"]:
		for i: int in moves.size():
			var m: Dictionary = moves[i]
			var pts: Array = paths[i]
			if int(m["bump"]) != -1:
				var from: Vector2 = center(int(m["from"]))
				var dirv: Vector2 = Vector2(RouteSim.dir_vec(int(m["dir"])))
				if int(m["bump"]) >= 0:
					dirv = (center(int(m["bump"])) - from).normalized()
				var hit: Vector2 = from + dirv * cell_size * 0.42
				pts.append(hit)
				_ghost_end.append(hit)
			elif int(m["via"]) >= 0:
				pts.append(center(int(m["via"])))
				_ghost.append(pts.duplicate())
				pts.clear()
				pts.append(center(int(m["to"])))
			elif int(m["to"]) != int(m["from"]):
				pts.append(center(int(m["to"])))
	for pts: Array in paths:
		if pts.size() >= 2:
			_ghost.append(pts)
	if str(res["result"]) == RouteSim.LOOP:
		for i: int in (res["state"]["cells"] as Array).size():
			_ghost_end.append(center(int(res["state"]["cells"][i])))


## Why the last run failed, in a few words.
func miss_reason() -> String:
	if last_result.is_empty():
		return ""
	var st: Dictionary = last_result["state"]
	var left: int = RouteSim.dots_left(level, st)
	var dots: String = ("1 dot left" if left == 1 else "%d dots left" % left) if left > 0 else "every dot taken"
	match str(last_result["result"]):
		RouteSim.EDGE:
			return "Rolled off the board  ·  " + dots
		RouteSim.COLLIDE:
			return "The orbs ran into each other  ·  " + dots
		RouteSim.LOOP:
			return "Going round in circles  ·  " + dots
	for e: Dictionary in last_result["events"]:
		if str(e["type"]) == "crash":
			var c: int = int(e["cell"])
			if RouteSim.board(level)["gates"].has(c):
				return "The gate was shut  ·  " + dots
			if RouteSim.board(level)["cracks"].has(c):
				return "Fell through the crack  ·  " + dots
	return "Hit a block  ·  " + dots


# --- Hints and paths -------------------------------------------------------------

## Shows where the solution's arrows go, and the path they make. It stays until the
## next run. Returns false if the room has no stored solution.
func show_hint() -> bool:
	if playing or level.is_empty():
		return false
	var sol: Dictionary = RouteSim.solution_arrows(level)
	if sol.is_empty() and turns() > 0:
		return false
	_hint = {"arrows": sol, "path": _path_points(sol)}
	_hint_t = 9999.0
	_ghost = []
	_ghost_end = []
	_sound("hint")
	return true


func hint_showing() -> bool:
	return not _hint.is_empty() and _hint_t > 0.0


## Lays the solution's arrows (the hint's "do it for me", the demo and the tutorial).
func place_solution() -> void:
	clear_arrows()
	for c: Variant in RouteSim.solution_arrows(level):
		_set_arrow(int(c), int(RouteSim.solution_arrows(level)[c]))


## Draws the run that `with_arrows` makes, solid, over the room (share card).
func show_path(with_arrows: Dictionary) -> void:
	_intro = 1.0
	arrows = with_arrows.duplicate()
	_path = _path_points(with_arrows)
	queue_redraw()


func _path_points(with_arrows: Dictionary) -> Array:
	var res: Dictionary = RouteSim.run(level, with_arrows)
	var out: Array = []
	var s: Dictionary = RouteSim.initial_state(level)
	var paths: Array = []
	for c: Variant in s["cells"]:
		paths.append([center(int(c))])
	for moves: Array in res["frames"]:
		for i: int in moves.size():
			var m: Dictionary = moves[i]
			var pts: Array = paths[i]
			if int(m["via"]) >= 0:
				pts.append(center(int(m["via"])))
				out.append(pts.duplicate())
				pts.clear()
				pts.append(center(int(m["to"])))
			elif int(m["to"]) != int(m["from"]) and int(m["bump"]) == -1:
				pts.append(center(int(m["to"])))
	for pts: Array in paths:
		if pts.size() >= 2:
			out.append(pts)
	return out


# --- Demo / attract mode ---------------------------------------------------------

func _demo_tick(delta: float) -> void:
	_demo_wait -= delta
	if _demo_wait > 0.0:
		return
	var sol: Dictionary = RouteSim.solution_arrows(level)
	var cells: Array = sol.keys()
	if _demo_step < cells.size():
		var c: int = cells[_demo_step]
		if not arrows.has(c):
			_set_arrow(c, int(sol[c]))
		_demo_step += 1
		_demo_wait = 0.45
		return
	if _demo_step == cells.size():
		_demo_step += 1
		go()
		_demo_wait = 0.0
		return
	# Run over: hold the finished board a moment, then start again.
	_demo_step = 0
	_demo_wait = 1.2
	reset()


# --- Effects ---------------------------------------------------------------------

func _sound(id: String, pitch: float = -1.0, db: float = 0.0) -> void:
	if not quiet:
		AudioManager.play(id, pitch, db)


func _haptic(ms: int) -> void:
	if not quiet:
		Haptics.tap(ms)


func _add_trauma(amount: float) -> void:
	if quiet or not bool(SaveSystem.get_setting("shake", true)):
		return
	_trauma = minf(1.0, _trauma + amount)


func _add_ring(p: Vector2, r0: float, r1: float, life: float, color: Color, width: float) -> void:
	_rings.append({"p": p, "r0": r0, "r1": r1, "life": life, "max": life, "c": color, "w": width})


func _burst(p: Vector2, count: int, color: Color, speed: float, radius: float) -> void:
	for i: int in count:
		var dir: Vector2 = Vector2.from_angle(_rng.randf() * TAU)
		var life: float = _rng.randf_range(0.35, 0.7)
		_particles.append({"p": p, "v": dir * speed * _rng.randf_range(0.4, 1.0), "life": life, "max": life, "c": color, "r": radius * _rng.randf_range(0.6, 1.2), "shard": false})


func _update_fx(delta: float) -> void:
	for p: Dictionary in _particles:
		p["life"] = float(p["life"]) - delta
		p["p"] = (p["p"] as Vector2) + (p["v"] as Vector2) * delta
		p["v"] = (p["v"] as Vector2) * pow(0.04, delta) + Vector2(0, 160 if p["shard"] else 0) * delta
		if p["shard"]:
			p["rot"] = float(p["rot"]) + delta * 6.0
	_particles = _particles.filter(func(p: Dictionary) -> bool: return float(p["life"]) > 0.0)
	for r: Dictionary in _rings:
		r["life"] = float(r["life"]) - delta
	_rings = _rings.filter(func(r: Dictionary) -> bool: return float(r["life"]) > 0.0)
	for key: Variant in _flash.keys():
		_flash[key] = float(_flash[key]) - delta * 4.0
		if float(_flash[key]) <= 0.0:
			_flash.erase(key)
	for key: Variant in _deny.keys():
		_deny[key] = float(_deny[key]) - delta * 3.0
		if float(_deny[key]) <= 0.0:
			_deny.erase(key)
	for key: Variant in _pops.keys():
		_pops[key] = float(_pops[key]) + delta * 4.0
	for key: Variant in _placed_t.keys():
		var rec: Dictionary = _placed_t[key]
		rec["t"] = minf(1.0, float(rec["t"]) + delta * 3.5)
	if not _live.is_empty():
		var spin: Array = _live["spin"]
		for i: int in mini(spin.size(), _spin_shown.size()):
			# Spinners turn the short way (always clockwise) to their new heading.
			var goal: float = float(spin[i]) * 90.0
			var cur: float = float(_spin_shown[i])
			var diff: float = fposmod(goal - cur, 360.0)
			_spin_shown[i] = cur + diff * minf(1.0, delta * 10.0)
		for g: Variant in _gate_shown:
			var want: float = 1.0 if RouteSim.gate_open(level, _live, int(g)) else 0.0
			_gate_shown[g] = move_toward(float(_gate_shown[g]), want, delta * 4.0)
		if RouteSim.dots_left(level, _live) == 0:
			_home_open = minf(1.0, _home_open + delta * 3.0)
	_screen_flash = maxf(0.0, _screen_flash - delta * 3.0)
	_kick = maxf(0.0, _kick - delta * 5.0)
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var s: float = _trauma * _trauma
	_shake = Vector2(14.0 * s * (0.6 * sin(_clock * 47.0) + 0.4 * sin(_clock * 89.0 + 1.3)), 10.0 * s * (0.6 * sin(_clock * 53.0 + 0.7) + 0.4 * sin(_clock * 97.0)))


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if level.is_empty():
		return
	draw_set_transform(_shake)
	var appear: float = 1.0 - pow(1.0 - _intro, 3.0)
	_draw_arena()
	_draw_floor(appear)
	if not _ghost.is_empty() and not playing:
		_draw_ghost()
	if hint_showing() and not playing:
		_draw_hint()
	for pts: Array in _path:
		_polyline_dots(pts, Color(pal["accent"], 0.9), cell_size * 0.2, cell_size * 0.05)
	if not playing and not demo and _path.is_empty() and not replaying:
		_draw_guide()
	_draw_pieces(appear)
	_draw_arrows(appear)
	_draw_orbs()
	_draw_spotlight()
	_draw_cursor()
	_draw_fx()
	if _screen_flash > 0.0:
		draw_rect(grid_rect().grow(cell_size * 0.3), Color(1, 1, 1, 0.18 * _screen_flash))
	draw_set_transform(Vector2.ZERO)


func _draw_arena() -> void:
	var r: Rect2 = grid_rect().grow(cell_size * 0.22)
	_round_rect(r, cell_size * 0.36, pal["faint"])


func _round_rect(rect: Rect2, radius: float, color: Color, border: Color = Color.TRANSPARENT, bw: float = 0.0) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 10
	sb.anti_aliasing = true
	if bw > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(bw))
	draw_style_box(sb, rect)


## Floor dots, blocks, holes and cracks.
func _draw_floor(appear: float) -> void:
	var b: Dictionary = RouteSim.board(level)
	var w: int = int(level["w"])
	var h: int = int(level["h"])
	var dot: Color = Color(pal["ink"], 0.13)
	for c: int in w * h:
		if b["blocks"].has(c):
			continue
		draw_circle(center(c), maxf(1.6, cell_size * 0.028), dot, true, -1.0, true)
	for c: Variant in b["blocks"]:
		var r: Rect2 = cell_rect(int(c)).grow(-cell_size * (0.08 + 0.42 * (1.0 - appear)))
		var wall: Color = pal["wall"]
		if bool(pal.get("dark", false)):
			# On dark rooms a full-strength light block shouts; soften it into the night.
			wall = wall.lerp(pal["bottom"], 0.35)
		var col: Color = wall.lerp(pal["target"], float(_flash.get(int(c), 0.0)) * 0.6)
		_round_rect(r, cell_size * 0.16, col)
	for c: Variant in b["cracks"]:
		var cc: int = int(c)
		var r2: Rect2 = cell_rect(cc).grow(-cell_size * 0.1)
		if not _live.is_empty() and RouteSim.is_hole(level, _live, cc):
			_round_rect(r2, cell_size * 0.18, Color(pal["ink"], 0.88))
			_round_rect(r2.grow(-cell_size * 0.1), cell_size * 0.12, Color(pal["ink"], 0.6))
			continue
		_round_rect(r2, cell_size * 0.18, Color(pal["ink"], 0.05), Color(pal["ink"], 0.22), 2.0)
		var p: Vector2 = r2.get_center()
		var s: float = cell_size
		var col2: Color = Color(pal["ink"], 0.35)
		var pts: PackedVector2Array = PackedVector2Array([p + Vector2(-0.3, -0.18) * s, p + Vector2(-0.08, -0.04) * s, p + Vector2(0.02, 0.14) * s, p + Vector2(0.3, 0.22) * s])
		draw_polyline(pts, col2, 2.0, true)
		draw_line(p + Vector2(-0.08, -0.04) * s, p + Vector2(0.14, -0.26) * s, col2, 2.0, true)


func _draw_pieces(appear: float) -> void:
	var b: Dictionary = RouteSim.board(level)
	var s: float = cell_size
	var ink: Color = pal["ink"]
	# Gates: a dashed square, solid when shut.
	for c: Variant in b["gates"]:
		var open: float = float(_gate_shown.get(c, 0.0))
		var r: Rect2 = cell_rect(int(c)).grow(-s * 0.1)
		_round_rect(r, s * 0.16, Color(pal["special"], 0.32 * (1.0 - open)))
		_dashed_rect(r, Color(pal["special"], 0.95 - 0.6 * open), 3.0)
	# Switches: a diamond with a halo.
	for c: Variant in b["switches"]:
		var p: Vector2 = center(int(c))
		var rr: float = s * 0.2 * appear
		var dia: PackedVector2Array = PackedVector2Array([p + Vector2(0, -rr), p + Vector2(rr, 0), p + Vector2(0, rr), p + Vector2(-rr, 0)])
		draw_colored_polygon(dia, pal["special"])
		var pulse: float = 0.5 + 0.5 * sin(_clock * 3.0)
		draw_arc(p, rr + s * 0.08 + s * 0.05 * pulse, 0.0, TAU, 32, Color(pal["special"], 0.5 - 0.3 * pulse), 2.5, true)
		draw_circle(p, s * 0.05, pal["top"], true, -1.0, true)
	# Portals: a ring with turning arcs.
	var portals: Array = level.get("portals", [])
	for i: int in portals.size():
		var pt: Array = portals[i]
		for side: int in 2:
			var p2: Vector2 = center(RouteSim.cell_of(level, int(pt[side * 2]), int(pt[side * 2 + 1])))
			var col: Color = pal["special"]
			var pr: float = s * 0.26 * appear
			draw_circle(p2, pr, Color(col, 0.16), true, -1.0, true)
			draw_arc(p2, pr, 0.0, TAU, 40, col, 3.0, true)
			var spin: float = _clock * (1.6 if side == 0 else -1.6) + float(i)
			for k: int in 3:
				var a0: float = spin + TAU * float(k) / 3.0
				draw_arc(p2, pr + s * 0.09, a0, a0 + 1.1, 12, Color(col, 0.7), 3.0, true)
			draw_circle(p2, s * 0.05, col, true, -1.0, true)
	# Bends: a short diagonal wall across the cell.
	for c: Variant in b["bends"]:
		var p3: Vector2 = center(int(c))
		var k: int = int(b["bends"][c])
		var half: float = s * 0.3 * appear
		var a: Vector2 = p3 + (Vector2(-half, half) if k == 0 else Vector2(-half, -half))
		var bb: Vector2 = p3 + (Vector2(half, -half) if k == 0 else Vector2(half, half))
		var col3: Color = (pal["wall"] as Color).lerp(pal["accent"], float(_flash.get(int(c), 0.0)) * 0.8)
		var t: float = maxf(4.0, s * 0.09)
		draw_line(a, bb, col3, t, true)
		draw_circle(a, t * 0.5, col3, true, -1.0, true)
		draw_circle(bb, t * 0.5, col3, true, -1.0, true)
	# Signs: a printed arrow.
	for c: Variant in b["signs"]:
		var r4: Rect2 = cell_rect(int(c)).grow(-s * 0.1)
		var fl: float = float(_flash.get(int(c), 0.0))
		_round_rect(r4, s * 0.18, Color(ink, 0.07 + 0.1 * fl))
		_chevron(center(int(c)), int(b["signs"][c]) * 90.0, s * 0.42 * appear, Color(ink, 0.9), maxf(3.0, s * 0.065))
	# Spinners: an arrow inside a turning ring.
	for c: Variant in b["spinners"]:
		var k2: int = int(b["spinners"][c])
		var p5: Vector2 = center(int(c))
		var ang: float = float(_spin_shown[k2]) if k2 < _spin_shown.size() else float(b["spin0"][k2]) * 90.0
		var fl2: float = float(_flash.get(int(c), 0.0))
		draw_circle(p5, s * 0.36, Color(pal["special"], 0.14 + 0.2 * fl2), true, -1.0, true)
		draw_arc(p5, s * 0.36, deg_to_rad(ang) + 0.5, deg_to_rad(ang) + TAU - 0.5, 32, Color(pal["special"], 0.9), 2.5, true)
		var tip: Vector2 = p5 + Vector2.from_angle(deg_to_rad(ang) + TAU - 0.5) * s * 0.36
		draw_circle(tip, s * 0.04, pal["special"], true, -1.0, true)
		_chevron(p5, ang, s * 0.36 * appear, pal["special"], maxf(3.0, s * 0.065))
	# Home: a ring that opens once every dot is taken.
	var hc: int = int(b["home"])
	var hp: Vector2 = center(hc)
	var open_k: float = _home_open
	var hr: float = s * 0.3 * appear
	if open_k < 1.0:
		_dashed_circle(hp, hr, Color(ink, 0.45 * (1.0 - open_k)), 3.0)
	draw_arc(hp, hr, 0.0, TAU, 48, Color(ink, 0.9 * open_k), 3.5, true)
	draw_arc(hp, hr * 0.62, 0.0, TAU, 40, Color(pal["accent"], 0.9 * open_k), 3.0, true)
	var breathe: float = 1.0 + 0.08 * sin(_clock * 2.6) * open_k
	draw_circle(hp, s * 0.07 * breathe, Color(ink, 0.35 + 0.6 * open_k), true, -1.0, true)
	# Dots.
	var dots: Array = level.get("dots", [])
	for i: int in dots.size():
		var d: Array = dots[i]
		var p6: Vector2 = center(RouteSim.cell_of(level, int(d[0]), int(d[1])))
		var taken: bool = not _live.is_empty() and RouteSim.dot_taken(_live, i)
		if taken:
			if _pops.has(i) and float(_pops[i]) < 1.0:
				var kk: float = float(_pops[i])
				draw_circle(p6, s * 0.17 * (1.0 + 0.6 * kk), Color(pal["target"], 1.0 - kk), true, -1.0, true)
			draw_circle(p6, s * 0.05, Color(pal["target"], 0.3), true, -1.0, true)
			continue
		var br: float = 1.0 + 0.04 * sin(_clock * 2.4 + float(i) * 1.7)
		var r6: float = s * 0.17 * br * appear
		if d.size() > 2:
			var next: bool = not _live.is_empty() and int(d[2]) == int(_live["nxt"])
			r6 = s * 0.21 * br * appear
			draw_circle(p6, r6, Color(pal["target"], 1.0 if next or _live.is_empty() else 0.55), true, -1.0, true)
			var f: Font = UIKit.font(700)
			var fs: int = int(s * 0.26)
			var txt: String = str(int(d[2]))
			var tw: Vector2 = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, p6 + Vector2(-tw.x * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pal["top"])
			if next and playing:
				draw_arc(p6, r6 + s * 0.06, 0.0, TAU, 32, Color(pal["target"], 0.5), 2.0, true)
		else:
			draw_circle(p6, r6, pal["target"], true, -1.0, true)
			draw_arc(p6, r6 * 0.46, 0.0, TAU, 28, Color(pal["top"], 0.9), maxf(2.0, s * 0.03), true)
	# Starts: a ring with a little pointer the way the orb sets off.
	for st: Array in b["starts"]:
		var sp: Vector2 = center(int(st[0]))
		var k3: float = 1.0 + 0.18 * _kick
		draw_arc(sp, s * 0.3 * k3 * appear, 0.0, TAU, 40, Color(ink, 0.85), 3.0, true)
		var dv: Vector2 = Vector2(RouteSim.dir_vec(int(st[1])))
		var tip2: Vector2 = sp + dv * s * 0.44
		var side: Vector2 = Vector2(-dv.y, dv.x)
		draw_colored_polygon(PackedVector2Array([tip2, tip2 - dv * s * 0.1 + side * s * 0.08, tip2 - dv * s * 0.1 - side * s * 0.08]), Color(ink, 0.85))


func _draw_arrows(appear: float) -> void:
	var s: float = cell_size
	for c: Variant in arrows:
		var rec: Dictionary = _placed_t.get(c, {"t": 1.0})
		var k: float = float(rec["t"])
		var pop: float = 1.0 + 0.25 * sin(minf(k, 1.0) * PI) * (1.0 - k)
		var fl: float = float(_flash.get(int(c), 0.0))
		var r: Rect2 = cell_rect(int(c)).grow(-s * 0.1)
		var grow: float = s * 0.4 * (1.0 - clampf(k * 2.0, 0.0, 1.0))
		_round_rect(r.grow(-grow), s * 0.18, Color(pal["accent"], 0.2 + 0.25 * fl))
		_chevron(center(int(c)), float(arrows[c]) * 90.0, s * 0.44 * pop * appear, pal["accent"], maxf(3.5, s * 0.08))


## A chevron arrow centred on p, pointing at `deg` (0 = right, 90 = down).
func _chevron(p: Vector2, deg: float, size_px: float, col: Color, width: float) -> void:
	var a: float = deg_to_rad(deg)
	var fwd: Vector2 = Vector2.from_angle(a)
	var side: Vector2 = Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = p + fwd * size_px * 0.42
	var tail: Vector2 = p - fwd * size_px * 0.42
	draw_line(tail, tip, col, width, true)
	var wing: float = size_px * 0.3
	draw_polyline(PackedVector2Array([tip - fwd * wing + side * wing, tip, tip - fwd * wing - side * wing]), col, width, true)
	draw_circle(tail, width * 0.5, col, true, -1.0, true)
	draw_circle(tip, width * 0.5, col, true, -1.0, true)
	draw_circle(tip - fwd * wing + side * wing, width * 0.5, col, true, -1.0, true)
	draw_circle(tip - fwd * wing - side * wing, width * 0.5, col, true, -1.0, true)


func _draw_orbs() -> void:
	var r: float = cell_size * 0.16
	for tr: Array in _trails:
		OrbStyles.draw_trail(self, orb_style, tr, pal, _clock, r)
	if _live.is_empty():
		return
	for i: int in _orb_pos.size():
		if playing and i < _moves.size():
			var m: Dictionary = _moves[i]
			# Home: it rolls in, then it's gone.
			if int(m["status"]) == 1 and (int(m["from"]) == int(m["to"]) or _tick_t >= 1.0):
				continue
		var bob: float = 1.0 if playing else 1.0 + 0.06 * sin(_clock * 3.0 + float(i))
		OrbStyles.draw_orb(self, orb_style, _orb_pos[i], r * bob, pal, _clock, playing)


## The guide: where the orb will roll, up to its first turn (or two, with the
## longer guide on) and a short way after.
func _draw_guide() -> void:
	if _preview_dirty:
		var n: int = 2 if bool(SaveSystem.get_setting("long_guide", true)) else 1
		_preview = RouteSim.preview(level, arrows, n, 2)
		_preview_dirty = false
	var phase: float = fmod(_clock * 40.0, cell_size * 0.25)
	for p: Dictionary in _preview:
		var cells: Array = p["cells"]
		var pts: Array = []
		var crash_at: Variant = null
		for k: int in cells.size():
			var c: int = int(cells[k])
			if c <= -1000:
				var from: Vector2 = pts[-1] if not pts.is_empty() else Vector2.ZERO
				crash_at = from.lerp(center(-1000 - c), 0.42)
			elif c < 0:
				pts.append(center(-1 - c))
				_polyline_dots(pts, Color(pal["ink"], 0.6), cell_size * 0.25, cell_size * 0.04, phase)
				pts = []
			else:
				pts.append(center(c))
		if str(p["end"]) == "crash" and crash_at == null and not pts.is_empty():
			# Off the edge: the guide runs to the board's edge.
			var last: Vector2 = pts[-1]
			var prev: Vector2 = pts[-2] if pts.size() > 1 else last
			var dirv: Vector2 = (last - prev).normalized() if pts.size() > 1 else Vector2(RouteSim.dir_vec(int(RouteSim.board(level)["starts"][0][1])))
			crash_at = last + dirv * cell_size * 0.42
		if crash_at != null:
			pts.append(crash_at)
		var fade: bool = str(p["end"]) == "more"
		_polyline_dots(pts, Color(pal["ink"], 0.6), cell_size * 0.25, cell_size * 0.04, phase, fade)
		if crash_at != null:
			var x: Vector2 = crash_at
			var rr: float = cell_size * 0.09
			draw_line(x + Vector2(-rr, -rr), x + Vector2(rr, rr), Color(pal["target"], 0.8), 3.0, true)
			draw_line(x + Vector2(-rr, rr), x + Vector2(rr, -rr), Color(pal["target"], 0.8), 3.0, true)


## Dots along a polyline, every `spacing` pixels (optionally fading out at the end).
func _polyline_dots(pts: Array, col: Color, spacing: float, radius: float, phase: float = 0.0, fade_end: bool = false) -> void:
	if pts.size() < 2:
		return
	var total: float = 0.0
	for i: int in pts.size() - 1:
		total += (pts[i] as Vector2).distance_to(pts[i + 1])
	var s: float = cell_size * 0.32 + phase
	var walked: float = 0.0
	for i: int in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg: float = a.distance_to(b)
		while s < walked + seg:
			var f: float = (s - walked) / maxf(seg, 0.001)
			var k: float = 1.0
			if fade_end:
				k = clampf((total - s) / (cell_size * 1.6), 0.15, 1.0)
			draw_circle(a.lerp(b, f), radius * (0.6 + 0.4 * k), Color(col, col.a * k), true, -1.0, true)
			s += spacing
		walked += seg


func _draw_ghost() -> void:
	var col: Color = Color(pal["ink"], 0.2)
	for pts: Array in _ghost:
		_polyline_dots(pts, col, cell_size * 0.2, cell_size * 0.03)
	for p: Vector2 in _ghost_end:
		var r: float = cell_size * 0.09
		draw_line(p + Vector2(-r, -r), p + Vector2(r, r), Color(pal["target"], 0.6), 3.0, true)
		draw_line(p + Vector2(-r, r), p + Vector2(r, -r), Color(pal["target"], 0.6), 3.0, true)


## The hint: the solving path, and an outline where each arrow goes.
func _draw_hint() -> void:
	var alpha: float = 0.6 + 0.25 * sin(_clock * 5.0)
	for pts: Array in _hint.get("path", []):
		_polyline_dots(pts, Color(pal["accent"], alpha), cell_size * 0.2, cell_size * 0.045, fmod(_clock * 30.0, cell_size * 0.2))
	var sol: Dictionary = _hint.get("arrows", {})
	for c: Variant in sol:
		if arrows.has(c) and int(arrows[c]) == int(sol[c]):
			continue
		var r: Rect2 = cell_rect(int(c)).grow(-cell_size * 0.1)
		_dashed_rect(r, Color(pal["accent"], 0.9), 3.0)
		_chevron(center(int(c)), float(sol[c]) * 90.0, cell_size * 0.4, Color(pal["accent"], 0.45), maxf(3.0, cell_size * 0.06))


func _draw_spotlight() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_clock * 4.5)
	for c: Variant in spotlight:
		var p: Vector2 = center(int(c))
		draw_arc(p, cell_size * (0.5 + 0.08 * pulse), 0.0, TAU, 48, Color(pal["accent"], 0.4 + 0.5 * pulse), 4.0, true)


func _draw_cursor() -> void:
	for c: Variant in _deny:
		var r: Rect2 = cell_rect(int(c)).grow(-cell_size * 0.06)
		var k: float = float(_deny[c])
		_round_rect(r.grow(cell_size * 0.04 * sin(k * PI * 3.0)), cell_size * 0.18, Color.TRANSPARENT, Color(pal["target"], 0.7 * k), 3.0)
	if cursor >= 0 and has_focus() and not playing:
		var r2: Rect2 = cell_rect(cursor).grow(-cell_size * 0.04)
		_round_rect(r2, cell_size * 0.2, Color.TRANSPARENT, Color(pal["accent"], 0.9), 3.0)


func _dashed_rect(r: Rect2, col: Color, width: float) -> void:
	var pts: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k: int in 4:
		_dashed(pts[k], pts[(k + 1) % 4], col, width)


func _dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var length: float = a.distance_to(b)
	if length < 1.0:
		return
	var dir: Vector2 = (b - a) / length
	var dash: float = maxf(6.0, cell_size * 0.1)
	var s: float = dash * 0.3
	while s < length:
		draw_line(a + dir * s, a + dir * minf(s + dash, length), col, width, true)
		s += dash * 1.8


func _dashed_circle(p: Vector2, r: float, col: Color, width: float) -> void:
	var n: int = 14
	for k: int in n:
		var a0: float = TAU * float(k) / float(n) + _clock * 0.3
		draw_arc(p, r, a0, a0 + TAU / float(n) * 0.55, 6, col, width, true)


func _draw_fx() -> void:
	for r: Dictionary in _rings:
		var k: float = 1.0 - float(r["life"]) / float(r["max"])
		var e: float = 1.0 - pow(1.0 - k, 3.0)
		var rad: float = lerpf(float(r["r0"]), float(r["r1"]), e)
		var col: Color = r["c"]
		draw_arc(r["p"], maxf(0.5, rad), 0.0, TAU, 48, Color(col, col.a * (1.0 - k)), maxf(0.5, float(r["w"]) * (1.0 - k * 0.7)), true)
	for p: Dictionary in _particles:
		var k2: float = float(p["life"]) / float(p["max"])
		var col2: Color = p["c"]
		if p["shard"]:
			var dir: Vector2 = Vector2.from_angle(float(p["rot"])) * float(p["r"]) * 0.5
			draw_line((p["p"] as Vector2) - dir, (p["p"] as Vector2) + dir, Color(col2, col2.a * k2), 3.0, true)
		else:
			draw_circle(p["p"], float(p["r"]) * (0.4 + 0.6 * k2), Color(col2, col2.a * k2), true, -1.0, true)
