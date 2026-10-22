extends Overlay
## A locked room: how it opens by playing, or open it now with a level key.

var chapter_id: String = "ch1"
var index: int = 0
var _status: Label
var _use: Button


func build() -> void:
	name = "Locked"
	add_title("Level %d" % (index + 1))
	var body: VBoxContainer = card_body()
	body.add_theme_constant_override("separation", 14)
	var how: String
	if index == 0:
		var ci: int = Levels.chapter_index(chapter_id)
		var prev: String = str(Palette.get_palette(str(Levels.chapters[ci - 1]["id"]))["name"]) if ci > 0 else ""
		how = "Clear %d rooms in %s to open this chapter. Or open this room now, for good, with a key." % [Levels.CHAPTER_GATE, prev]
	else:
		how = "Clear level %d to open it. Or open it now, for good, with a key." % index
	var sub: Label = UIKit.label(how, 23, pal["muted"], 400)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(sub)
	var art: TextureRect = UIKit.icon_rect("key-round", 72.0, pal["accent"])
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(art)
	_use = UIKit.pill("", pal, "accent", Vector2(0, 90), 28)
	_use.name = "UseKey"
	_use.pressed.connect(_use_key)
	body.add_child(_use)
	_first_focus = _use
	var video: Button = UIKit.pill("", pal, "ghost", Vector2(0, 80), 24)
	video.name = "VideoKey"
	video.pressed.connect(func() -> void:
		if SaveSystem.video_keys_left() <= 0:
			_status.text = "That's all the free keys for today. More tomorrow!"
			return
		if not AdManager.rewarded_ready():
			_status.text = "No video available right now. Try again in a little while."
			return
		AdManager.show_rewarded(func(ok: bool) -> void:
			if ok:
				SaveSystem.add_video_key()
				AudioManager.play("unlock", 1.0)
				_status.text = "Here's a key!"
				_refresh()
		)
	)
	body.add_child(video)
	var buy: Button = UIKit.pill("Get keys", pal, "text", Vector2(0, 64), 24)
	buy.name = "GetKeys"
	buy.pressed.connect(func() -> void: app.open_keys(func() -> void: app.open_locked(chapter_id, index)))
	body.add_child(buy)
	_status = UIKit.label("", 20, pal["accent"], 600)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	Events.keys_changed.connect(func(_c: int) -> void: _refresh())
	_refresh()
	_refresh_video(video)


func _refresh() -> void:
	if not is_inside_tree() and _use == null:
		return
	var k: int = SaveSystem.keys()
	_use.text = "Use a key  ·  you have %d" % k if k > 0 else "No keys yet"
	_use.disabled = k <= 0


func _refresh_video(video: Button) -> void:
	var left: int = SaveSystem.video_keys_left()
	video.text = "Watch a video for a key  ·  %d left today" % left if left > 0 else "Free keys are back tomorrow"


func _use_key() -> void:
	var id: String = str(Levels.level(chapter_id, index)["id"])
	if SaveSystem.use_key(id):
		AudioManager.play("unlock", 1.0)
		Haptics.tap(20)
		app.close_settings()
		app.open_game(chapter_id, index)
