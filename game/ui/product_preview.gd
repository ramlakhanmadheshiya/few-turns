class_name ProductPreview
extends Control
## A small live picture of what a pack gives you: orbs flying with their trails,
## theme swatches, rooms unlocking, a beating heart.

var product: String = "supporter_pack"
var pal: Dictionary
## Compact = the rounded tile in a shop row; otherwise the hero of a product card.
var compact: bool = false
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	if compact:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(pal["accent"], 0.14)
		sb.set_corner_radius_all(26)
		sb.corner_detail = 8
		draw_style_box(sb, r)
	var c: Vector2 = size * 0.5
	var u: float = minf(size.x, size.y)
	match product:
		"complete_pack":
			_orbs(c + Vector2(-u * 0.16, -u * 0.12), u * 0.55, 3)
			_swatches(c + Vector2(u * 0.18, u * 0.14), u * 0.42, 4)
			_heart(c + Vector2(-u * 0.2, u * 0.2), u * 0.26)
		"orb_pack":
			_orbs(c, u * (0.9 if compact else 0.75), 3 if compact else 6)
		"theme_pack":
			_swatches(c, u * (0.8 if compact else 0.7), 4 if compact else 11)
		"keys":
			_keys(c, u * (0.7 if compact else 0.6))
		_:
			_heart(c, u * (0.55 if compact else 0.5))


func _heart(c: Vector2, s: float) -> void:
	var beat: float = 1.0 + 0.07 * maxf(0.0, sin(_t * 4.0)) * maxf(0.0, sin(_t * 1.3))
	var hs: float = s * beat
	if not compact:
		draw_circle(c, s * 0.68, Color(pal["accent"], 0.14), true, -1.0, true)
	draw_texture_rect(UIKit.icon("heart-filled"), Rect2(c - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, pal["target"])


## Orbs circling, each in a different style with its trail.
func _orbs(c: Vector2, span: float, count: int) -> void:
	var styles: Array = OrbStyles.ids().slice(1)
	var r: float = span * 0.32
	var orb_r: float = maxf(4.0, span * (0.07 if count > 3 else 0.09))
	for i: int in count:
		var style: String = styles[i % styles.size()]
		var a: float = _t * 1.1 + TAU * float(i) / float(count)
		var trail: Array = []
		for k: int in 14:
			var ak: float = a - float(13 - k) * 0.06
			trail.append(c + Vector2(cos(ak), sin(ak) * 0.7) * r)
		OrbStyles.draw_trail(self, style, trail, pal, _t, orb_r)
		OrbStyles.draw_orb(self, style, trail[-1], orb_r, pal, _t, true)


## Theme swatches: each a little light-and-deep pill.
func _swatches(c: Vector2, span: float, count: int) -> void:
	var ids: Array = Palette.THEMES.keys()
	var cols: int = 2 if count <= 4 else 4
	var rows: int = ceili(float(count) / float(cols))
	var cell: float = span / float(maxi(cols, rows))
	var origin: Vector2 = c - Vector2(cell * float(cols), cell * float(rows)) * 0.5
	var shift: int = int(_t * 0.8)
	for i: int in count:
		var th: Dictionary = Palette.THEMES[ids[(i + shift) % ids.size()]]
		var p: Vector2 = origin + Vector2(float(i % cols) + 0.5, float(i / cols) + 0.5) * cell
		var rr: float = cell * 0.4
		draw_circle(p, rr, Color(th["bottom"]), true, -1.0, true)
		draw_circle(p, rr * 0.62, Color(th["top"]), true, -1.0, true)
		draw_circle(p, rr * 0.28, Color(th["accent"]), true, -1.0, true)
		draw_arc(p, rr, 0.0, TAU, 24, Color(pal["ink"], 0.15), 1.2, true)


## Three keys fanned out, gently swaying.
func _keys(c: Vector2, span: float) -> void:
	for i: int in 3:
		var a: float = (float(i) - 1.0) * 0.45 + 0.08 * sin(_t * 1.6 + float(i))
		var s: float = span * (0.62 if i == 1 else 0.5)
		var p: Vector2 = c + Vector2((float(i) - 1.0) * span * 0.22, (0.0 if i == 1 else span * 0.06))
		draw_set_transform(p, a, Vector2.ONE)
		draw_texture_rect(UIKit.icon("key-round"), Rect2(-Vector2(s, s) * 0.5, Vector2(s, s)), false, pal["accent"] if i == 1 else Color(pal["accent"], 0.6))
	draw_set_transform(Vector2.ZERO)


## A 3x3 grid of rooms whose locks open one by one.
func _levels(c: Vector2, span: float) -> void:
	var cell: float = span / 3.0
	var open: int = int(fmod(_t * 3.0, 12.0))
	for i: int in 9:
		var p: Vector2 = c + Vector2(float(i % 3) - 1.0, float(i / 3) - 1.0) * cell
		var s: float = cell * 0.82
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.set_corner_radius_all(int(s * 0.28))
		sb.corner_detail = 6
		var is_open: bool = i < open
		sb.bg_color = Color(pal["accent"], 0.85) if is_open else Color(pal["ink"], 0.1)
		draw_style_box(sb, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)))
		var ic: String = "check" if is_open else "lock"
		var isz: float = s * 0.5
		draw_texture_rect(UIKit.icon(ic), Rect2(p - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color.WHITE if is_open else Color(pal["ink"], 0.4))
