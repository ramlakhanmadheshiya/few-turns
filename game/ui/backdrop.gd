class_name Backdrop
extends Control
## Soft vertical gradient that eases between chapter palettes, with slow drifting motes.

var _top: Color = Color("#FFF4E8")
var _bottom: Color = Color("#FFD3C2")
var _mote: Color = Color(1, 1, 1, 0.5)
var _motes: Array = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7
	for i: int in 26:
		_motes.append({"p": Vector2(_rng.randf(), _rng.randf()), "r": _rng.randf_range(1.5, 4.5), "s": _rng.randf_range(0.006, 0.02), "ph": _rng.randf() * TAU})


func set_palette(pal: Dictionary, animate: bool = true) -> void:
	var top: Color = pal["top"]
	var bottom: Color = pal["bottom"]
	var mote: Color = Color(1, 1, 1, 0.55) if not bool(pal.get("dark", false)) else Color(1, 1, 1, 0.18)
	if _tween != null:
		_tween.kill()
	if not animate:
		_top = top
		_bottom = bottom
		_mote = mote
		queue_redraw()
		return
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "_top", top, 0.7)
	_tween.tween_property(self, "_bottom", bottom, 0.7)
	_tween.tween_property(self, "_mote", mote, 0.7)


func _process(delta: float) -> void:
	for m: Dictionary in _motes:
		var p: Vector2 = m["p"]
		p.y -= float(m["s"]) * delta
		p.x += sin(Time.get_ticks_msec() / 1000.0 * 0.4 + float(m["ph"])) * 0.0006
		if p.y < -0.02:
			p.y = 1.02
		m["p"] = p
	queue_redraw()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	var pts: PackedVector2Array = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([_top, _top, _bottom, _bottom]))
	for m: Dictionary in _motes:
		var p: Vector2 = (m["p"] as Vector2) * size
		var tw: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 0.8 + float(m["ph"]))
		draw_circle(p, float(m["r"]), Color(_mote, _mote.a * (0.35 + 0.65 * tw)), true, -1.0, true)
