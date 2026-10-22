class_name Tutorial
extends Control
## Hands-on first-play tutorial for Path level 1. It never blocks input: the player
## really lays the arrow, turns it and presses Go while an animated hand and short
## captions guide them through tap -> turn -> Go.

signal finished

enum Step { SHOW, TURN, GO, ROLLING, RETRY, DONE }

var board: Board
var pal: Dictionary
var go_button: Control
var step: Step = Step.SHOW
var _t: float = 0.0
var _caption: Label
var _bubble: PanelContainer
var _shown_text: String = ""
var _cell: int = -1
var _dir: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sol: Dictionary = RouteSim.solution_arrows(board.level)
	for c: Variant in sol:
		_cell = int(c)
		_dir = int(sol[c])
	_bubble = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = pal["ink"]
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption = UIKit.label("", 26, pal["top"], 600)
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(440, 0)
	_bubble.add_child(_caption)
	add_child(_bubble)
	board.arrows_changed.connect(func(_left: int) -> void: _check_arrow())
	board.run_started.connect(func() -> void: _go(Step.ROLLING))
	board.run_finished.connect(func(won: bool) -> void:
		if won:
			_go(Step.DONE)
			SaveSystem.set_flag("tutorial_done")
			var tw: Tween = create_tween()
			tw.tween_interval(0.4)
			tw.tween_property(self, "modulate:a", 0.0, 0.4)
			tw.tween_callback(func() -> void:
				board.spotlight = []
				finished.emit()
				queue_free()
			)
		else:
			_go(Step.RETRY)
	)
	_go(Step.SHOW)


func _check_arrow() -> void:
	if step == Step.ROLLING or step == Step.DONE:
		return
	if board.arrows.has(_cell):
		_go(Step.GO if int(board.arrows[_cell]) == _dir else Step.TURN)
	else:
		_go(Step.SHOW)


func _go(next: Step) -> void:
	if next == step and _t > 0.0:
		return
	step = next
	_t = 0.0
	board.spotlight = [_cell] if step in [Step.SHOW, Step.TURN, Step.RETRY] else []
	match step:
		Step.SHOW:
			_say("The orb rolls up. Tap the ringed cell to lay an arrow")
		Step.TURN:
			_say("Tap it again to turn it, until it points home")
		Step.GO:
			_say("Now press Go")
		Step.ROLLING:
			_say("")
		Step.RETRY:
			_say("Nearly! Point the arrow at home, then Go")
		Step.DONE:
			_say("Home! Every dot, then home")


func _say(text: String) -> void:
	if text == _shown_text:
		return
	_shown_text = text
	_bubble.visible = not text.is_empty()
	_caption.text = text
	_bubble.pivot_offset = _bubble.size * 0.5
	_bubble.scale = Vector2(0.9, 0.9)
	create_tween().tween_property(_bubble, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_t += delta
	# Keep the caption just above the grid.
	var top: Vector2 = board.global_position - global_position + board.grid_rect().position + Vector2(board.grid_rect().size.x * 0.5, 0)
	# Over the TRY / TURNS / STARS strip if need be, never over the board.
	_bubble.position = Vector2(top.x - _bubble.size.x * 0.5, maxf(-110.0, top.y - _bubble.size.y - 12.0))
	queue_redraw()


func _draw() -> void:
	if board == null or board.level.is_empty() or _cell < 0:
		return
	var at: Vector2
	if step == Step.GO and go_button != null:
		at = go_button.global_position - global_position + go_button.size * 0.5
	elif step in [Step.SHOW, Step.TURN, Step.RETRY]:
		at = board.global_position - global_position + board.center(_cell)
	else:
		return
	# A looping tap: the hand presses, a ripple, then it lifts.
	var cycle: float = fmod(_t, 1.6) / 1.6
	var press: float = clampf((cycle - 0.25) / 0.15, 0.0, 1.0) * (1.0 - clampf((cycle - 0.55) / 0.15, 0.0, 1.0))
	var ripple: float = clampf((cycle - 0.35) / 0.4, 0.0, 1.0)
	if ripple > 0.0 and ripple < 1.0:
		draw_arc(at, 18.0 + 40.0 * ripple, 0.0, TAU, 32, Color(pal["accent"], 0.7 * (1.0 - ripple)), 3.0, true)
	var s: float = 76.0 * (1.0 - 0.12 * press)
	var hand: Vector2 = at + Vector2(-s * 0.3, 10.0 - 14.0 * (1.0 - press))
	var r: Rect2 = Rect2(hand, Vector2(s, s))
	draw_texture_rect(UIKit.icon("pointer-filled"), r, false, Color(1, 1, 1, 0.95))
	draw_texture_rect(UIKit.icon("pointer"), r, false, pal["ink"])
