extends Screen
## Title screen: wordmark, a live attract-mode room, and one obvious Play button.

var _play: Button
var _board: Board


func _ready() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	var top: HBoxContainer = HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.custom_minimum_size = Vector2(0, 96)
	var shop: Button = UIKit.icon_button("shopping-bag", pal, 72.0)
	shop.name = "Shop"
	shop.pressed.connect(func() -> void: app.open_shop())
	top.add_child(shop)
	var fill: Control = Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	var settings: Button = UIKit.icon_button("settings", pal, 72.0)
	settings.name = "SettingsButton"
	settings.pressed.connect(func() -> void: app.open_settings(false))
	top.add_child(settings)
	col.add_child(top)

	# Title: the app icon, the name on one line, and a quiet tagline.
	var title_box: VBoxContainer = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	var icon: TextureRect = TextureRect.new()
	icon.name = "Logo"
	icon.texture = load("res://assets/icon.svg")
	icon.custom_minimum_size = Vector2(92, 92)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_box.add_child(icon)
	var fv: FontVariation = (UIKit.font(300) as FontVariation).duplicate()
	fv.spacing_glyph = 2
	var title: Label = UIKit.label("Few Turns", 88, pal["ink"], 300)
	title.name = "Title"
	title.add_theme_font_override("font", fv)
	title_box.add_child(title)
	title_box.add_child(UIKit.caption("A quiet arrow puzzle", {"muted": pal["accent"]}, 18, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(title_box)
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)

	# The live attract-mode room, on a soft floating card.
	var card: PanelContainer = PanelContainer.new()
	card.name = "DemoCard"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(260, 340)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var dark: bool = bool(pal.get("dark", false))
	sb.bg_color = Color(1, 1, 1, 0.06) if dark else Color(1, 1, 1, 0.42)
	sb.border_color = Color(pal["ink"], 0.06)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(44)
	sb.corner_detail = 12
	sb.shadow_color = Color(pal["ink"], 0.10)
	sb.shadow_size = 26
	sb.shadow_offset = Vector2(0, 10)
	for side: String in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 16)
	card.add_theme_stylebox_override("panel", sb)
	col.add_child(card)
	var demo_level: Dictionary = Levels.level("ch1", 13)
	if demo_level.is_empty():
		demo_level = Levels.level("ch1", 0)
	# Hug the room: the card is as wide as the room's shape at this height.
	var aspect: float = (float(demo_level.get("w", 5)) + 0.6) / (float(demo_level.get("h", 7)) + 0.6)
	card.resized.connect(func() -> void:
		var want: float = (card.size.y - 32.0) * aspect + 32.0
		if absf(card.custom_minimum_size.x - want) > 2.0:
			card.custom_minimum_size.x = want
	)
	_board = Board.new()
	_board.demo = true
	_board.quiet = true
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_board)
	_board.setup(demo_level, pal)

	var bottom: VBoxContainer = VBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.custom_minimum_size = Vector2(0, 260)
	var target: Dictionary = Levels.continue_target()
	var cpal: Dictionary = Palette.get_palette(str(target["chapter"]))
	_play = UIKit.pill("", pal, "primary", Vector2(320, 96), 36)
	_play.name = "Play"
	_with_icon(_play, "play", "Play", 36, pal["top"], 30.0)
	_play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play.pressed.connect(func() -> void: app.open_game(str(target["chapter"]), int(target["index"])))
	bottom.add_child(_play)
	# Where Play picks up: a small chip in the chapter's own colour.
	var chip: _ContinueChip = _ContinueChip.new()
	chip.name = "Continue"
	chip.pal = pal
	chip.dot = cpal["accent"]
	chip.text = "%s  ·  LEVEL %d" % [str(cpal["name"]).to_upper(), int(target["index"]) + 1]
	chip.stars = SaveSystem.total_stars()
	chip.custom_minimum_size = Vector2(0, 40)
	bottom.add_child(chip)
	var levels: Button = UIKit.pill("", pal, "ghost", Vector2(240, 72), 26)
	levels.name = "Chapters"
	_with_icon(levels, "layout-grid", "Chapters", 26, pal["ink"], 24.0)
	levels.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	levels.pressed.connect(func() -> void: app.open_chapters())
	bottom.add_child(levels)
	col.add_child(bottom)

	_play.focus_neighbor_bottom = levels.get_path()
	levels.focus_neighbor_top = _play.get_path()
	_play.pivot_offset = _play.custom_minimum_size * 0.5
	var tw: Tween = create_tween().set_loops()
	tw.tween_property(_play, "scale", Vector2(1.035, 1.035), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_play, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_play.button_down.connect(func() -> void: tw.kill())


## Puts an icon right beside a button's word, centred together.
func _with_icon(b: Button, icon_name: String, text: String, font_size: int, color: Color, icon_size: float) -> void:
	b.tooltip_text = text
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var ic: TextureRect = UIKit.icon_rect(icon_name, icon_size, color)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l: Label = UIKit.label(text, font_size, color, 600)
	l.name = "Text"
	row.add_child(l)


func focus_default() -> void:
	if _play != null:
		_play.grab_focus()


## "● DAWN · LEVEL 13   ★ 34": where Play continues, and the stars so far.
class _ContinueChip:
	extends Control
	var pal: Dictionary
	var dot: Color
	var text: String = ""
	var stars: int = 0

	func _draw() -> void:
		var f: Font = UIKit.font(700)
		var fs: int = 18
		var label: String = text
		var star_text: String = "★ %d" % stars
		var w1: float = f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w2: float = f.get_string_size(star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var gap: float = 26.0
		var pad: float = 20.0
		var total: float = 14.0 + 10.0 + w1 + gap + w2 + pad * 2.0
		var r: Rect2 = Rect2(Vector2((size.x - total) * 0.5, 0), Vector2(total, size.y))
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(pal["ink"], 0.06)
		sb.set_corner_radius_all(int(size.y * 0.5))
		draw_style_box(sb, r)
		var y: float = r.get_center().y
		var x: float = r.position.x + pad
		draw_circle(Vector2(x + 7.0, y), 7.0, dot, true, -1.0, true)
		x += 24.0
		var base: float = y + (f.get_ascent(fs) - f.get_descent(fs)) * 0.5
		draw_string(f, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(pal["ink"], 0.7))
		x += w1 + gap
		draw_string(f, Vector2(x, base), star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#E0A21A"))
