extends Overlay
## Pick an orb style or a colour theme. Locked ones open their pack's card
## (buy, or try it free for an hour with a video).

## "orbs" or "themes".
var mode: String = "orbs"
var _clock: Label
var _product: String = ""


func _process(_delta: float) -> void:
	if _clock != null:
		var c: String = SaveSystem.trial_clock(_product)
		_clock.text = "On trial  ·  %s left" % c if not c.is_empty() else "Trial over"


func _init() -> void:
	scrollable = true


func build() -> void:
	name = "Picker"
	add_title("Orbs" if mode == "orbs" else "Colours")
	var body: VBoxContainer = card_body()
	var product: String = "orb_pack" if mode == "orbs" else "theme_pack"
	var owned: bool = SaveSystem.owns(product)
	var current: String = SaveSystem.orb_style() if mode == "orbs" else Palette.theme_id
	var left: int = SaveSystem.trial_left(product)
	if left > 0 and not SaveSystem.bought(product):
		_clock = UIKit.label("", 20, pal["accent"], 600)
		_clock.name = "TrialClock"
		body.add_child(_clock)
		_product = product
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	body.add_child(grid)
	var ids: Array = OrbStyles.ids() if mode == "orbs" else Palette.theme_ids()
	for id: String in ids:
		var free: bool = OrbStyles.is_free(id) if mode == "orbs" else id == "chapters"
		var locked: bool = not free and not owned
		var tile: Button = _tile(id, id == current, locked)
		tile.pressed.connect(func() -> void:
			if locked:
				app.open_product(product, func() -> void: app.open_picker(mode))
				return
			SaveSystem.set_setting("orb_style" if mode == "orbs" else "theme", id)
			AudioManager.play_ui("ui_toggle")
			if mode == "themes":
				app.apply_theme()
			app.open_picker(mode)
		)
		grid.add_child(tile)
		if id == current:
			_first_focus = tile
	if not SaveSystem.bought(product):
		add_gap(8)
		var get_btn: Button = UIKit.pill("Get the %s" % Store.display_name(product), pal, "ghost", Vector2(0, 84), 26)
		get_btn.name = "GetPack"
		get_btn.pressed.connect(func() -> void: app.open_product(product, func() -> void: app.open_picker(mode)))
		body.add_child(get_btn)


func _tile(id: String, selected: bool, locked: bool) -> Button:
	var b: Button = Button.new()
	b.name = "Pick_" + id
	b.custom_minimum_size = Vector2(250, 130)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(pal["ink"], 0.06)
	sb.set_corner_radius_all(28)
	sb.corner_detail = 8
	if selected:
		sb.border_color = pal["target"]
		sb.set_border_width_all(4)
	for state: String in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, sb)
	var focus: StyleBoxFlat = sb.duplicate()
	focus.border_color = pal["accent"]
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	UIKit.add_press_feel(b)
	var art: _Swatch = _Swatch.new()
	art.mode = mode
	art.id = id
	art.pal = pal
	art.dim = locked
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -40
	art.offset_top = 10
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(art)
	var name_l: Label = UIKit.label(OrbStyles.display_name(id) if mode == "orbs" else Palette.theme_name(id), 22, Color(pal["ink"], 0.5 if locked else 1.0), 600)
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -46
	name_l.offset_bottom = -10
	b.add_child(name_l)
	if locked:
		var lock: TextureRect = UIKit.icon_rect("lock", 22.0, Color(pal["ink"], 0.45))
		lock.position = Vector2(14, 12)
		b.add_child(lock)
	return b


## An orb with its trail, or a theme's light and deep colours.
class _Swatch:
	extends Control
	var mode: String
	var id: String
	var pal: Dictionary
	var dim: bool = false
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		if mode == "orbs":
			var trail: Array = []
			for k: int in 16:
				var x: float = -60.0 + 7.0 * float(k)
				trail.append(c + Vector2(x + fmod(_t * 30.0, 7.0), sin((x + _t * 60.0) * 0.05) * 8.0))
			if dim:
				modulate.a = 0.55
			OrbStyles.draw_trail(self, id, trail, pal, _t, 14.0)
			OrbStyles.draw_orb(self, id, trail[-1], 14.0, pal, _t, true)
			return
		var p: Dictionary = Palette.get_palette("ch1") if id == "chapters" else Palette.themed(Palette.CHAPTERS["ch1"], id)
		var alpha: float = 0.55 if dim else 1.0
		if id == "chapters":
			# Chapter colours: a strip of every chapter's tone.
			var ids: Array = Palette.ids()
			var w: float = 26.0
			for i: int in ids.size():
				var cp: Dictionary = Palette.CHAPTERS[ids[i]]
				var pos: Vector2 = c + Vector2((float(i) - float(ids.size() - 1) * 0.5) * (w * 0.8), 0)
				draw_circle(pos, w * 0.5, Color(cp["bottom"], alpha), true, -1.0, true)
				draw_circle(pos, w * 0.22, Color(cp["accent"], alpha), true, -1.0, true)
			return
		for k: int in 2:
			var r: Rect2 = Rect2(c + Vector2(-70.0 + 74.0 * float(k), -30), Vector2(66, 60))
			var sb: StyleBoxFlat = StyleBoxFlat.new()
			sb.set_corner_radius_all(14)
			sb.bg_color = Color(p["top"] if k == 0 else p["bottom"], alpha)
			sb.border_color = Color(pal["ink"], 0.15)
			sb.set_border_width_all(1)
			draw_style_box(sb, r)
			draw_circle(r.get_center() + Vector2(-10, 4), 9.0, Color(p["target"], alpha), true, -1.0, true)
			draw_line(r.get_center() + Vector2(4, -10), r.get_center() + Vector2(22, -10), Color(p["ink"], alpha), 4.0, true)
			draw_circle(r.get_center() + Vector2(14, 10), 4.0, Color(p["accent"], alpha), true, -1.0, true)
