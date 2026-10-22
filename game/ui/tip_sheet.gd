extends Overlay
## The tip jar: say thanks, as often as you like. A tip opens nothing new.
## Four quick amounts, or type your own (Google Play sells fixed prices, so a
## custom tip rounds to the nearest 10).

var _status: Label
var _amount: LineEdit
var _custom_btn: Button


func build() -> void:
	name = "Tips"
	add_title("Tip jar")
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 14)
	var sub: Label = UIKit.label("Say thanks, as often as you like. A tip opens nothing new: it all goes into making the next chapter.", 22, pal["muted"], 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(sub)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	for rupees: int in Store.TIP_PRESETS:
		var id: String = "tip_%d" % rupees
		var b: Button = UIKit.pill(Store.price(id), pal, "soft", Vector2(0, 84), 28)
		b.name = "Tip_%d" % rupees
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: _tip(rupees))
		grid.add_child(b)
		if _first_focus == null:
			_first_focus = b
	add_gap(4)
	body.add_child(UIKit.caption("Or your own amount", pal, 16, HORIZONTAL_ALIGNMENT_CENTER))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	body.add_child(row)
	var minus: Button = UIKit.icon_button("minus", pal, 68.0)
	minus.name = "TipMinus"
	minus.pressed.connect(func() -> void: _nudge(-1))
	row.add_child(minus)
	_amount = LineEdit.new()
	_amount.name = "TipAmount"
	_amount.text = "500"
	_amount.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount.custom_minimum_size = Vector2(200, 72)
	_amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_amount.max_length = 5
	_amount.add_theme_font_override("font", UIKit.font(500))
	_amount.add_theme_font_size_override("font_size", 34)
	_amount.add_theme_color_override("font_color", pal["ink"])
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(pal["ink"], 0.06)
	box.set_corner_radius_all(36)
	box.border_color = Color(pal["ink"], 0.15)
	box.set_border_width_all(2)
	_amount.add_theme_stylebox_override("normal", box)
	var focus: StyleBoxFlat = box.duplicate()
	focus.border_color = pal["accent"]
	_amount.add_theme_stylebox_override("focus", focus)
	_amount.text_changed.connect(func(_t: String) -> void: _refresh_custom())
	_amount.text_submitted.connect(func(_t: String) -> void: _amount.text = str(_custom()))
	row.add_child(_amount)
	var plus: Button = UIKit.icon_button("plus", pal, 68.0)
	plus.name = "TipPlus"
	plus.pressed.connect(func() -> void: _nudge(1))
	row.add_child(plus)
	_custom_btn = UIKit.pill("", pal, "accent", Vector2(0, 86), 28)
	_custom_btn.name = "TipCustom"
	_custom_btn.pressed.connect(func() -> void:
		_amount.text = str(_custom())
		_tip(_custom())
	)
	body.add_child(_custom_btn)
	_status = UIKit.label(_thanks(), 20, pal["accent"], 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_refresh_custom()
	Store.purchase_finished.connect(func(ok: bool, msg: String, id: String) -> void:
		if not is_inside_tree() or not (Store.is_tip(id) or id.is_empty()):
			return
		_status.text = msg if not ok else _thanks()
		if ok:
			AudioManager.play("win", 1.0, -9.0)
			Haptics.tap(30)
	)


## The typed amount, rounded to an amount Play sells and kept in range.
func _custom() -> int:
	return Store.snap_tip(int(_amount.text.to_int()))


func _nudge(dir: int) -> void:
	_amount.text = str(Store.nudge_tip(_custom(), dir))
	_refresh_custom()


func _refresh_custom() -> void:
	var v: int = _custom()
	_custom_btn.text = "Tip %s" % Store.price("tip_%d" % v)
	var typed: int = int(_amount.text.to_int())
	if typed > 0 and typed != v:
		_status.text = "Google Play takes amounts in steps of %d (%d above %d), so that's %s" % [Store.TIP_STEP, Store.TIP_BIG_STEP, Store.TIP_BIG_FROM, Store.price("tip_%d" % v)]


func _tip(rupees: int) -> void:
	_status.text = "Opening Google Play…"
	Store.buy("tip_%d" % rupees)


func _thanks() -> String:
	var n: int = SaveSystem.tips_given()
	return "" if n == 0 else "You've tipped %d %s. Thank you ♥" % [n, "time" if n == 1 else "times"]
