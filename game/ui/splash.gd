class_name Splash
extends Control
## The opening moment: the logo plays out (the orb rolls up from the start, the
## arrow turns it, and it rolls into home), the title appears, then it fades into
## the game. Matches the boot splash (the icon tile on cream) so the hand-off is
## seamless. Tap to skip.

signal finished

const BG_TOP: Color = Color("#FFF4E8")
const BG_BOTTOM: Color = Color("#FFD3C2")
const TILE_A: Color = Color("#FF9A5C")
const TILE_B: Color = Color("#DC4F45")
const CREAM: Color = Color("#FFF4E8")
const ARROW: Color = Color("#E8603F")
const INK: Color = Color("#2D2A4A")
const LENGTH: float = 2.7
## Logo-space points: start, the arrow, home.
const START: Vector2 = Vector2(300, 730)
const TURN: Vector2 = Vector2(300, 330)
const HOME: Vector2 = Vector2(770, 330)

var _t: float = 0.0
## Driven frame by frame (e.g. for recording) instead of by the clock: no sound, no
## tap to skip, no fade-out.
var manual: bool = false
var _done: bool = false
var _turned: bool = false
var _home: bool = false


## Shows the moment `t` seconds in (manual mode).
func show_at(t: float) -> void:
	_t = t
	_turned = t > 1.0
	_home = t > 1.5
	queue_redraw()


func _ready() -> void:
	if manual:
		set_process(false)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_finish()
	)


func _process(delta: float) -> void:
	_t += delta
	if not _turned and _t > 1.0:
		_turned = true
		AudioManager.play("bounce", 1.0, -6.0)
		Haptics.tap(8)
	if not _home and _t > 1.5:
		_home = true
		AudioManager.play_note("pop", 2)
		Haptics.tap(14)
	if _t >= LENGTH:
		_finish()
	queue_redraw()


func _finish() -> void:
	if _done:
		return
	_done = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		finished.emit()
		queue_free()
	)


## Logo space (1024 x 1024, the glyph scaled as in the icon) to screen.
func _p(v: Vector2) -> Vector2:
	var s: float = _unit()
	return size * Vector2(0.5, 0.42) + ((v - Vector2(527, 513)) * 0.86) * s


func _unit() -> float:
	return minf(size.x, size.y) / 1024.0 * 0.62


func _r(v: float) -> float:
	return v * 0.86 * _unit()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
	# The tile, as in the icon.
	var u: float = _unit()
	var tile: Rect2 = Rect2(size * Vector2(0.5, 0.42) - Vector2(512, 512) * u, Vector2(1024, 1024) * u)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = TILE_A.lerp(TILE_B, 0.5)
	sb.set_corner_radius_all(int(232.0 * u))
	sb.corner_detail = 12
	sb.shadow_color = Color(INK, 0.12)
	sb.shadow_size = int(40.0 * u)
	sb.shadow_offset = Vector2(0, 16.0 * u)
	draw_style_box(sb, tile)
	var appear: float = clampf(_t / 0.3, 0.0, 1.0)
	var cream: Color = Color(CREAM, appear)
	# Start ring and home.
	draw_arc(_p(START), _r(62), 0.0, TAU, 48, cream, _r(22), true)
	var hk: float = clampf((_t - 1.5) / 0.5, 0.0, 1.0)
	draw_arc(_p(HOME), _r(80) * (1.0 + 0.15 * sin(hk * PI)), 0.0, TAU, 48, cream, _r(22), true)
	draw_circle(_p(HOME), _r(24), cream, true, -1.0, true)
	if _home and hk < 1.0:
		draw_arc(_p(HOME), _r(80 + 120 * hk), 0.0, TAU, 56, Color(CREAM, 1.0 - hk), _r(10), true)
	# The arrow tile, which pops when the orb turns on it.
	var pk: float = clampf((_t - 1.0) / 0.3, 0.0, 1.0)
	var pop: float = 1.0 + 0.14 * sin(pk * PI)
	var half: float = _r(95) * pop
	var tr: Rect2 = Rect2(_p(TURN) - Vector2(half, half), Vector2(half, half) * 2.0)
	var tsb: StyleBoxFlat = StyleBoxFlat.new()
	tsb.bg_color = cream
	tsb.set_corner_radius_all(int(_r(46)))
	tsb.corner_detail = 10
	draw_style_box(tsb, tr)
	var c: Vector2 = _p(TURN)
	var w: float = _r(30)
	var ac: Color = Color(ARROW, appear)
	draw_line(c + Vector2(-_r(48), 0) * pop, c + Vector2(_r(48), 0) * pop, ac, w, true)
	draw_polyline(PackedVector2Array([c + Vector2(_r(8), -_r(40)) * pop, c + Vector2(_r(48), 0) * pop, c + Vector2(_r(8), _r(40)) * pop]), ac, w, true)
	# The run: up (0.35 -> 1.0 s), turn, right into home (-> 1.5 s). Dots trail it.
	var k1: float = clampf((_t - 0.35) / 0.65, 0.0, 1.0)
	var k2: float = clampf((_t - 1.0) / 0.5, 0.0, 1.0)
	for y: float in [640.0, 585.0, 530.0, 475.0]:
		var f: float = (730.0 - y) / 400.0
		if f < k1:
			draw_circle(_p(Vector2(300, y)), _r(15), Color(CREAM, 0.75), true, -1.0, true)
	for x: float in [430.0, 482.0]:
		var f2: float = (x - 300.0) / 470.0
		if f2 < k2:
			draw_circle(_p(Vector2(x, 330)), _r(15), Color(CREAM, 0.75), true, -1.0, true)
	var orb: Vector2 = START
	if k2 > 0.0:
		orb = TURN.lerp(HOME, k2)
	elif k1 > 0.0:
		orb = START.lerp(TURN, k1)
	if not _home:
		draw_circle(_p(orb), _r(90), Color(1, 1, 1, 0.14 * appear), true, -1.0, true)
		draw_circle(_p(orb), _r(44), cream, true, -1.0, true)
	# Title.
	var ta: float = clampf((_t - 1.6) / 0.45, 0.0, 1.0)
	if ta > 0.0:
		var f3: Font = UIKit.font(300)
		var fs: int = int(clampf(size.x * 0.11, 48.0, 96.0))
		var title: String = "few turns"
		var tw: float = f3.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y2: float = tile.end.y + fs + 20.0 * (1.0 - ta)
		draw_string(f3, Vector2(size.x * 0.5 - tw * 0.5, y2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, ta))
		var f4: Font = UIKit.font(500)
		var tag: String = "a quiet arrow puzzle"
		var tw2: float = f4.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(f4, Vector2(size.x * 0.5 - tw2 * 0.5, y2 + 46.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(INK, 0.5 * ta))
