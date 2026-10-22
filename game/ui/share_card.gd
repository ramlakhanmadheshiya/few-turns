class_name ShareCard
extends Control
## The picture players share after a clear: the room with the run they made, their
## stars, and a QR code that opens the game. Rendered off-screen at 1080 x 1350
## (4:5, the shape chat apps and feeds show best).

const SIZE: Vector2i = Vector2i(1080, 1350)
const SITE: String = "theramlakhan.com/few-turns"

var info: Dictionary = {}
var pal: Dictionary


## Renders the card for `info` and calls back with an Image (null if the renderer
## isn't available, e.g. headless).
static func render(host: Node, data: Dictionary, done: Callable) -> void:
	if DisplayServer.get_name() == "headless":
		done.call(null)
		return
	var vp: SubViewport = SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var card: ShareCard = ShareCard.new()
	card.info = data
	card.pal = data["pal"]
	card.size = Vector2(SIZE)
	vp.add_child(card)
	host.add_child(vp)
	# Let the board lay out and settle before taking the picture.
	for i: int in 4:
		await RenderingServer.frame_post_draw
	if not is_instance_valid(vp):
		return
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	done.call(img)


func _ready() -> void:
	var p: Dictionary = pal
	var level: Dictionary = info["level"]
	# Header: icon and name on the left, level and chapter on the right.
	var icon: TextureRect = TextureRect.new()
	icon.texture = load("res://assets/icon.svg")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	icon.position = Vector2(72, 64)
	icon.size = Vector2(100, 100)
	add_child(icon)
	var name_l: Label = UIKit.label("Few Turns", 54, p["ink"], 400, HORIZONTAL_ALIGNMENT_LEFT)
	name_l.position = Vector2(196, 78)
	name_l.size = Vector2(520, 72)
	add_child(name_l)
	var lvl: Label = UIKit.caption("Level %d" % int(info["number"]), {"muted": p["target"]}, 34, HORIZONTAL_ALIGNMENT_RIGHT)
	lvl.position = Vector2(600, 70)
	lvl.size = Vector2(408, 48)
	add_child(lvl)
	var ch: Label = UIKit.label(str(info["chapter"]), 32, p["muted"], 500, HORIZONTAL_ALIGNMENT_RIGHT)
	ch.position = Vector2(600, 120)
	ch.size = Vector2(408, 44)
	add_child(ch)
	# The room, with the winning path drawn over it.
	var frame: Panel = Panel.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(p["ink"], 0.05)
	sb.set_corner_radius_all(40)
	frame.add_theme_stylebox_override("panel", sb)
	# As big as fits in 560 x 720, in the room's own shape.
	var aspect: float = (float(level["w"]) + 0.6) / (float(level["h"]) + 0.6)
	var fh: float = 720.0
	var fw: float = fh * aspect
	if fw > 640.0:
		fw = 640.0
		fh = fw / aspect
	frame.position = Vector2((1080.0 - fw) * 0.5, 200.0 + (720.0 - fh) * 0.5)
	frame.size = Vector2(fw, fh)
	add_child(frame)
	var board: Board = Board.new()
	board.quiet = true
	board.input_enabled = false
	board.position = frame.position + Vector2(10, 10)
	board.size = frame.size - Vector2(20, 20)
	add_child(board)
	board.setup(level, p)
	board.show_path(info.get("arrows", {}))
	# Stars, title, and how it went.
	var stars: _StarRow = _StarRow.new()
	stars.earned = int(info["stars"])
	stars.pal = p
	stars.position = Vector2(0, 950)
	stars.size = Vector2(1080, 90)
	add_child(stars)
	var title: Label = UIKit.label(str(info["title"]), 76, p["ink"], 400)
	title.position = Vector2(0, 1040)
	title.size = Vector2(1080, 96)
	add_child(title)
	var sub: Label = UIKit.label("%s   %s" % [info["verdict"], info["stats"]], 32, p["muted"], 500)
	sub.position = Vector2(0, 1134)
	sub.size = Vector2(1080, 48)
	add_child(sub)
	# Footer: the dare, the address, and a QR code.
	var ask: Label = UIKit.label("Can you find the turns?", 34, p["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT)
	ask.position = Vector2(72, 1226)
	ask.size = Vector2(700, 48)
	add_child(ask)
	var url: Label = UIKit.label(SITE, 30, p["accent"], 600, HORIZONTAL_ALIGNMENT_LEFT)
	url.position = Vector2(72, 1272)
	url.size = Vector2(700, 44)
	add_child(url)
	var qr: TextureRect = TextureRect.new()
	qr.texture = load("res://assets/share/qr.png")
	qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	qr.position = Vector2(894, 1196)
	qr.size = Vector2(124, 124)
	add_child(qr)


func _draw() -> void:
	var top: Color = pal["top"]
	var bottom: Color = pal["bottom"]
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]), PackedColorArray([top, top, bottom, bottom]))
	# Soft dots, like the game's backdrop.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var dot: Color = Color(1, 1, 1, 0.3) if not bool(pal.get("dark", false)) else Color(1, 1, 1, 0.08)
	for i: int in 70:
		draw_circle(Vector2(rng.randf() * size.x, rng.randf() * size.y), rng.randf_range(2.0, 6.0), dot, true, -1.0, true)
	draw_line(Vector2(72, 1204), Vector2(860, 1204), Color(pal["ink"], 0.12), 2.0, true)


class _StarRow:
	extends Control
	var earned: int = 3
	var pal: Dictionary

	func _draw() -> void:
		for i: int in 3:
			var s: float = 84.0 if i == 1 else 70.0
			var c: Vector2 = Vector2(size.x * 0.5 + (float(i) - 1.0) * 108.0, size.y * 0.5 - (6.0 if i == 1 else 0.0))
			var r: Rect2 = Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
			if i < earned:
				draw_texture_rect(UIKit.icon("star-filled"), r, false, Color("#FFC53D"))
			else:
				draw_texture_rect(UIKit.icon("star"), r, false, Color(pal["ink"], 0.25))
