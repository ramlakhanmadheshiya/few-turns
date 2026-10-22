extends Overlay
## Level keys: pick how many with − / +, see the price (10% off at five or more),
## or watch a video for a free one.

var _count: int = 1
var _num: Label
var _buy: Button
var _deal: Label
var _have: Label
var _status: Label


func build() -> void:
	name = "KeysShop"
	add_title("Level keys")
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 14)
	var sub: Label = UIKit.label("A key opens any locked room, for good. Clear it and the next room opens as usual.", 22, pal["muted"], 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(sub)
	_have = UIKit.label("", 22, pal["ink"], 600)
	body.add_child(_have)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	body.add_child(row)
	var minus: Button = UIKit.icon_button("minus", pal, 80.0)
	minus.name = "Minus"
	minus.pressed.connect(func() -> void: _set_count(_count - 1))
	row.add_child(minus)
	var mid: VBoxContainer = VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	var key_row: HBoxContainer = HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.add_theme_constant_override("separation", 10)
	mid.add_child(key_row)
	key_row.add_child(UIKit.icon_rect("key-round", 44.0, pal["accent"]))
	_num = UIKit.label("1", 64, pal["ink"], 400)
	_num.custom_minimum_size = Vector2(90, 0)
	key_row.add_child(_num)
	var plus: Button = UIKit.icon_button("plus", pal, 80.0)
	plus.name = "Plus"
	plus.pressed.connect(func() -> void: _set_count(_count + 1))
	row.add_child(plus)
	# Quick picks.
	var quick: HBoxContainer = HBoxContainer.new()
	quick.alignment = BoxContainer.ALIGNMENT_CENTER
	quick.add_theme_constant_override("separation", 12)
	body.add_child(quick)
	for n: int in [1, 2, 5, 10]:
		var q: Button = UIKit.pill("%d" % n, pal, "soft", Vector2(96, 56), 22)
		q.name = "Quick_%d" % n
		q.pressed.connect(func() -> void: _set_count(n))
		quick.add_child(q)
	_deal = UIKit.label("", 20, pal["accent"], 700)
	body.add_child(_deal)
	_buy = UIKit.pill("", pal, "accent", Vector2(0, 92), 30)
	_buy.name = "BuyKeys"
	_buy.pressed.connect(func() -> void:
		_status.text = "Opening Google Play…"
		Store.buy("keys_%d" % _count)
	)
	body.add_child(_buy)
	_first_focus = _buy
	var video: Button = UIKit.pill("", pal, "ghost", Vector2(0, 80), 24)
	video.name = "VideoKey"
	video.pressed.connect(func() -> void:
		if SaveSystem.video_keys_left() <= 0:
			_status.text = "That's all the free keys for today. More tomorrow!"
			return
		if not AdManager.rewarded_ready():
			_status.text = "No video available right now. Try again in a little while."
			return
		AdManager.show_rewarded(func(ok: bool) -> void:
			if ok:
				SaveSystem.add_video_key()
				AudioManager.play("unlock", 1.0)
				_status.text = "Here's a key!"
				video.text = _video_text()
		)
	)
	video.text = _video_text()
	body.add_child(video)
	_status = UIKit.label("", 20, pal["muted"], 500)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	Store.purchase_finished.connect(func(ok: bool, msg: String, id: String) -> void:
		if is_inside_tree() and (Store.is_keys(id) or id.is_empty()):
			_status.text = msg
			if ok:
				AudioManager.play("unlock", 1.0)
	)
	Events.keys_changed.connect(func(_c: int) -> void: _refresh())
	Store.price_updated.connect(func(_id: String, _p: String) -> void: _refresh())
	_refresh()


func _video_text() -> String:
	var left: int = SaveSystem.video_keys_left()
	return "Watch a video for a key  ·  %d left today" % left if left > 0 else "Free keys are back tomorrow"


func _set_count(n: int) -> void:
	var was: int = _count
	_count = clampi(n, 1, Store.KEY_MAX)
	if _count != was:
		AudioManager.play_ui("ui_toggle")
		_num.pivot_offset = _num.size * 0.5
		_num.scale = Vector2(1.2, 1.2)
		create_tween().tween_property(_num, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree() and _num == null:
		return
	_num.text = str(_count)
	var k: int = SaveSystem.keys()
	_have.text = "You have %d %s" % [k, "key" if k == 1 else "keys"]
	_buy.text = "Get %d %s for %s" % [_count, "key" if _count == 1 else "keys", Store.price("keys_%d" % _count)]
	if _count >= Store.KEY_BULK:
		_deal.text = "10%% off for %d or more" % Store.KEY_BULK
	else:
		_deal.text = "Buy %d or more: 10%% off" % Store.KEY_BULK
