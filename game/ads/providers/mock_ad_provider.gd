extends Node
## Stand-in ads for debug desktop builds, so layouts and flows can be checked
## without a phone. No network, no SDK.

signal banner_resized(height_px: float)

const BANNER_PX: float = 100.0

var _layer: CanvasLayer
var _banner: Control


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)


func show_banner() -> void:
	if _banner != null:
		return
	_banner = ColorRect.new()
	(_banner as ColorRect).color = Color(0.1, 0.1, 0.12, 0.88)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var win_h: float = float(DisplayServer.window_get_size().y)
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_banner.offset_top = -BANNER_PX * vp_h / maxf(1.0, win_h)
	_banner.mouse_filter = Control.MOUSE_FILTER_STOP
	var l: Label = Label.new()
	l.text = "Ad banner (test)"
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_child(l)
	_layer.add_child(_banner)
	banner_resized.emit(BANNER_PX)


func hide_banner() -> void:
	if _banner != null:
		_banner.queue_free()
		_banner = null


func rewarded_ready() -> bool:
	return true


func show_rewarded(on_done: Callable) -> void:
	_fullscreen("Rewarded ad (test)", on_done)


func interstitial_ready() -> bool:
	return true


func show_interstitial(on_done: Callable) -> void:
	_fullscreen("Interstitial ad (test)", func(_ok: bool) -> void: on_done.call())


func _fullscreen(text: String, on_done: Callable) -> void:
	var root: ColorRect = ColorRect.new()
	root.color = Color(0.05, 0.05, 0.08, 0.94)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(col)
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 32)
	col.add_child(l)
	var close: Button = Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(200, 72)
	col.add_child(close)
	_layer.add_child(root)
	close.disabled = true
	get_tree().create_timer(1.0).timeout.connect(func() -> void: close.disabled = false)
	close.pressed.connect(func() -> void:
		root.queue_free()
		on_done.call(true)
	)
