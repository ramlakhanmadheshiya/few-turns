extends Overlay
## A yes / no question.

var message: String = "Are you sure?"
var yes_text: String = "Yes"
var no_text: String = "No"
var on_yes: Callable


func build() -> void:
	name = "Confirm"
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 18)
	body.add_child(UIKit.label(message, 40, pal["ink"], 600))
	add_gap(8)
	var yes: Button = UIKit.pill(yes_text, pal, "primary", Vector2(0, 84), 28)
	yes.name = "Yes"
	yes.pressed.connect(func() -> void: on_yes.call())
	body.add_child(yes)
	var no: Button = UIKit.pill(no_text, pal, "ghost", Vector2(0, 80), 26)
	no.name = "No"
	no.pressed.connect(func() -> void: app.close_settings())
	body.add_child(no)
	_first_focus = no
