class_name Overlay
extends Control
## A centred floating card over a soft shade. Tapping the shade closes it.
## Subclasses fill `card_body()` in `build()`. Long content scrolls inside the card
## (set `scrollable`) so the card never turns into a sheet from the bottom.

var app: Node
var pal: Dictionary
## Content scrolls inside the card when it's taller than the screen allows.
var scrollable: bool = false
## Called instead of closing when the shade or close button is tapped (e.g. to go
## back to the overlay this one was opened from).
var on_close: Callable
var _body: VBoxContainer
var _card: PanelContainer
var _first_focus: Control
var _scroll: TouchScroll


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(pal["bottom"], 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close()
	)
	add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(600, 0)
	_card.add_theme_stylebox_override("panel", UIKit.card_style(pal))
	center.add_child(_card)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	if scrollable:
		var outer: VBoxContainer = VBoxContainer.new()
		_card.add_child(outer)
		_scroll = TouchScroll.new()
		_scroll.name = "CardScroll"
		_scroll.custom_minimum_size = Vector2(520, 0)
		outer.add_child(_scroll)
		_scroll.set_content(_body)
		_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.resized.connect(_fit_scroll)
		get_viewport().size_changed.connect(_fit_scroll)
	else:
		_card.add_child(_body)
	build()
	if scrollable:
		_fit_scroll.call_deferred()
	_card.pivot_offset = Vector2(290, 300)
	_card.scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.35)


## Override to add content to card_body().
func build() -> void:
	pass


## Closes this overlay (or returns to the one it was opened from).
func close() -> void:
	if on_close.is_valid():
		on_close.call()
	else:
		app.close_settings()


## Caps the card at most of the screen height; the rest scrolls.
func _fit_scroll() -> void:
	if _scroll == null:
		return
	var limit: float = get_viewport_rect().size.y * 0.8 - 72.0
	_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, limit)


func card_body() -> VBoxContainer:
	return _body


## Title row with a close button.
func add_title(text: String) -> void:
	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = UIKit.label(text, 40, pal["ink"], 600, HORIZONTAL_ALIGNMENT_LEFT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn: Button = UIKit.icon_button("x", pal, 64.0)
	close_btn.name = "Close"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	_body.add_child(head)
	add_gap(12)


func add_gap(h: float) -> void:
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0, h)
	_body.add_child(gap)


func focus_default() -> void:
	if _first_focus != null:
		_first_focus.grab_focus()
