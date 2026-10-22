extends Control
## Root of the game: backdrop, one screen at a time with soft transitions,
## and the settings sheet. Handles the back button / Escape globally.

const HomeScreen: GDScript = preload("res://game/ui/screens/home_screen.gd")
const ChaptersScreen: GDScript = preload("res://game/ui/screens/chapters_screen.gd")
const LevelsScreen: GDScript = preload("res://game/ui/screens/levels_screen.gd")
const GameScreen: GDScript = preload("res://game/ui/screens/game_screen.gd")
const ShopScreen: GDScript = preload("res://game/ui/screens/shop_screen.gd")
const SettingsSheet: GDScript = preload("res://game/ui/settings_sheet.gd")
const CreditsSheet: GDScript = preload("res://game/ui/credits_sheet.gd")
const HowToPlaySheet: GDScript = preload("res://game/ui/how_to_play_sheet.gd")
const AboutSheet: GDScript = preload("res://game/ui/about_sheet.gd")
const ConfirmSheet: GDScript = preload("res://game/ui/confirm_sheet.gd")
const ProductSheet: GDScript = preload("res://game/ui/product_sheet.gd")
const TipSheet: GDScript = preload("res://game/ui/tip_sheet.gd")
const PickerSheet: GDScript = preload("res://game/ui/picker_sheet.gd")
const ShareSheet: GDScript = preload("res://game/ui/share_sheet.gd")
const LockedSheet: GDScript = preload("res://game/ui/locked_sheet.gd")
const KeysSheet: GDScript = preload("res://game/ui/keys_sheet.gd")
const SettingInfoSheet: GDScript = preload("res://game/ui/setting_info_sheet.gd")

var backdrop: Backdrop
var host: MarginContainer
var current: Screen
## The one overlay that can sit above a screen: settings, credits or a confirm prompt.
var settings: Control
var _busy: bool = false
var _banner_h: float = 0.0
var _last_back_msec: int = -1000
## Re-opens the current screen (used to repaint after a theme change).
var _route: Callable
var _palette_id: String = "ch1"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop = Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	host = MarginContainer.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	backdrop.set_palette(Palette.get_palette("ch1"), false)
	Events.banner_changed.connect(func(h: float) -> void:
		_banner_h = h
		_apply_safe_area()
	)
	open_home()
	AdManager.refresh_banner()
	# The opening moment: the logo plays out, then the home screen.
	if not AudioManager.mute_for_tests:
		var splash: Splash = Splash.new()
		splash.name = "Splash"
		add_child(splash)


## Keeps content inside notches and rounded corners; also caps width on desktop.
func _apply_safe_area() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var margins: Dictionary = {"left": 28.0, "right": 28.0, "top": 20.0, "bottom": 20.0}
	if OS.has_feature("mobile"):
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		var win: Vector2i = DisplayServer.window_get_size()
		if win.x > 0 and safe.size.x > 0:
			var k: float = vp.x / float(win.x)
			margins["left"] += safe.position.x * k
			margins["top"] += safe.position.y * k
			margins["right"] += (win.x - safe.end.x) * k
			margins["bottom"] += (win.y - safe.end.y) * k
	# Reserve room for the bottom banner so it never covers a button.
	margins["bottom"] += _banner_h
	var max_w: float = 760.0
	if vp.x - margins["left"] - margins["right"] > max_w:
		var extra: float = (vp.x - max_w) * 0.5
		margins["left"] = extra
		margins["right"] = extra
	for side: String in margins:
		host.add_theme_constant_override("margin_" + side, int(margins[side]))


func open_home() -> void:
	_route = open_home
	_go(HomeScreen.new(), "ch1")


func open_chapters() -> void:
	_route = open_chapters
	_go(ChaptersScreen.new(), "ch1")


func open_levels(chapter_id: String) -> void:
	_route = open_levels.bind(chapter_id)
	var s: Screen = LevelsScreen.new()
	s.set("chapter_id", chapter_id)
	_go(s, chapter_id)


func open_shop() -> void:
	_route = open_shop
	_go(ShopScreen.new(), "ch1")


func open_game(chapter_id: String, index: int) -> void:
	# In a browser that only gets the free levels, the rest is on Google Play.
	if WebPlatform.over_cap(chapter_id, index):
		WebPlatform.show_full_game()
		return
	_route = open_game.bind(chapter_id, index)
	var s: Screen = GameScreen.new()
	s.set("chapter_id", chapter_id)
	s.set("index", index)
	_go(s, chapter_id)


## A pack's card. `back` (optional) is where closing it returns to.
func open_product(product: String, back: Callable = Callable()) -> void:
	var sheet: Control = ProductSheet.new()
	sheet.set("product", product)
	sheet.set("show_shop_link", current == null or current.get_script() != ShopScreen)
	if back.is_valid():
		sheet.set("on_close", back)
	_open_overlay(sheet)


## A locked room: open it with a key, or see how it opens by playing.
func open_locked(chapter_id: String, index: int) -> void:
	var sheet: Control = LockedSheet.new()
	sheet.set("chapter_id", chapter_id)
	sheet.set("index", index)
	_open_overlay(sheet)


func open_keys(back: Callable = Callable()) -> void:
	var sheet: Control = KeysSheet.new()
	if back.is_valid():
		sheet.set("on_close", back)
	_open_overlay(sheet)


## What a setting does, with a little demo. Closing returns to Settings.
func open_setting_info(key: String) -> void:
	var sheet: Control = SettingInfoSheet.new()
	sheet.set("key", key)
	sheet.set("on_close", open_settings.bind(current != null and current.in_game()))
	_open_overlay(sheet)


func open_tips() -> void:
	_open_overlay(TipSheet.new())


## "orbs" or "themes".
func open_picker(mode: String) -> void:
	var sheet: Control = PickerSheet.new()
	sheet.set("mode", mode)
	sheet.set("on_close", open_settings.bind(current != null and current.in_game()))
	_open_overlay(sheet)


func open_share(info: Dictionary) -> void:
	var sheet: Control = ShareSheet.new()
	sheet.set("info", info)
	_open_overlay(sheet)


## Repaints everything in the newly chosen colour theme.
func apply_theme() -> void:
	if current != null:
		backdrop.set_palette(Palette.get_palette(_palette_id))
	if _route.is_valid():
		_busy = false
		_route.call()


func _go(next: Screen, palette_id: String) -> void:
	if _busy:
		next.free()
		return
	_busy = true
	close_settings()
	_palette_id = palette_id
	var pal: Dictionary = Palette.get_palette(palette_id)
	next.app = self
	next.pal = pal
	backdrop.set_palette(pal)
	AudioManager.play_music(next.music_track())
	var old: Screen = current
	current = next
	if old != null:
		old.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var out: Tween = create_tween().set_parallel(true)
		out.tween_property(old, "modulate:a", 0.0, 0.16)
		out.tween_property(old, "scale", Vector2(0.98, 0.98), 0.16)
		await out.finished
		old.queue_free()
	next.modulate.a = 0.0
	host.add_child(next)
	next.pivot_offset = next.size * 0.5
	next.scale = Vector2(1.02, 1.02)
	var into: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	into.tween_property(next, "modulate:a", 1.0, 0.28)
	into.tween_property(next, "scale", Vector2.ONE, 0.32)
	_busy = false


## in_game hides "Reset progress" so stars can't be wiped mid-level.
func open_settings(in_game: bool = false) -> void:
	var sheet: Control = SettingsSheet.new()
	sheet.set("in_game", in_game)
	_open_overlay(sheet)


func open_credits() -> void:
	_open_overlay(CreditsSheet.new())


func open_how_to_play() -> void:
	_open_overlay(HowToPlaySheet.new())


func open_about() -> void:
	_open_overlay(AboutSheet.new())


## Replays the first-room tutorial on Dawn level 1.
func replay_tutorial() -> void:
	SaveSystem.set_flag("tutorial_done", false)
	close_settings()
	open_game("ch1", 0)


func _open_overlay(sheet: Control) -> void:
	close_settings()
	settings = sheet
	settings.set("app", self)
	settings.set("pal", current.pal if current != null else Palette.get_palette("ch1"))
	add_child(settings)


func _confirm_quit() -> void:
	var sheet: Control = ConfirmSheet.new()
	sheet.set("message", "Leave Few Turns?")
	sheet.set("yes_text", "Quit")
	sheet.set("no_text", "Keep playing")
	sheet.set("on_yes", func() -> void: get_tree().quit())
	_open_overlay(sheet)


func close_settings() -> void:
	if settings != null and is_instance_valid(settings):
		settings.queue_free()
	settings = null


## Focus rings only appear once the player uses keys or a gamepad, so touch
## players never see them.
func _input(event: InputEvent) -> void:
	var nav: bool = (event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed)
	if nav and get_viewport().gui_get_focus_owner() == null:
		if settings != null and is_instance_valid(settings):
			settings.call("focus_default")
		elif current != null:
			current.focus_default()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_BACK):
		get_viewport().set_input_as_handled()
		go_back()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## Phone back / Escape: one step back through overlay -> level -> levels ->
## chapters -> home, and on home ask before quitting.
func go_back() -> void:
	# Android can deliver both the notification and a key event for one press.
	var now: int = Time.get_ticks_msec()
	if now - _last_back_msec < 250:
		return
	_last_back_msec = now
	AudioManager.play_ui("ui_back")
	if settings != null:
		close_settings()
		return
	if _busy:
		return
	if current != null and current.handle_back():
		return
	if current != null and current.get_script() == HomeScreen and not OS.has_feature("web"):
		_confirm_quit()
