extends Control
## The Google Play feature graphic (1024 x 500): the icon's run (up from the start,
## one arrow, right into home) on the icon's coral, with the name and a plain line.
## Rendered by `godot --path . --resolution 1024x500 res://tools/render_feature_graphic.tscn`.

const TOP: Color = Color("#FF9A5C")
const BOTTOM: Color = Color("#DC4F45")
const CREAM: Color = Color("#FFF4E8")
const ARROW: Color = Color("#E8603F")


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([TOP, TOP.lerp(BOTTOM, 0.5), BOTTOM, TOP.lerp(BOTTOM, 0.5)]))
	# A faint dot grid, like the rooms.
	for y: int in range(25, 500, 50):
		for x: int in range(25, 1024, 50):
			draw_circle(Vector2(x, y), 2.0, Color(CREAM, 0.16), true, -1.0, true)
	var start: Vector2 = Vector2(125, 375)
	var turn: Vector2 = Vector2(125, 125)
	var home: Vector2 = Vector2(425, 125)
	draw_arc(start, 32.0, 0.0, TAU, 48, CREAM, 11.0, true)
	for i: int in 4:
		draw_circle(start.lerp(turn, (float(i) + 1.0) / 5.0), 7.0, Color(CREAM, 0.75), true, -1.0, true)
	var tile: StyleBoxFlat = StyleBoxFlat.new()
	tile.bg_color = CREAM
	tile.set_corner_radius_all(24)
	tile.corner_detail = 10
	draw_style_box(tile, Rect2(turn - Vector2(48, 48), Vector2(96, 96)))
	draw_line(turn + Vector2(-24, 0), turn + Vector2(24, 0), ARROW, 15.0, true)
	draw_polyline(PackedVector2Array([turn + Vector2(4, -20), turn + Vector2(24, 0), turn + Vector2(4, 20)]), ARROW, 15.0, true)
	draw_circle(Vector2(225, 125), 7.0, Color(CREAM, 0.75), true, -1.0, true)
	draw_circle(Vector2(275, 125), 7.0, Color(CREAM, 0.75), true, -1.0, true)
	draw_circle(Vector2(335, 125), 44.0, Color(1, 1, 1, 0.14), true, -1.0, true)
	draw_circle(Vector2(335, 125), 22.0, CREAM, true, -1.0, true)
	draw_arc(home, 40.0, 0.0, TAU, 48, CREAM, 11.0, true)
	draw_circle(home, 12.0, CREAM, true, -1.0, true)
	# Name and line.
	var title: Font = UIKit.font(300)
	draw_string(title, Vector2(530, 250), "Few Turns", HORIZONTAL_ALIGNMENT_LEFT, -1, 80, CREAM)
	var body: Font = UIKit.font(500)
	draw_string(body, Vector2(534, 312), "A quiet arrow puzzle.", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(CREAM, 0.85))
	draw_string(body, Vector2(534, 358), "A few arrows. One run home.", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#FFE2C8"))
