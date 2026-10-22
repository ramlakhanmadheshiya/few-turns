extends Overlay
## Settings. "Reset progress" is hidden while a level is being played so stars
## can't be wiped by accident mid-game.

var in_game: bool = false
var _confirm_reset: bool = false
var _reset_btn: Button


func _init() -> void:
	scrollable = true


func build() -> void:
	name = "Settings"
	add_title("Settings")
	var body: VBoxContainer = card_body()
	for item: Array in [["Music", "music_volume", 0.5], ["Sound", "sound_volume", 0.75]]:
		var key: String = item[1]
		var row: Control = UIKit.slider_row(item[0], float(SaveSystem.get_setting(key, item[2])), pal, func(v: float) -> void: SaveSystem.set_setting(key, v))
		row.name = "Row_" + key
		body.add_child(row)
		if _first_focus == null:
			_first_focus = row.get_child(1)
	for item: Array in [["Vibration", "haptics"], ["Screen shake", "shake"], ["Longer guide", "long_guide"]]:
		var tkey: String = item[1]
		var trow: HBoxContainer = UIKit.toggle_row(item[0], bool(SaveSystem.get_setting(tkey, true)), pal, func(on: bool) -> void: SaveSystem.set_setting(tkey, on), func() -> void: app.open_setting_info(tkey))
		trow.name = "Row_" + tkey
		body.add_child(trow)
	add_gap(12)
	# Look: colour theme and orb style, each showing the current pick.
	var looks: HBoxContainer = HBoxContainer.new()
	looks.add_theme_constant_override("separation", 14)
	body.add_child(looks)
	looks.add_child(_look_button("Colours", Palette.theme_name(Palette.theme_id), "palette", "themes"))
	looks.add_child(_look_button("Orbs", OrbStyles.display_name(SaveSystem.orb_style()), "circle-dot", "orbs"))
	add_gap(12)
	var buttons: GridContainer = GridContainer.new()
	buttons.columns = 2
	buttons.add_theme_constant_override("h_separation", 14)
	buttons.add_theme_constant_override("v_separation", 14)
	body.add_child(buttons)
	for item: Array in [["How to play", "HowToPlay", "circle-help", func() -> void: app.open_how_to_play()],
			["Shop", "ShopButton", "shopping-bag", func() -> void:
				app.close_settings()
				app.open_shop()],
			["About", "About", "info", func() -> void: app.open_about()],
			["Credits", "Credits", "users", func() -> void: app.open_credits()]]:
		var b: Button = UIKit.pill(item[0], pal, "soft", Vector2(0, 72), 22)
		b.name = item[1]
		b.icon = UIKit.icon(item[2])
		b.add_theme_constant_override("icon_max_width", 26)
		for key: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(key, pal["ink"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(item[3])
		buttons.add_child(b)
	var provider: Node = AdManager.provider
	if provider != null and provider.has_method("privacy_options_required") and provider.privacy_options_required():
		var privacy: Button = UIKit.pill("Ad privacy choices", pal, "soft", Vector2(0, 72), 22)
		privacy.name = "Privacy"
		privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		privacy.pressed.connect(func() -> void: provider.show_privacy_options())
		buttons.add_child(privacy)
	if not in_game:
		add_gap(4)
		_reset_btn = UIKit.pill("Reset progress", pal, "text", Vector2(0, 68), 24)
		_reset_btn.name = "Reset"
		_reset_btn.pressed.connect(_on_reset)
		body.add_child(_reset_btn)
	add_gap(6)
	var version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	body.add_child(UIKit.caption("Few Turns %s   ·   made with Godot" % version, pal, 16, HORIZONTAL_ALIGNMENT_CENTER))


## A card showing the current colour theme or orb, opening its picker.
func _look_button(title: String, current: String, icon_name: String, mode: String) -> Button:
	var b: Button = UIKit.pill("", pal, "ghost", Vector2(0, 100), 22)
	b.name = "Pick" + title
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: app.open_picker(mode))
	var row: HBoxContainer = HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 20
	row.offset_right = -14
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var dot: PanelContainer = PanelContainer.new()
	var dsb: StyleBoxFlat = StyleBoxFlat.new()
	dsb.bg_color = Color(pal["target"], 0.16)
	dsb.set_corner_radius_all(26)
	dot.add_theme_stylebox_override("panel", dsb)
	dot.custom_minimum_size = Vector2(52, 52)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic: TextureRect = UIKit.icon_rect(icon_name, 26.0, pal["target"])
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.add_child(ic)
	row.add_child(dot)
	var text: VBoxContainer = VBoxContainer.new()
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	text.add_child(UIKit.label(title, 26, pal["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT))
	text.add_child(UIKit.label(current, 19, pal["muted"], 500, HORIZONTAL_ALIGNMENT_LEFT))
	return b


func _on_reset() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_reset_btn.text = "Tap again to erase all stars"
		return
	SaveSystem.reset_progress()
	app.close_settings()
	app.open_home()
