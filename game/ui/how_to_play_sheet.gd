extends Overlay
## The rules in five short lines, plus a way to replay the hands-on tutorial.

const STEPS: Array = [
	["1", "Tap a cell to lay an arrow; tap again to turn it, or swipe the way it should point."],
	["2", "TURNS shows how many arrows the room gives you. The dotted guide shows where the orb rolls first."],
	["3", "Press Go. The orb rolls straight and turns on every arrow."],
	["4", "Take every red dot, then roll into home. Home stays shut until the last dot."],
	["5", "Hit a block, roll off the board or go round in circles, and it's back to the start. Your arrows and the missed path stay."],
	["6", "First try ★★★  ·  within three tries ★★  ·  after that ★. Restart clears the arrows for a fresh start at try 1."],
]


func build() -> void:
	name = "HowToPlay"
	add_title("How to play")
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 14)
	for step: Array in STEPS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var num: Label = UIKit.label(step[0], 24, pal["top"], 700)
		num.custom_minimum_size = Vector2(44, 44)
		var dot: StyleBoxFlat = StyleBoxFlat.new()
		dot.bg_color = pal["accent"]
		dot.set_corner_radius_all(22)
		num.add_theme_stylebox_override("normal", dot)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(num)
		var text: Label = UIKit.label(step[1], 25, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		body.add_child(row)
	var tip: Label = UIKit.label("Stuck? The bulb shows where the arrows go. Tap the room while the orb rolls to speed it up.", 21, pal["muted"], 400)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(tip)
	add_gap(6)
	var replay: Button = UIKit.pill("Replay tutorial", pal, "primary", Vector2(0, 80), 26)
	replay.name = "ReplayTutorial"
	replay.pressed.connect(func() -> void: app.replay_tutorial())
	body.add_child(replay)
	_first_focus = replay
