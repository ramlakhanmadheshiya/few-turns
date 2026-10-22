extends Overlay
## What the game is, who made it, and where to get help.

const SITE: String = "https://theramlakhan.com/few-turns/"
const AUTHOR_SITE: String = "https://theramlakhan.com/"


func _init() -> void:
	scrollable = true


## Pill padding trimmed so three buttons fit side by side.
func _tight(sb: StyleBox) -> StyleBox:
	var out: StyleBox = sb.duplicate()
	out.content_margin_left = 14
	out.content_margin_right = 14
	return out


func build() -> void:
	name = "About"
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 10)
	var head: HBoxContainer = HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_END
	var close_btn: Button = UIKit.icon_button("x", pal, 60.0)
	close_btn.name = "Close"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	body.add_child(head)
	var icon: TextureRect = TextureRect.new()
	icon.texture = load("res://assets/icon.svg")
	icon.custom_minimum_size = Vector2(150, 150)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(icon)
	body.add_child(UIKit.label("Few Turns", 52, pal["ink"], 400))
	var version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	body.add_child(UIKit.caption("A quiet arrow puzzle   ·   version %s" % version, pal, 17, HORIZONTAL_ALIGNMENT_CENTER))
	add_gap(10)
	var blurb: Label = UIKit.label("Lay a few arrows, press Go, and watch one orb find its way home. 360 rooms across 9 chapters, every one checked by a solver: the turns you get are the fewest that work.", 23, pal["ink"], 400)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(blurb)
	add_gap(14)
	body.add_child(UIKit.caption("Made by", pal, 17, HORIZONTAL_ALIGNMENT_CENTER))
	var me: Button = UIKit.pill("Ramlakhan Madheshiya", pal, "text", Vector2(0, 56), 30)
	me.name = "Author"
	me.add_theme_color_override("font_color", pal["ink"])
	me.add_theme_color_override("font_hover_color", pal["accent"])
	me.pressed.connect(func() -> void: OS.shell_open(AUTHOR_SITE))
	body.add_child(me)
	body.add_child(UIKit.label("Game designer and developer", 20, pal["muted"], 400))
	add_gap(4)
	body.add_child(UIKit.label("Claude Opus 5.5", 28, pal["ink"], 500))
	body.add_child(UIKit.label("AI co-developer, by Anthropic", 20, pal["muted"], 400))
	add_gap(16)
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	for item: Array in [["Privacy", "privacy/", "shield"], ["Help", "help/", "circle-help"], ["Website", "", "globe"]]:
		var b: Button = UIKit.pill(item[0], pal, "soft", Vector2(0, 72), 22)
		b.name = str(item[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.add_theme_stylebox_override("normal", _tight(b.get_theme_stylebox("normal")))
		b.icon = UIKit.icon(item[2])
		b.add_theme_constant_override("icon_max_width", 26)
		b.add_theme_color_override("icon_normal_color", pal["ink"])
		var url: String = SITE + str(item[1])
		b.pressed.connect(func() -> void: OS.shell_open(url))
		row.add_child(b)
		if _first_focus == null:
			_first_focus = b
	add_gap(6)
	var note: Label = UIKit.label("Your progress is saved only on this device. Ads (Android) are served by Google AdMob.", 18, pal["muted"], 400)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
