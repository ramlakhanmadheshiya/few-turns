class_name UIKit
extends RefCounted
## Small design system: one typeface in a few weights, pill buttons, round icon
## buttons and labels. Everything is built in code from the active palette.

const FONT_PATH: String = "res://assets/fonts/Outfit-Variable.ttf"
const ICON_DIR: String = "res://assets/icons/"

static var _fonts: Dictionary = {}
static var _icons: Dictionary = {}


static func font(weight: int = 400) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var base: FontFile = load(FONT_PATH) as FontFile
	var fv: FontVariation = FontVariation.new()
	fv.base_font = base
	var ts: TextServer = TextServerManager.get_primary_interface()
	fv.variation_opentype = {ts.name_to_tag("wght"): weight}
	_fonts[weight] = fv
	return fv


static func icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = load(ICON_DIR + name + ".svg") as Texture2D
	return _icons[name]


static func label(text: String, size: int, color: Color, weight: int = 400, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The floating card used by every overlay (settings, shop, results...).
static func card_style(pal: Dictionary) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var dark: bool = bool(pal.get("dark", false))
	sb.bg_color = (pal["top"] as Color).lightened(0.06) if dark else (pal["top"] as Color).lerp(Color.WHITE, 0.4)
	sb.set_corner_radius_all(44)
	sb.corner_detail = 12
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 36
	sb.content_margin_bottom = 36
	sb.shadow_color = Color(0, 0, 0, 0.16)
	sb.shadow_size = 30
	return sb


## Small uppercase caption with letter spacing, e.g. "MADE BY".
static func caption(text: String, pal: Dictionary, size: int = 18, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l: Label = label(text.to_upper(), size, pal["muted"], 600, align)
	var fv: FontVariation = (font(600) as FontVariation).duplicate()
	fv.spacing_glyph = 3
	l.add_theme_font_override("font", fv)
	return l


static func icon_rect(name: String, size: float, color: Color) -> TextureRect:
	var ic: TextureRect = TextureRect.new()
	ic.texture = icon(name)
	ic.custom_minimum_size = Vector2(size, size)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = color
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


static func _box(fill: Color, radius: int, border: Color = Color.TRANSPARENT, border_w: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(radius)
	s.corner_detail = 12
	s.anti_aliasing = true
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.content_margin_left = 28
	s.content_margin_right = 28
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## A rounded "pill" button. style: "primary" (solid ink), "ghost" (outline) or "soft".
static func pill(text: String, pal: Dictionary, style: String = "primary", min_size: Vector2 = Vector2(280, 84), font_size: int = 30) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font(600))
	b.add_theme_font_size_override("font_size", font_size)
	var ink: Color = pal["ink"]
	var bg: Color = pal["top"]
	var fill: Color
	var text_c: Color
	var border: Color = Color.TRANSPARENT
	var bw: int = 0
	match style:
		"primary":
			fill = ink
			text_c = bg
		"accent":
			fill = pal["accent"]
			text_c = Color.WHITE
		"soft":
			fill = Color(ink, 0.08)
			text_c = ink
		"text":
			fill = Color(ink, 0.0)
			text_c = Color(ink, 0.6)
		_:
			fill = Color(ink, 0.0)
			text_c = ink
			border = Color(ink, 0.22)
			bw = 3
	var radius: int = int(min_size.y * 0.5)
	b.add_theme_stylebox_override("normal", _box(fill, radius, border, bw))
	b.add_theme_stylebox_override("hover", _box(fill.lerp(Color.WHITE, 0.08) if style == "primary" else Color(ink, fill.a + 0.05), radius, border, bw))
	b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.08) if style == "primary" else Color(ink, fill.a + 0.1), radius, border, bw))
	var focus: StyleBoxFlat = _box(Color.TRANSPARENT, radius, Color(pal["accent"], 0.9), 3)
	focus.expand_margin_left = 6
	focus.expand_margin_right = 6
	focus.expand_margin_top = 6
	focus.expand_margin_bottom = 6
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", _box(Color(ink, 0.06), radius))
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, text_c)
	b.add_theme_color_override("font_disabled_color", Color(ink, 0.35))
	add_press_feel(b)
	return b


## A round icon button with an optional soft backing circle.
static func icon_button(icon_name: String, pal: Dictionary, diameter: float = 72.0, backed: bool = true) -> Button:
	var b: Button = Button.new()
	b.icon = icon(icon_name)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(diameter, diameter)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_ALL
	var ink: Color = pal["ink"]
	var fill: Color = Color(ink, 0.07) if backed else Color.TRANSPARENT
	var r: int = int(diameter)
	var normal: StyleBoxFlat = _box(fill, r)
	var pad: float = diameter * 0.27
	for s: StyleBoxFlat in [normal]:
		s.content_margin_left = pad
		s.content_margin_right = pad
		s.content_margin_top = pad
		s.content_margin_bottom = pad
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(ink, fill.a + 0.06)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(ink, fill.a + 0.12)
	var focus: StyleBoxFlat = normal.duplicate()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(pal["accent"], 0.9)
	focus.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", normal)
	for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color", "icon_hover_pressed_color"]:
		b.add_theme_color_override(key, ink)
	b.add_theme_color_override("icon_disabled_color", Color(ink, 0.3))
	b.add_theme_font_override("font", font(600))
	b.add_theme_font_size_override("font_size", 22)
	for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, ink)
	add_press_feel(b)
	return b


## Squash on press, springy release, and a soft tap sound.
static func add_press_feel(c: Control) -> void:
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	if c is BaseButton:
		var b: BaseButton = c
		b.button_down.connect(func() -> void:
			var tw: Tween = b.create_tween()
			tw.tween_property(b, "scale", Vector2(0.93, 0.93), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			Haptics.tap(6)
		)
		b.button_up.connect(func() -> void:
			var tw: Tween = b.create_tween()
			tw.tween_property(b, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		)
		b.pressed.connect(func() -> void: AudioManager.play_ui("ui_tap"))


## A labelled on/off row used by the settings sheet.
## `on_info` (optional) makes the label tappable, with a small info mark, to explain
## what the setting does.
static func toggle_row(text: String, value: bool, pal: Dictionary, on_change: Callable, on_info: Callable = Callable()) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 76)
	if on_info.is_valid():
		var info: Button = Button.new()
		info.name = "Info"
		info.flat = true
		info.text = text
		info.icon = icon("info")
		info.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_theme_constant_override("icon_max_width", 22)
		info.add_theme_constant_override("h_separation", 10)
		info.add_theme_font_override("font", font(500))
		info.add_theme_font_size_override("font_size", 28)
		for key: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			info.add_theme_color_override(key, pal["ink"])
		for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			info.add_theme_color_override(key, Color(pal["ink"], 0.4))
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		for key: String in ["normal", "hover", "pressed", "focus"]:
			info.add_theme_stylebox_override(key, empty)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.pressed.connect(on_info)
		row.add_child(info)
	else:
		var l: Label = label(text, 28, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
	var sw: CheckButton = CheckButton.new()
	sw.button_pressed = value
	sw.focus_mode = Control.FOCUS_ALL
	sw.add_theme_icon_override("checked", _switch_texture(true, pal))
	sw.add_theme_icon_override("unchecked", _switch_texture(false, pal))
	sw.add_theme_icon_override("checked_disabled", _switch_texture(true, pal))
	sw.add_theme_icon_override("unchecked_disabled", _switch_texture(false, pal))
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	for key: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		sw.add_theme_stylebox_override(key, empty)
	sw.toggled.connect(func(on: bool) -> void:
		AudioManager.play_ui("ui_toggle")
		Haptics.tap(8)
		on_change.call(on)
	)
	row.add_child(sw)
	return row


## A labelled 0..1 volume slider. Plays a tick while dragging so you hear the level.
static func slider_row(text: String, value: float, pal: Dictionary, on_change: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 76)
	row.add_theme_constant_override("separation", 20)
	var l: Label = label(text, 28, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT)
	l.custom_minimum_size = Vector2(130, 0)
	row.add_child(l)
	var s: HSlider = HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_ALL
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(pal["ink"], 0.14)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = pal["accent"]
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob: Texture2D = _knob_texture(pal, false)
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", _knob_texture(pal, true))
	s.add_theme_icon_override("grabber_disabled", knob)
	s.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		AudioManager.play("ui_toggle", 1.0)
	)
	row.add_child(s)
	return row


static func _knob_texture(pal: Dictionary, focused: bool) -> Texture2D:
	var d: int = 40
	var img: Image = Image.create(d, d, false, Image.FORMAT_RGBA8)
	var c: Vector2 = Vector2(d, d) * 0.5
	for y: int in d:
		for x: int in d:
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var ring: float = clampf(d * 0.5 - dist + 0.5, 0.0, 1.0)
			var inner: float = clampf(d * 0.5 - 5.0 - dist + 0.5, 0.0, 1.0)
			var edge: Color = pal["accent"] if focused else Color(pal["ink"], 0.18)
			var col: Color = Color(edge, edge.a * ring).blend(Color(1, 1, 1, inner))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Draws a minimal switch into an image so CheckButton can use it as an icon.
static func _switch_texture(on: bool, pal: Dictionary) -> Texture2D:
	var w: int = 92
	var h: int = 52
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track: Color = pal["accent"] if on else Color(pal["ink"], 0.18)
	var knob: Color = Color.WHITE
	var r: float = h * 0.5
	for y: int in h:
		for x: int in w:
			var px: Vector2 = Vector2(x + 0.5, y + 0.5)
			var cx: float = clampf(px.x, r, w - r)
			var d: float = px.distance_to(Vector2(cx, r))
			var a: float = clampf(r - d + 0.5, 0.0, 1.0)
			var c: Color = Color(track, track.a * a)
			var kc: Vector2 = Vector2(w - r if on else r, r)
			var kd: float = px.distance_to(kc)
			var ka: float = clampf(r - 5.0 - kd + 0.5, 0.0, 1.0)
			c = c.blend(Color(knob, ka))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
