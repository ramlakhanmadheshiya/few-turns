class_name TouchScroll
extends Control
## Vertical scrolling that works the same on every phone: drag anywhere (even on a
## button) to scroll, flick for momentum, no scrollbar. A drag never counts as a tap.

const DRAG_START_PX: float = 14.0
const FRICTION: float = 5.0

var content: Control
var scroll_y: float = 0.0
var _tracking: bool = false
var _dragging: bool = false
var _start_pointer: float = 0.0
var _start_scroll: float = 0.0
var _velocity: float = 0.0
var _last_pointer: float = 0.0
var _last_msec: int = 0
var _muted: Array[BaseButton] = []


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	# Keyboard / gamepad focus scrolls the focused item into view.
	get_viewport().gui_focus_changed.connect(func(c: Control) -> void:
		if content != null and is_instance_valid(c) and content.is_ancestor_of(c):
			var top: float = c.global_position.y - content.global_position.y
			if top < scroll_y:
				scroll_to(top - 20.0)
			elif top + c.size.y > scroll_y + size.y:
				scroll_to(top + c.size.y - size.y + 20.0)
	)


## Sets the scrolled child. Its width follows ours; its height is its own minimum.
func set_content(c: Control) -> void:
	content = c
	add_child(c)
	resized.connect(_fit)
	c.minimum_size_changed.connect(_fit)
	_fit.call_deferred()


func _fit() -> void:
	if content == null:
		return
	content.size = Vector2(size.x, maxf(size.y, content.get_combined_minimum_size().y))
	_apply()


func max_scroll() -> float:
	return maxf(0.0, (content.size.y if content != null else 0.0) - size.y)


func scroll_to(y: float) -> void:
	scroll_y = clampf(y, 0.0, max_scroll())
	_apply()


func _apply() -> void:
	if content != null:
		content.position = Vector2(0, -roundf(scroll_y))


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or content == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if get_global_rect().has_point(mb.position) and mb.pressed and not _covered():
				scroll_to(scroll_y + (-80.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 80.0))
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and get_global_rect().has_point(mb.position) and not _covered():
			_tracking = true
			_dragging = false
			_start_pointer = mb.position.y
			_last_pointer = mb.position.y
			_start_scroll = scroll_y
			_velocity = 0.0
			_last_msec = Time.get_ticks_msec()
		elif not mb.pressed and _tracking:
			_tracking = false
			if _dragging:
				_dragging = false
				# Let buttons work again after this release has been ignored.
				_unmute.call_deferred()
	elif event is InputEventMouseMotion and _tracking:
		var y: float = (event as InputEventMouseMotion).position.y
		if not _dragging and absf(y - _start_pointer) > DRAG_START_PX:
			_dragging = true
			_mute_buttons()
		if _dragging:
			var now: int = Time.get_ticks_msec()
			var dt: float = maxf(0.001, float(now - _last_msec) / 1000.0)
			_velocity = lerpf(_velocity, -(y - _last_pointer) / dt, 0.4)
			_last_pointer = y
			_last_msec = now
			scroll_to(_start_scroll - (y - _start_pointer))


## True while a floating card this list isn't part of is open on top of it.
func _covered() -> bool:
	for n: Node in get_tree().get_nodes_in_group("modal"):
		if is_instance_valid(n) and n is CanvasItem and (n as CanvasItem).is_visible_in_tree() and not n.is_ancestor_of(self):
			return true
	return false


func _process(delta: float) -> void:
	if _tracking or absf(_velocity) < 5.0:
		return
	scroll_to(scroll_y + _velocity * delta)
	_velocity *= exp(-FRICTION * delta)
	if scroll_y <= 0.0 or scroll_y >= max_scroll():
		_velocity = 0.0


## While dragging, buttons under the finger must not fire on release.
func _mute_buttons() -> void:
	_muted.clear()
	_collect(content)
	for b: BaseButton in _muted:
		b.disabled = true


func _collect(n: Node) -> void:
	for child: Node in n.get_children():
		if child is BaseButton and not (child as BaseButton).disabled:
			_muted.append(child)
		_collect(child)


func _unmute() -> void:
	for b: BaseButton in _muted:
		if is_instance_valid(b):
			b.disabled = false
			if b.scale != Vector2.ONE:
				b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_muted.clear()
