extends Overlay
## Who made what, section by section.

const SECTIONS: Array = [
	["Made by", [
		["Ramlakhan Madheshiya", "Game design, development and levels", "https://theramlakhan.com/"],
		["Claude Opus 5.5", "AI co-developer, by Anthropic", ""],
	]],
	["Engine", [["Godot Engine 4.7", "MIT licence. godotengine.org", "https://godotengine.org/"]]],
	["Type", [["Outfit", "By the Outfit Project Authors. SIL Open Font License 1.1.", ""]]],
	["Icons", [["Lucide", "By the Lucide contributors. ISC licence. lucide.dev", "https://lucide.dev/"]]],
	["Sound and music", [["Synthesised for Few Turns", "Every sound effect and all nine chapter themes are made in code for this game.", ""]]],
	["Art and levels", [["Made in code", "Drawn and generated for this game. A solver checks every one of the 360 rooms: it can be done with the turns it gives, and not with fewer.", ""]]],
	["Ads and purchases, on Android", [
		["Godot AdMob Plugin", "By Poing Studios. MIT licence.", ""],
		["Godot Google Play Billing", "By the Godot Engine contributors. MIT licence.", ""],
		["Google Mobile Ads SDK, User Messaging Platform and Play Billing Library", "By Google, under Google's terms.", ""],
	]],
]


func _init() -> void:
	scrollable = true


func build() -> void:
	name = "Credits"
	add_title("Credits")
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 4)
	for section: Array in SECTIONS:
		body.add_child(UIKit.caption(str(section[0]), pal, 17))
		add_gap(2)
		for entry: Array in section[1]:
			var url: String = str(entry[2])
			if url.is_empty():
				var v: Label = UIKit.label(str(entry[0]), 27, pal["ink"], 500, HORIZONTAL_ALIGNMENT_LEFT)
				v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				body.add_child(v)
			else:
				var link: Button = UIKit.pill(str(entry[0]), pal, "text", Vector2(0, 44), 27)
				link.alignment = HORIZONTAL_ALIGNMENT_LEFT
				link.add_theme_color_override("font_color", pal["ink"])
				link.add_theme_color_override("font_hover_color", pal["accent"])
				var box: StyleBoxEmpty = StyleBoxEmpty.new()
				for st: String in ["normal", "hover", "pressed"]:
					link.add_theme_stylebox_override(st, box)
				link.pressed.connect(func() -> void: OS.shell_open(url))
				body.add_child(link)
			var d: Label = UIKit.label(str(entry[1]), 20, pal["muted"], 400, HORIZONTAL_ALIGNMENT_LEFT)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(d)
			add_gap(8)
		add_gap(12)
	body.add_child(UIKit.label("Thank you for playing ♥", 24, pal["accent"], 600))
