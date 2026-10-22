class_name ChapterIntro
extends Control
## The first time a chapter's opening room is played: a floating card explains the
## chapter's new idea with a live diagram, then the new element is spotlit in the
## room with a short caption until the player starts aiming.

signal done

const LESSONS: Dictionary = {
	"ch1": ["Few turns", "Lay arrows on the floor, then press Go. The orb rolls straight and turns on every arrow: take every dot, then roll home."],
	"ch2": ["Signs", "Printed signs turn the orb just like your arrows, but they're fixed. Use them, or steer around them."],
	"ch3": ["Bends", "A bend is a little diagonal wall: the orb banks off it round the corner, whichever way it comes in."],
	"ch4": ["Switch and gates", "Rolling over the switch flips every gate: shut ones open, open ones shut. Each pass flips them again."],
	"ch5": ["Spinners", "A spinner points the orb, then turns a quarter clockwise. Come back through it and it sends you somewhere new."],
	"ch6": ["Portals", "Roll into one portal and out of its twin, still heading the same way."],
	"ch7": ["Cracked floor", "Cracked floor holds once. The moment the orb rolls off it, it crumbles into a hole."],
	"ch8": ["Numbered dots", "Numbered dots count only in order. Roll over 2 before 1 and it doesn't count yet: come back for it."],
	"ch9": ["Two orbs", "Two orbs roll at once and share your arrows. Both must get home, without ever bumping into each other."],
}
const CAPTIONS: Dictionary = {
	"ch2": "Signs turn the orb too",
	"ch3": "Bends bank the orb round",
	"ch4": "The switch opens the gate",
	"ch5": "The spinner turns after each pass",
	"ch6": "In one portal, out the other",
	"ch7": "Cracked floor holds only once",
	"ch8": "Take the dots in order",
	"ch9": "Both orbs follow your arrows",
}

var chapter_id: String = "ch2"
var pal: Dictionary
var board: Board
var _card_root: Control
var _bubble: PanelContainer
var _spotlight: bool = false
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_card()
	board.edit_started.connect(func() -> void:
		if _spotlight:
			_finish()
	)
	board.run_started.connect(func() -> void:
		if _spotlight:
			_finish()
	)


func _build_card() -> void:
	_card_root = Control.new()
	_card_root.add_to_group("modal")
	_card_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card_root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(pal["bottom"], 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_root.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_root.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.card_style(pal))
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var lesson: Array = LESSONS.get(chapter_id, LESSONS["ch1"])
	col.add_child(UIKit.caption("New in %s" % pal["name"], {"muted": pal["accent"]}, 18, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(UIKit.label(str(lesson[0]), 46, pal["ink"], 500))
	var art: ChapterArt = ChapterArt.new()
	art.chapter_id = chapter_id
	art.pal = pal
	art.custom_minimum_size = Vector2(0, 250)
	col.add_child(art)
	var text: Label = UIKit.label(str(lesson[1]), 25, pal["ink"], 400)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(text)
	var ok: Button = UIKit.pill("Got it", pal, "primary", Vector2(0, 88), 30)
	ok.name = "GotIt"
	ok.pressed.connect(dismiss)
	col.add_child(ok)
	panel.modulate.a = 0.0
	(func() -> void:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = Vector2(0.9, 0.9)
		var tw: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate:a", 1.0, 0.25)
		tw.tween_property(panel, "scale", Vector2.ONE, 0.4)
	).call_deferred()
	ok.grab_focus.call_deferred()


## Closes the card and spotlights the new element in the room.
func dismiss() -> void:
	if _card_root == null:
		_finish()
		return
	var root: Control = _card_root
	_card_root = null
	var tw: Tween = create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.2)
	tw.tween_callback(root.queue_free)
	_spotlight = true
	board.spotlight = _spots()
	_bubble = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = pal["ink"]
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(UIKit.label(str(CAPTIONS.get(chapter_id, "Follow the dotted path")), 24, pal["top"], 600))
	add_child(_bubble)
	done.emit()


func _finish() -> void:
	_spotlight = false
	board.spotlight = []
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)


func _process(_delta: float) -> void:
	if _bubble != null:
		var g: Rect2 = board.grid_rect()
		var top: Vector2 = board.global_position - global_position + g.position + Vector2(g.size.x * 0.5, 0)
		_bubble.position = Vector2(top.x - _bubble.size.x * 0.5, maxf(-110.0, top.y - _bubble.size.y - 12.0))


## Where the chapter's new element sits.
func _spots() -> Array:
	var lv: Dictionary = board.level
	var keys: Dictionary = {"ch2": "signs", "ch3": "bends", "ch4": "switches", "ch5": "spinners", "ch6": "portals", "ch7": "cracks", "ch8": "dots", "ch9": "starts"}
	var out: Array = []
	var key: String = str(keys.get(chapter_id, ""))
	for q: Array in lv.get(key, []):
		out.append(RouteSim.cell_of(lv, int(q[0]), int(q[1])))
		if key == "portals":
			out.append(RouteSim.cell_of(lv, int(q[2]), int(q[3])))
	if key == "switches":
		for g2: Array in lv.get("gates", []):
			out.append(RouteSim.cell_of(lv, int(g2[0]), int(g2[1])))
	return out
