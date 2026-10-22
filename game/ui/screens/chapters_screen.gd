extends Screen
## A calm vertical list of chapters, each card painted in its own palette.

var _first: Control


func _ready() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	col.add_child(make_header("Chapters", func() -> void: app.open_home()))
	var total_stars: Label = UIKit.label("★ %d / %d" % [SaveSystem.total_stars(), Levels.total_levels() * 3], 24, pal["muted"], 600)
	total_stars.name = "TotalStars"
	col.add_child(total_stars)
	var scroll: TouchScroll = TouchScroll.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 18)
	scroll.set_content(list)
	var prev: Control = null
	for i: int in Levels.chapters.size():
		var c: Dictionary = Levels.chapters[i]
		var card: Button = _card(c, i)
		list.add_child(card)
		if prev == null:
			_first = card
		else:
			card.focus_neighbor_top = prev.get_path()
			prev.focus_neighbor_bottom = card.get_path()
		prev = card
		card.modulate.a = 0.0
		card.position.y += 30
		var tw: Tween = create_tween()
		tw.tween_interval(0.05 * float(i))
		tw.tween_property(card, "modulate:a", 1.0, 0.3)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	list.add_child(spacer)


func _card(c: Dictionary, index: int) -> Button:
	var id: String = str(c["id"])
	var cp: Dictionary = Palette.get_palette(id)
	var open: bool = Levels.chapter_open(id)
	var b: Button = Button.new()
	b.name = "Chapter_" + id
	b.custom_minimum_size = Vector2(0, 200)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = cp["bottom"]
	sb.set_corner_radius_all(36)
	sb.corner_detail = 12
	sb.anti_aliasing = true
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	var focus: StyleBoxFlat = sb.duplicate()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = pal["accent"]
	focus.set_border_width_all(4)
	focus.expand_margin_left = 6
	focus.expand_margin_right = 6
	focus.expand_margin_top = 6
	focus.expand_margin_bottom = 6
	b.add_theme_stylebox_override("focus", focus)
	UIKit.add_press_feel(b)
	var bg: Control = _CardBack.new()
	bg.pal = cp
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bg)
	# The chapter's idea, playing out on the right half of the card.
	var art: ChapterArt = ChapterArt.new()
	art.name = "Art"
	art.chapter_id = id
	art.pal = cp
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.resized.connect(func() -> void: art.area = Rect2(art.size.x * 0.44, 14.0, art.size.x * 0.54, art.size.y - 28.0))
	b.add_child(art)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 34)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	b.add_child(margin)
	var text: VBoxContainer = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(text)
	text.add_child(UIKit.label("%02d" % (index + 1), 22, cp["muted"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UIKit.label(str(cp["name"]), 48, cp["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UIKit.label(str(cp["tagline"]), 22, cp["muted"], 400, HORIZONTAL_ALIGNMENT_LEFT))
	var total: int = Levels.level_count(id)
	var status: HBoxContainer = HBoxContainer.new()
	status.add_theme_constant_override("separation", 10)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(status)
	if open:
		status.add_child(UIKit.label("★ %d/%d" % [Levels.stars_in(id), total * 3], 22, cp["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT))
		status.add_child(UIKit.label("·  %d/%d cleared" % [Levels.cleared_in(id), total], 20, cp["muted"], 500, HORIZONTAL_ALIGNMENT_LEFT))
		b.pressed.connect(func() -> void: app.open_levels(id))
	else:
		status.add_child(UIKit.icon_rect("lock", 26.0, cp["ink"]))
		var prev_name: String = str(Palette.get_palette(str(Levels.chapters[index - 1]["id"]))["name"])
		var left: int = Levels.CHAPTER_GATE - Levels.cleared_in(str(Levels.chapters[index - 1]["id"]))
		status.add_child(UIKit.label("%d more in %s" % [left, prev_name], 20, cp["muted"], 500, HORIZONTAL_ALIGNMENT_LEFT))
		art.modulate.a = 0.45
		art.playing = false
		# Still worth a look: every room is listed, and a key opens any of them.
		b.pressed.connect(func() -> void: app.open_levels(id))
	return b


func focus_default() -> void:
	if _first != null:
		_first.grab_focus()


func handle_back() -> bool:
	app.open_home()
	return true


## The card's face: the chapter's light colour fading into its deeper one.
class _CardBack:
	extends Control
	var pal: Dictionary

	func _draw() -> void:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.set_corner_radius_all(36)
		sb.corner_detail = 12
		sb.anti_aliasing = true
		sb.bg_color = pal["top"]
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		# A soft panel behind the scene so it reads as a little window into the chapter.
		var art: StyleBoxFlat = sb.duplicate()
		art.bg_color = Color(pal["bottom"], 0.45)
		art.set_corner_radius_all(26)
		draw_style_box(art, Rect2(Vector2(size.x * 0.44, 12.0), Vector2(size.x * 0.54, size.y - 24.0)))
