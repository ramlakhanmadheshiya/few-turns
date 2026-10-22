extends Screen
## One chapter's 40 rooms as a grid of square tiles. Every number is shown, open
## or locked, so the whole chapter is visible at a glance. A hero card shows the
## chapter's idea and progress; the key chip shows level keys.

var chapter_id: String = "ch1"
var _focus: Control
var _scroll: TouchScroll
var _keys_label: Label
var _tiles: Array = []


func music_track() -> String:
	return chapter_id


func _ready() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(make_header(str(pal["name"]), func() -> void: app.open_chapters()))
	var scroll: TouchScroll = TouchScroll.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_scroll = scroll
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	scroll.set_content(list)
	list.add_child(_hero())
	list.add_child(_key_row())
	var next: Dictionary = Levels.continue_target()
	var total: int = Levels.level_count(chapter_id)
	var center: CenterContainer = CenterContainer.new()
	list.add_child(center)
	var grid: GridContainer = GridContainer.new()
	grid.name = "Grid"
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	center.add_child(grid)
	for i: int in total:
		var lv: Dictionary = Levels.level(chapter_id, i)
		var tile: _LevelTile = _LevelTile.new()
		tile.name = "Level_%d" % (i + 1)
		tile.pal = pal
		tile.number = i + 1
		tile.stars = SaveSystem.stars_for(str(lv["id"]))
		tile.open = Levels.level_open(chapter_id, i)
		tile.keyed = SaveSystem.key_unlocked(str(lv["id"])) and not SaveSystem.is_cleared(str(lv["id"]))
		tile.current = str(next["chapter"]) == chapter_id and int(next["index"]) == i
		tile.pressed.connect(_on_tile.bind(i))
		grid.add_child(tile)
		_tiles.append(tile)
		if tile.current or (_focus == null and tile.open):
			_focus = tile
		tile.modulate.a = 0.0
		var tw: Tween = create_tween()
		tw.tween_interval(0.012 * float(i))
		tw.tween_property(tile, "modulate:a", 1.0, 0.22)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	list.add_child(spacer)
	Events.keys_changed.connect(func(_c: int) -> void: _refresh_keys())
	# Bring the current room into view, keeping the hero card when it fits.
	(func() -> void:
		if _focus != null and _focus.is_inside_tree():
			var bottom: float = _focus.global_position.y - _scroll.content.global_position.y + _focus.size.y + 24.0
			if bottom > _scroll.size.y:
				_scroll.scroll_to(bottom - _scroll.size.y * 0.8)
	).call_deferred()


func _on_tile(i: int) -> void:
	if Levels.level_open(chapter_id, i):
		app.open_game(chapter_id, i)
	else:
		AudioManager.play_ui("ui_back")
		app.open_locked(chapter_id, i)


func _refresh_keys() -> void:
	if _keys_label != null and is_instance_valid(_keys_label):
		var k: int = SaveSystem.keys()
		_keys_label.text = "%d %s" % [k, "key" if k == 1 else "keys"]
	for i: int in _tiles.size():
		var t: _LevelTile = _tiles[i]
		var id: String = str(Levels.level(chapter_id, i)["id"])
		t.open = Levels.level_open(chapter_id, i)
		t.keyed = SaveSystem.key_unlocked(id) and not SaveSystem.is_cleared(id)
		t.queue_redraw()


## The chapter at a glance: its live scene, progress and stars.
func _hero() -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.name = "Hero"
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(pal["bottom"], 0.55)
	sb.set_corner_radius_all(36)
	sb.corner_detail = 10
	sb.content_margin_left = 30
	sb.content_margin_right = 22
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	var v: VBoxContainer = VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var top: HBoxContainer = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	v.add_child(top)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	top.add_child(text)
	text.add_child(UIKit.caption("Chapter %d" % (Levels.chapter_index(chapter_id) + 1), {"muted": pal["accent"]}, 17))
	text.add_child(UIKit.label(str(pal["tagline"]), 30, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT))
	var total: int = Levels.level_count(chapter_id)
	text.add_child(UIKit.label("★ %d / %d" % [Levels.stars_in(chapter_id), total * 3], 22, pal["muted"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	var art: ChapterArt = ChapterArt.new()
	art.chapter_id = chapter_id
	art.pal = pal
	art.custom_minimum_size = Vector2(230, 116)
	top.add_child(art)
	var bar: _Progress = _Progress.new()
	bar.pal = pal
	bar.total = total
	bar.open = Levels.open_in(chapter_id)
	bar.cleared = Levels.cleared_in(chapter_id)
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	var legend: Label = UIKit.label("%d of %d open  ·  %d cleared  ·  %d locked" % [bar.open, total, bar.cleared, total - bar.open], 19, pal["muted"], 500, HORIZONTAL_ALIGNMENT_LEFT)
	legend.name = "Legend"
	v.add_child(legend)
	return card


func _key_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var chip: Button = UIKit.pill("", pal, "soft", Vector2(170, 56), 20)
	chip.name = "Keys"
	chip.icon = UIKit.icon("key-round")
	chip.add_theme_constant_override("icon_max_width", 24)
	for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		chip.add_theme_color_override(key, pal["accent"])
	chip.pressed.connect(func() -> void: app.open_keys())
	row.add_child(chip)
	_keys_label = UIKit.label("", 20, pal["ink"], 600)
	chip.text = ""
	chip.add_child(_keys_label)
	_keys_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_keys_label.offset_left = 44
	_refresh_keys()
	return row


func focus_default() -> void:
	if _focus != null:
		_focus.grab_focus()


func handle_back() -> bool:
	app.open_chapters()
	return true


## Open (light) and cleared (solid) shares of the chapter.
class _Progress:
	extends Control
	var pal: Dictionary
	var total: int = 40
	var open: int = 0
	var cleared: int = 0

	func _draw() -> void:
		var r: float = size.y * 0.5
		_bar(size.x, Color(pal["ink"], 0.1), r)
		_bar(size.x * float(open) / float(maxi(1, total)), Color(pal["accent"], 0.35), r)
		_bar(size.x * float(cleared) / float(maxi(1, total)), pal["accent"], r)

	func _bar(w: float, col: Color, r: float) -> void:
		if w <= 0.5:
			return
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(r))
		draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(maxf(w, size.y), size.y)))


class _LevelTile:
	extends Button
	var pal: Dictionary
	var number: int = 1
	var stars: int = 0
	var open: bool = false
	var current: bool = false
	var keyed: bool = false
	var _t: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(108, 118)
		focus_mode = Control.FOCUS_ALL
		flat = true
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for key: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(key, empty)

	func _ready() -> void:
		UIKit.add_press_feel(self)

	func _process(delta: float) -> void:
		_t += delta
		if current or has_focus():
			queue_redraw()

	func _draw() -> void:
		var ink: Color = pal["ink"]
		var box: Rect2 = Rect2(Vector2(4, 4), Vector2(size.x - 8, size.x - 8))
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.set_corner_radius_all(26)
		sb.corner_detail = 8
		var f: Font = UIKit.font(500)
		var cleared: bool = stars > 0
		if has_focus():
			var fsb: StyleBoxFlat = sb.duplicate()
			fsb.bg_color = Color.TRANSPARENT
			fsb.border_color = pal["accent"]
			fsb.set_border_width_all(3)
			draw_style_box(fsb, box.grow(5))
		if not open:
			sb.bg_color = Color(ink, 0.05)
			sb.border_color = Color(ink, 0.08)
			sb.set_border_width_all(2)
			draw_style_box(sb, box)
			_text(f, str(number), box.get_center() + Vector2(0, -4), 34, Color(ink, 0.32))
			# A small lock badge in the corner.
			var c: Vector2 = box.end - Vector2(18, 18)
			draw_circle(c, 14.0, pal["top"], true, -1.0, true)
			draw_texture_rect(UIKit.icon("lock"), Rect2(c - Vector2(9, 9), Vector2(18, 18)), false, Color(ink, 0.45))
			return
		if cleared:
			sb.bg_color = ink
			draw_style_box(sb, box)
			_text(f, str(number), box.get_center() + Vector2(0, -10), 34, pal["top"])
			for k: int in 3:
				var p: Vector2 = box.get_center() + Vector2((float(k) - 1.0) * 16.0, 22)
				var s: float = 14.0
				var col: Color = Color("#FFC53D") if k < stars else Color(pal["top"], 0.25)
				draw_texture_rect(UIKit.icon("star-filled"), Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, col)
		else:
			sb.bg_color = Color(pal["accent"], 0.16) if current else Color(ink, 0.04)
			sb.border_color = pal["accent"] if current else Color(ink, 0.45)
			sb.set_border_width_all(3)
			draw_style_box(sb, box)
			_text(f, str(number), box.get_center() + Vector2(0, -4), 34, ink)
		if current:
			var pulse: float = 0.5 + 0.5 * sin(_t * 3.0)
			var glow: StyleBoxFlat = sb.duplicate()
			glow.bg_color = Color.TRANSPARENT
			glow.border_color = Color(pal["accent"], 0.7 - 0.5 * pulse)
			glow.set_border_width_all(3)
			draw_style_box(glow, box.grow(4.0 + 4.0 * pulse))
		if keyed:
			var kc: Vector2 = box.end - Vector2(18, 18)
			draw_circle(kc, 14.0, pal["accent"], true, -1.0, true)
			draw_texture_rect(UIKit.icon("key-round"), Rect2(kc - Vector2(9, 9), Vector2(18, 18)), false, Color.WHITE)

	func _text(f: Font, s: String, centre: Vector2, fs: int, col: Color) -> void:
		var w: Vector2 = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var asc: float = f.get_ascent(fs)
		var desc: float = f.get_descent(fs)
		draw_string(f, Vector2(centre.x - w.x * 0.5, centre.y + (asc - desc) * 0.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
