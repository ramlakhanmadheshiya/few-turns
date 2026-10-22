class_name Screen
extends Control
## Base for full-screen pages. The app sets `app` and `pal` before adding it.

var app: Node
var pal: Dictionary = Palette.get_palette("ch1")


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS


## Which music track and palette this screen wants.
func music_track() -> String:
	return "menu"


## Return true if the screen consumed the back action.
func handle_back() -> bool:
	return false


## True while a room is being played (settings then hide progress reset).
func in_game() -> bool:
	return false


## Called after the screen is visible; give keyboard/gamepad focus here.
func focus_default() -> void:
	pass


## Standard header: back button, centred title and a settings button on the right.
func make_header(title: String, on_back: Callable, right: Control = null) -> Control:
	if right == null:
		right = UIKit.icon_button("settings", pal, 72.0)
		right.name = "SettingsButton"
		(right as Button).pressed.connect(func() -> void: app.open_settings(in_game()))
	var bar: Control = Control.new()
	bar.custom_minimum_size = Vector2(0, 96)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back: Button = UIKit.icon_button("chevron-left", pal, 72.0)
	back.name = "Back"
	back.position = Vector2(0, 12)
	back.pressed.connect(on_back)
	bar.add_child(back)
	var t: Label = UIKit.label(title, 34, pal["ink"], 600)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.add_child(t)
	if right != null:
		right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		right.position = Vector2(-right.custom_minimum_size.x, 12)
		bar.add_child(right)
		bar.resized.connect(func() -> void: right.position = Vector2(bar.size.x - right.custom_minimum_size.x, 12))
	return bar
