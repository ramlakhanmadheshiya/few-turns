extends Screen
## The shop: every pack with a live preview, its price, and whether it's yours.
## Tapping one opens its card (floating, like Settings) with perks, buy, and a
## video trial for the cosmetic packs.

var _rows: Dictionary = {}
var _status: Label
var _first: Control


func _ready() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.add_child(make_header("Shop", func() -> void: app.open_home()))
	var scroll: TouchScroll = TouchScroll.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	scroll.set_content(list)
	var sub: Label = UIKit.label("Every room in Few Turns opens by playing.\nThese are extras, and they help me make more.", 22, pal["muted"], 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(sub)
	for id: String in Store.PRODUCTS:
		var row: Button = _row(id)
		list.add_child(row)
		_rows[id] = row
		if _first == null:
			_first = row
		if id == "supporter_pack":
			list.add_child(_keys_row())
	list.add_child(_tip_row())
	_status = UIKit.label("", 20, pal["muted"], 500)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(_status)
	var restore: Button = UIKit.pill("Restore purchases", pal, "ghost", Vector2(340, 72), 24)
	restore.name = "Restore"
	restore.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restore.pressed.connect(func() -> void:
		_status.text = "Checking your purchases…"
		Store.restore()
	)
	list.add_child(restore)
	var foot: Label = UIKit.label("One-time purchases through Google Play. No subscriptions.", 18, pal["muted"], 400)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(foot)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	list.add_child(spacer)
	Store.restore_finished.connect(func(_ok: bool, msg: String) -> void:
		_status.text = msg
		_refresh_all()
	)
	Store.purchase_finished.connect(func(_ok: bool, msg: String, _id: String) -> void:
		_status.text = msg
		_refresh_all()
	)
	Store.price_updated.connect(func(_id: String, _p: String) -> void: _refresh_all())
	Events.purchases_changed.connect(_refresh_all)


func _refresh_all() -> void:
	if not is_inside_tree():
		return
	for id: String in _rows:
		(_rows[id] as Button).get_node("Margin/Row/Right").call("refresh")


## One shop row: preview tile, name and blurb, and price / owned state.
func _row(id: String) -> Button:
	var info: Dictionary = Store.PRODUCTS[id]
	var featured: bool = id == "complete_pack"
	var b: Button = Button.new()
	b.name = "Product_" + id
	b.custom_minimum_size = Vector2(0, 148 if featured else 128)
	b.focus_mode = Control.FOCUS_ALL
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(pal["ink"], 0.06)
	sb.set_corner_radius_all(32)
	sb.corner_detail = 10
	if featured:
		sb.bg_color = Color(pal["accent"], 0.14)
		sb.border_color = Color(pal["accent"], 0.8)
		sb.set_border_width_all(3)
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	var focus: StyleBoxFlat = sb.duplicate()
	focus.border_color = pal["accent"]
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	UIKit.add_press_feel(b)
	b.pressed.connect(func() -> void: app.open_product(id))
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20 if side in ["top", "bottom"] else 22)
	b.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var tile: ProductPreview = ProductPreview.new()
	tile.product = id
	tile.pal = pal
	tile.compact = true
	tile.custom_minimum_size = Vector2(96, 96)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tile)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	if featured:
		text.add_child(UIKit.caption("Best value  ·  save %d%%" % Store.complete_saving(), {"muted": pal["accent"]}, 16))
	text.add_child(UIKit.label(str(info["name"]), 30, pal["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	var blurb: Label = UIKit.label(str(info["blurb"]), 20, pal["muted"], 400, HORIZONTAL_ALIGNMENT_LEFT)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(blurb)
	var right: _PriceTag = _PriceTag.new()
	right.name = "Right"
	right.product = id
	right.pal = pal
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	right.refresh()
	return b


## Level keys: consumable, so a stepper card instead of a one-time pack.
func _keys_row() -> Button:
	var b: Button = Button.new()
	b.name = "Product_keys"
	b.custom_minimum_size = Vector2(0, 128)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(pal["ink"], 0.06)
	sb.set_corner_radius_all(32)
	sb.corner_detail = 10
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	UIKit.add_press_feel(b)
	b.pressed.connect(func() -> void: app.open_keys())
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 22
	row.offset_right = -22
	row.offset_top = 16
	row.offset_bottom = -16
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var tile: ProductPreview = ProductPreview.new()
	tile.product = "keys"
	tile.pal = pal
	tile.compact = true
	tile.custom_minimum_size = Vector2(96, 96)
	row.add_child(tile)
	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(UIKit.label("Level keys", 30, pal["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UIKit.label("Open any locked room  ·  10% off for 5+", 20, pal["muted"], 400, HORIZONTAL_ALIGNMENT_LEFT))
	var price: VBoxContainer = VBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(price)
	price.add_child(UIKit.label(Store.price("keys_1"), 26, pal["target"], 700, HORIZONTAL_ALIGNMENT_RIGHT))
	price.add_child(UIKit.label("per key", 16, pal["muted"], 600, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(UIKit.icon_rect("chevron-right", 28.0, pal["muted"]))
	return b


func _tip_row() -> Button:
	var b: Button = UIKit.pill("", pal, "soft", Vector2(0, 112), 24)
	b.name = "TipJar"
	b.pressed.connect(func() -> void: app.open_tips())
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 30
	row.offset_right = -30
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(UIKit.icon_rect("coffee", 44.0, pal["accent"]))
	var text: VBoxContainer = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(UIKit.label("Tip jar", 28, pal["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	var n: int = SaveSystem.tips_given()
	text.add_child(UIKit.label("Say thanks, as often as you like" if n == 0 else "You've tipped %d %s. Thank you ♥" % [n, "time" if n == 1 else "times"], 20, pal["muted"], 400, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(UIKit.icon_rect("chevron-right", 32.0, pal["muted"]))
	return b


func focus_default() -> void:
	if _first != null:
		_first.grab_focus()


func handle_back() -> bool:
	app.open_home()
	return true


## Price pill, "Owned" check, or the time left on a video trial (live).
class _PriceTag:
	extends HBoxContainer
	var product: String
	var pal: Dictionary
	var _clock: Label
	var _wait: float = 0.0

	func _process(delta: float) -> void:
		_wait -= delta
		if _wait <= 0.0:
			_wait = 0.25
			_tick()

	func _tick() -> void:
		if _clock == null or not is_instance_valid(_clock):
			return
		var c: String = SaveSystem.trial_clock(product)
		_clock.text = "trial · %s left" % c if not c.is_empty() else ""

	func refresh() -> void:
		for c: Node in get_children():
			c.queue_free()
		add_theme_constant_override("separation", 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if SaveSystem.bought(product):
			add_child(UIKit.icon_rect("check", 28.0, pal["accent"]))
			add_child(UIKit.label("Owned", 24, pal["accent"], 700))
			return
		var box: VBoxContainer = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		box.add_child(UIKit.label(Store.price(product), 26, pal["target"], 700, HORIZONTAL_ALIGNMENT_RIGHT))
		var left: int = SaveSystem.trial_left(product)
		if left > 0:
			var clock: Label = UIKit.label("", 16, pal["accent"], 700, HORIZONTAL_ALIGNMENT_RIGHT)
			clock.name = "TrialClock"
			box.add_child(clock)
			_clock = clock
			_tick()
		add_child(UIKit.icon_rect("chevron-right", 28.0, pal["muted"]))
