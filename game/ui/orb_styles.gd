class_name OrbStyles
extends RefCounted
## The orb and its trail, in every style the Orb pack offers. "classic" is free;
## the rest come with the Orb pack (or a one-hour trial from a video).

const STYLES: Array = [
	{"id": "classic", "name": "Classic", "free": true},
	{"id": "comet", "name": "Comet"},
	{"id": "pearl", "name": "Pearl"},
	{"id": "ember", "name": "Ember"},
	{"id": "neon", "name": "Neon"},
	{"id": "planet", "name": "Planet"},
	{"id": "eclipse", "name": "Eclipse"},
]


static func ids() -> Array:
	return STYLES.map(func(s: Dictionary) -> String: return str(s["id"]))


static func display_name(id: String) -> String:
	for s: Dictionary in STYLES:
		if str(s["id"]) == id:
			return str(s["name"])
	return "Classic"


static func is_free(id: String) -> bool:
	return id == "classic"


static func trail_length(id: String) -> int:
	match id:
		"comet":
			return 34
		"ember", "neon":
			return 24
		_:
			return 16


static func _glow(c: CanvasItem, p: Vector2, r: float, col: Color, layers: int, spread: float) -> void:
	for i: int in layers:
		var k: float = 1.0 - float(i) / float(layers)
		c.draw_circle(p, r * (1.0 + spread * (1.0 - k) + 0.25), Color(col, col.a * 0.12 * k), true, -1.0, true)


## Draws one orb at p. `flying` adds the soft halo used in flight.
static func draw_orb(c: CanvasItem, id: String, p: Vector2, r: float, pal: Dictionary, clock: float, flying: bool) -> void:
	var ink: Color = pal["orb"]
	var dark: bool = bool(pal.get("dark", false))
	match id:
		"comet":
			_glow(c, p, r, Color(pal["accent"], 1.0), 4, 1.6)
			c.draw_circle(p, r, Color.WHITE.lerp(pal["accent"], 0.25), true, -1.0, true)
			c.draw_circle(p, r * 0.55, Color.WHITE, true, -1.0, true)
		"pearl":
			c.draw_circle(p, r * 1.15, Color(ink, 0.18), true, -1.0, true)
			c.draw_circle(p, r, Color("#F4F1EA"), true, -1.0, true)
			c.draw_arc(p, r, 0.0, TAU, 24, Color(ink, 0.35), 1.5, true)
			c.draw_circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.32, Color.WHITE, true, -1.0, true)
		"ember":
			var flicker: float = 0.85 + 0.15 * sin(clock * 23.0)
			_glow(c, p, r, Color("#FF7A2F"), 4, 1.2 * flicker)
			c.draw_circle(p, r, Color("#FF7A2F"), true, -1.0, true)
			c.draw_circle(p, r * 0.6, Color("#FFD166"), true, -1.0, true)
		"neon":
			var hue: float = fmod(clock * 0.15, 1.0)
			var col: Color = Color.from_hsv(hue, 0.65, 1.0)
			_glow(c, p, r, col, 5, 1.8)
			c.draw_arc(p, r * 0.85, 0.0, TAU, 28, col, 3.0, true)
			c.draw_circle(p, r * 0.4, Color.WHITE, true, -1.0, true)
		"planet":
			c.draw_circle(p, r, pal["accent"], true, -1.0, true)
			c.draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(Color.WHITE, 0.45), true, -1.0, true)
			var tilt: float = -0.35
			var pts: PackedVector2Array = PackedVector2Array()
			for k: int in 33:
				var a: float = TAU * float(k) / 32.0
				pts.append(p + Vector2(cos(a) * r * 1.75, sin(a) * r * 0.5).rotated(tilt))
			c.draw_polyline(pts, Color(pal["special2"], 0.95), 2.2, true)
		"eclipse":
			_glow(c, p, r, Color("#FFF3C4"), 4, 1.4)
			c.draw_circle(p, r * 1.08, Color("#FFF3C4"), true, -1.0, true)
			c.draw_circle(p, r * 0.92, Color("#14121F"), true, -1.0, true)
		_:
			if flying:
				if dark:
					c.draw_circle(p, r * 2.8, Color(ink, 0.06), true, -1.0, true)
					c.draw_circle(p, r * 1.8, Color(ink, 0.14), true, -1.0, true)
				else:
					c.draw_circle(p, r * 1.7, Color(ink, 0.1), true, -1.0, true)
			c.draw_circle(p, r, ink, true, -1.0, true)


static func draw_trail(c: CanvasItem, id: String, tr: Array, pal: Dictionary, clock: float, orb_r: float) -> void:
	var n: int = tr.size()
	var col: Color = pal["orb"]
	var width: float = orb_r * 1.6
	match id:
		"comet":
			col = Color.WHITE.lerp(pal["accent"], 0.4)
			width = orb_r * 2.0
		"ember":
			col = Color("#FF7A2F")
		"neon":
			col = Color.from_hsv(fmod(clock * 0.15, 1.0), 0.65, 1.0)
		"planet":
			col = pal["accent"]
		"eclipse":
			col = Color("#FFF3C4")
		"pearl":
			col = Color(pal["orb"], 0.6)
	for k: int in range(1, n):
		var f: float = float(k) / float(n)
		c.draw_line(tr[k - 1], tr[k], Color(col, 0.3 * f), width * f, true)
	if id == "ember" and n > 4:
		# Sparks shed from the trail.
		for k: int in range(0, n, 3):
			var jitter: Vector2 = Vector2(sin(clock * 31.0 + float(k)), cos(clock * 27.0 + float(k) * 1.7)) * 6.0
			c.draw_circle((tr[k] as Vector2) + jitter, 1.8, Color("#FFD166", 0.6 * float(k) / float(n)), true, -1.0, true)
