extends Overlay
## What a setting does: a little looping demo, a description, and the switch.

const INFO: Dictionary = {
	"long_guide": ["Longer guide", "The dotted guide follows the orb through two turns instead of one, so you can see more of its way before you press Go. Turn it off for a purer challenge."],
	"shake": ["Screen shake", "The room gives a small jolt when the orb takes a dot, hits a block or gets home, so every moment feels solid. Turn it off if motion bothers you."],
	"haptics": ["Vibration", "Your phone gives a short buzz on turns, dots and button taps. Turn it off to play silently in your hand."],
}

var key: String = "long_guide"


func build() -> void:
	name = "SettingInfo"
	var info: Array = INFO.get(key, INFO["long_guide"])
	add_title(str(info[0]))
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 16)
	var demo: _Demo = _Demo.new()
	demo.name = "Demo"
	demo.key = key
	demo.pal = pal
	demo.custom_minimum_size = Vector2(0, 300)
	body.add_child(demo)
	var text: Label = UIKit.label(str(info[1]), 23, pal["ink"], 400)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(text)
	var row: HBoxContainer = UIKit.toggle_row(str(info[0]), bool(SaveSystem.get_setting(key, true)), pal, func(on: bool) -> void:
		SaveSystem.set_setting(key, on)
		demo.queue_redraw()
	)
	row.name = "Toggle"
	body.add_child(row)
	var back: Button = UIKit.pill("Back to settings", pal, "soft", Vector2(0, 76), 24)
	back.name = "BackToSettings"
	back.pressed.connect(close)
	body.add_child(back)
	_first_focus = back


## Side-by-side "off" and "on" panels playing the same moment.
class _Demo:
	extends Control
	var key: String
	var pal: Dictionary
	var _t: float = 0.0
	var _buzzed: int = -1

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var w: float = (size.x - 20.0) * 0.5
		for i: int in 2:
			var r: Rect2 = Rect2(Vector2(float(i) * (w + 20.0), 0), Vector2(w, size.y))
			var on: bool = i == 1
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.bg_color = Color(pal["ink"], 0.05)
			sb.set_corner_radius_all(24)
			sb.border_color = Color(pal["accent"], 0.8) if on else Color(pal["ink"], 0.1)
			sb.set_border_width_all(3 if on else 2)
			draw_style_box(sb, r)
			var f: Font = UIKit.font(700)
			var cap: String = "ON" if on else "OFF"
			draw_string(f, r.position + Vector2(18, 34), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(pal["accent"] if on else pal["muted"]))
			match key:
				"shake":
					_shake_panel(r, on)
				"haptics":
					_buzz_panel(r, on)
				_:
					_guide_panel(r, on)

	## A small grid: the orb, two arrows, and the guide through one turn or two.
	func _guide_panel(r: Rect2, on: bool) -> void:
		var ink: Color = pal["ink"]
		var cell: float = minf((r.size.x - 40.0) / 4.0, (r.size.y - 70.0) / 4.0)
		var o: Vector2 = Vector2(r.get_center().x - cell * 2.0, r.position.y + 52.0)
		var at: Callable = func(x: int, y: int) -> Vector2: return o + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
		for y: int in 4:
			for x: int in 4:
				draw_circle(at.call(x, y), 2.0, Color(ink, 0.15), true, -1.0, true)
		# Start bottom-left, up to an arrow, right to an arrow, up off the top.
		var pts: Array = [at.call(0, 3), at.call(0, 1), at.call(2, 1), at.call(2, 0)]
		var stop: int = 3 if on else 2
		var phase: float = fmod(_t * 0.6, 1.0)
		for k: int in stop:
			var a: Vector2 = pts[k]
			var b: Vector2 = pts[k + 1]
			if k == stop - 1:
				b = a.lerp(b, 0.7 if not on else 1.0)
			_dots(a, b, Color(ink, 0.75 - 0.15 * float(k)))
		for c: Vector2 in [pts[1], pts[2]]:
			var rr: Rect2 = Rect2(c - Vector2(cell, cell) * 0.4, Vector2(cell, cell) * 0.8)
			var sb2: StyleBoxFlat = StyleBoxFlat.new()
			sb2.bg_color = Color(pal["accent"], 0.2)
			sb2.set_corner_radius_all(int(cell * 0.18))
			draw_style_box(sb2, rr)
		_arrow(pts[1], Vector2.RIGHT, cell)
		_arrow(pts[2], Vector2.UP, cell)
		draw_arc(pts[0], cell * 0.3, 0.0, TAU, 32, ink, 3.0, true)
		draw_circle(pts[0], cell * 0.16 * (1.0 + 0.06 * sin(phase * TAU)), pal["orb"], true, -1.0, true)

	func _arrow(c: Vector2, dir: Vector2, cell: float) -> void:
		var s: float = cell * 0.3
		var side: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = c + dir * s
		draw_line(c - dir * s, tip, pal["accent"], 4.0, true)
		draw_polyline(PackedVector2Array([tip - dir * s * 0.6 + side * s * 0.6, tip, tip - dir * s * 0.6 - side * s * 0.6]), pal["accent"], 4.0, true)

	func _dots(a: Vector2, b: Vector2, col: Color) -> void:
		var n: int = int(a.distance_to(b) / 12.0)
		for k: int in n:
			draw_circle(a.lerp(b, (float(k) + 0.5) / float(maxi(n, 1))), 2.8, col, true, -1.0, true)

	## The orb takes a dot; with shake on, the little room jolts.
	func _shake_panel(r: Rect2, on: bool) -> void:
		var u: float = fmod(_t, 1.8) / 1.8
		var k: float = clampf(u / 0.45, 0.0, 1.0)
		var hit: bool = u >= 0.45
		var jolt: float = 0.0
		if on and hit:
			var d: float = (u - 0.45) / 0.3
			jolt = maxf(0.0, 1.0 - d) * 9.0
		var off: Vector2 = Vector2(sin(_t * 61.0), cos(_t * 53.0)) * jolt
		var inner: Rect2 = Rect2(r.position + Vector2(24, 54) + off, r.size - Vector2(48, 78))
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(pal["ink"], 0.06)
		sb.set_corner_radius_all(14)
		draw_style_box(sb, inner)
		var target: Vector2 = inner.position + Vector2(inner.size.x * 0.5, 34)
		var start: Vector2 = inner.position + Vector2(inner.size.x * 0.5, inner.size.y - 20)
		if not hit:
			draw_circle(target, 14.0, pal["target"], true, -1.0, true)
			draw_circle(start.lerp(target, k), 6.0, pal["orb"], true, -1.0, true)
		else:
			var p: float = clampf((u - 0.45) / 0.3, 0.0, 1.0)
			draw_arc(target, 14.0 + 26.0 * p, 0.0, TAU, 32, Color(pal["target"], 1.0 - p), 3.0, true)

	## A phone that buzzes when the orb hits, with ripples, when vibration is on.
	func _buzz_panel(r: Rect2, on: bool) -> void:
		var u: float = fmod(_t, 1.4) / 1.4
		var buzz: bool = on and u > 0.5 and u < 0.75
		var c: Vector2 = r.get_center() + Vector2(0, 18)
		var wob: Vector2 = Vector2(sin(_t * 90.0) * 3.0, 0) if buzz else Vector2.ZERO
		var phone: Rect2 = Rect2(c - Vector2(42, 74) + wob, Vector2(84, 148))
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(pal["ink"], 0.08)
		sb.border_color = pal["ink"]
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(16)
		draw_style_box(sb, phone)
		draw_circle(phone.get_center() + Vector2(0, -20), 10.0, pal["target"], true, -1.0, true)
		if buzz:
			for k: int in 3:
				var off2: float = 58.0 + 12.0 * float(k)
				var col: Color = Color(pal["accent"], 0.7 - 0.2 * float(k))
				draw_arc(c + Vector2(-off2 + 10.0, 0), 20.0, PI * 0.7, PI * 1.3, 10, col, 3.0, true)
				draw_arc(c + Vector2(off2 - 10.0, 0), 20.0, -PI * 0.3, PI * 0.3, 10, col, 3.0, true)
			var beat: int = int(_t / 1.4)
			if beat != _buzzed:
				_buzzed = beat
				if is_visible_in_tree():
					Haptics.tap(18)
