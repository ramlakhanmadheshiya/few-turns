extends Overlay
## One pack, on a floating card: a live preview, what you get, the price, and for
## cosmetic packs a one-hour trial from a short video (with a live countdown).

var product: String = "supporter_pack"
## Show a "See the shop" link (when opened from outside the shop).
var show_shop_link: bool = true
var _buy: Button
var _status: Label
var _trial_btn: Button
var _tick: float = 0.0


## Live trial countdown on the trial button.
func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or _trial_btn == null:
		return
	_tick = 0.25
	var clock: String = SaveSystem.trial_clock(product)
	_trial_btn.text = "On trial  ·  %s left  ·  choose one" % clock if not clock.is_empty() else "Try it free for 1 hour with a video"


func _init() -> void:
	scrollable = true


func build() -> void:
	name = "Product"
	var info: Dictionary = Store.PRODUCTS[product]
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 12)
	var head: HBoxContainer = HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_END
	var close_btn: Button = UIKit.icon_button("x", pal, 60.0)
	close_btn.name = "Close"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	body.add_child(head)
	var hero: ProductPreview = ProductPreview.new()
	hero.product = product
	hero.pal = pal
	hero.custom_minimum_size = Vector2(0, 190)
	body.add_child(hero)
	if product == "complete_pack":
		body.add_child(UIKit.caption("Best value  ·  save %d%%" % Store.complete_saving(), {"muted": pal["accent"]}, 18, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.label(str(info["name"]), 48, pal["ink"], 500))
	if product == "supporter_pack":
		var sub: Label = UIKit.label("Few Turns is made by one person. One purchase\nhelps make the next chapter.", 22, pal["muted"], 400)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(sub)
	add_gap(4)
	var perks: VBoxContainer = VBoxContainer.new()
	perks.add_theme_constant_override("separation", 12)
	perks.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(perks)
	for perk: String in info["perks"]:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var dot: PanelContainer = PanelContainer.new()
		var dsb: StyleBoxFlat = StyleBoxFlat.new()
		dsb.bg_color = Color(pal["target"], 0.16)
		dsb.set_corner_radius_all(20)
		dot.add_theme_stylebox_override("panel", dsb)
		dot.custom_minimum_size = Vector2(40, 40)
		var ic: TextureRect = UIKit.icon_rect("check", 22.0, pal["target"])
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.add_child(ic)
		row.add_child(dot)
		row.add_child(UIKit.label(perk, 26, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT))
		perks.add_child(row)
	add_gap(8)
	_status = UIKit.label("", 20, pal["muted"], 500)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_buy = UIKit.pill("", pal, "accent", Vector2(0, 92), 30)
	_buy.name = "Buy"
	_buy.pressed.connect(func() -> void:
		if SaveSystem.bought(product):
			if product in ["orb_pack", "theme_pack"]:
				app.open_picker("orbs" if product == "orb_pack" else "themes")
			return
		_status.text = "Opening Google Play…"
		Store.buy(product)
	)
	body.add_child(_buy)
	_first_focus = _buy
	if bool(info.get("trial", false)) and not SaveSystem.bought(product):
		var trial: Button = UIKit.pill("Try it free for 1 hour with a video", pal, "ghost", Vector2(0, 84), 24)
		trial.name = "Trial"
		_trial_btn = trial
		trial.pressed.connect(func() -> void:
			if SaveSystem.trial_left(product) > 0:
				app.open_picker("orbs" if product == "orb_pack" else "themes")
				return
			if not AdManager.rewarded_ready():
				_status.text = "No video available right now. Try again in a little while."
				return
			AdManager.show_rewarded(func(ok: bool) -> void:
				if ok:
					SaveSystem.start_trial(product)
					AudioManager.play("unlock", 1.0)
					app.open_picker("orbs" if product == "orb_pack" else "themes")
			)
		)
		body.add_child(trial)
	var links: HBoxContainer = HBoxContainer.new()
	links.alignment = BoxContainer.ALIGNMENT_CENTER
	links.add_theme_constant_override("separation", 12)
	body.add_child(links)
	var restore: Button = UIKit.pill("Restore purchase", pal, "text", Vector2(0, 64), 22)
	restore.name = "Restore"
	restore.pressed.connect(func() -> void:
		_status.text = "Checking your purchases…"
		Store.restore()
	)
	links.add_child(restore)
	if show_shop_link:
		var shop: Button = UIKit.pill("See the shop", pal, "text", Vector2(0, 64), 22)
		shop.name = "SeeShop"
		shop.pressed.connect(func() -> void:
			app.close_settings()
			app.open_shop()
		)
		links.add_child(shop)
	Store.purchase_finished.connect(_on_result)
	Store.restore_finished.connect(func(ok: bool, msg: String) -> void: _on_result(ok, msg, product))
	Store.price_updated.connect(func(_id: String, _p: String) -> void: _refresh())
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	if SaveSystem.bought(product):
		_buy.text = "Choose one in Settings" if product in ["orb_pack", "theme_pack"] else "It's yours  ♥"
		_buy.disabled = product not in ["orb_pack", "theme_pack"]
	else:
		var verb: String = "Support for" if product == "supporter_pack" else "Get it for"
		_buy.text = "%s %s" % [verb, Store.price(product)]
		_buy.disabled = false


func _on_result(ok: bool, message: String, _id: String) -> void:
	if not is_inside_tree():
		return
	_status.text = message
	if ok:
		AudioManager.play("unlock", 1.0)
		Haptics.tap(30)
	_refresh()
