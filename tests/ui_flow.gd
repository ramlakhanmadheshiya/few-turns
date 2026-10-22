extends Node
## End-to-end flow through the real app, headless:
## home -> play -> miss (back to the start) -> arrows -> hint -> home -> result -> next ->
## chapter intro -> settings, pickers, shop and product cards -> back.
## Run: godot --headless --path . res://tests/ui_flow.tscn

var app: Control
var failures: int = 0
var _backup: Dictionary


func _ready() -> void:
	AudioManager.mute_for_tests = true
	_backup = SaveSystem.data.duplicate(true)
	SaveSystem.reset_progress()
	SaveSystem.data["owned"] = {}
	SaveSystem.data["flags"]["supporter"] = false
	SaveSystem.data["keys"] = 0
	SaveSystem.data["hint_day"] = ""
	SaveSystem.data["trials"] = {}
	SaveSystem.data["settings"]["theme"] = "chapters"
	SaveSystem.data["settings"]["orb_style"] = "classic"
	SaveSystem._apply_cosmetics()
	app = (load("res://game/scenes/main.tscn") as PackedScene).instantiate()
	add_child(app)
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok  ", label)
	else:
		failures += 1
		push_error("FAILED: " + label)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _find(name: String) -> Node:
	return app.find_child(name, true, false)


func _screen_is(file: String) -> bool:
	return app.current != null and app.current.get_script().resource_path.ends_with(file)


## Waits until the board's run is over (bounded).
func _settle(board: Board) -> void:
	for i: int in 200:
		if not board.playing:
			break
		await _wait(0.05)
	await _wait(0.4)


func _run() -> void:
	await _wait(0.6)
	_check(_screen_is("home_screen.gd"), "starts on the home screen")
	_check(_find("Shop") != null, "home has a shop button")
	_check((_find("Title") as Label).text == "Few Turns", "home shows the name, capitalised, on one line")
	_check(_find("Play") != null and _find("Chapters") != null and _find("Continue") != null, "home keeps Play, the continue line and Chapters")
	(_find("Play") as Button).pressed.emit()
	await _wait(0.8)
	var board: Board = app.current.get("board")
	_check(board != null and str(board.level.get("id", "")) == "ch1_01", "Play opens the first room")
	_check(board.turns() == 1 and board.arrows_left() == 1, "the first room gives one turn")
	_check(_find("Tutorial") != null and _find("Go") != null, "first play shows the hands-on tutorial and a Go button")

	# A miss puts the orb back at the start and says why.
	(_find("Go") as Button).pressed.emit()
	await _wait(0.1)
	_check(board.playing, "Go rolls the orb")
	await _settle(board)
	_check(not board.playing and int(board.get("_live")["tick"]) == 0, "a miss puts the orb back at the start")
	_check(SaveSystem.misses("ch1_01") == 1, "the miss is counted as a try")
	var hud: Control = _find("Hud")
	_check(int(hud.get("attempt")) == 2 and int(hud.get("stars")) == 2, "the HUD shows try 2 with two stars still on offer")
	_check(not (board.get("_ghost") as Array).is_empty(), "the missed path stays visible as a guide")

	# Laying arrows: a tap lays one, more taps turn it; with none left, a tap says so.
	var sol: Dictionary = RouteSim.solution_arrows(board.level)
	var right_cell: int = int(sol.keys()[0])
	var spare: int = -1
	for c: int in int(board.level["w"]) * int(board.level["h"]):
		if RouteSim.placeable(board.level, c) and c != right_cell:
			spare = c
			break
	board.tap_cell(spare)
	_check(board.arrows.has(spare) and board.arrows_left() == 0 and int(hud.get("left")) == 0, "a tap lays an arrow and TURNS counts down")
	var first_dir: int = int(board.arrows[spare])
	board.tap_cell(spare)
	_check(int(board.arrows[spare]) == (first_dir + 1) % 4, "tapping an arrow turns it a quarter")
	board.tap_cell(right_cell)
	_check(not board.arrows.has(right_cell), "with no arrows left, a tap on a free cell lays nothing")
	board.tap_cell(spare)
	board.tap_cell(spare)
	board.tap_cell(spare)
	_check(not board.arrows.has(spare) and board.arrows_left() == 1, "after four turns, a tap takes the arrow back")
	board.point_cell(spare, 2)
	_check(int(board.arrows.get(spare, -1)) == 2, "a swipe points the arrow the way of the swipe")

	var hints_before: int = SaveSystem.hints_left()
	(_find("Hint") as Button).pressed.emit()
	_check(SaveSystem.hints_left() == hints_before - 1 and board.hint_showing(), "a hint is spent and the way is shown")
	_check((board.get("_ghost") as Array).is_empty(), "a hint clears the trace of the last miss, so the lines don't tangle")
	_check(not board.arrows.has(spare), "a hint takes back arrows that aren't part of the way")
	board.point_cell(right_cell, int(sol[right_cell]))
	_check(board.hint_showing(), "the hint stays while laying arrows, until Go")
	(_find("Go") as Button).pressed.emit()
	await _settle(board)
	await _wait(0.8)
	_check(SaveSystem.stars_for("ch1_01") == 2, "a second-try clear with a hint earns two stars")
	_check(SaveSystem.flag("tutorial_done"), "clearing the tutorial room finishes the tutorial")
	for n: String in ["Next", "Watch", "Share", "Replay", "Levels"]:
		_check(_find(n) != null, "result card offers %s" % n)
	(_find("Watch") as Button).pressed.emit()
	await _wait(0.2)
	_check(board.playing and board.replaying, "Watch replays the winning run")
	await _settle(board)
	await _wait(1.0)
	_check(SaveSystem.stars_for("ch1_01") == 2, "watching a replay records nothing new")
	(_find("Share") as Button).pressed.emit()
	await _wait(0.5)
	_check(_find("ShareNow") != null and _find("Save") != null and _find("CopyLink") != null, "share card offers share, save and copy link")
	_check(ShareService.message_for({"chapter": "Path", "number": 1, "verdict": "First try. Perfect."}).contains("theramlakhan.com/few-turns"), "the share message links to the game")
	app.close_settings()
	(_find("Next") as Button).pressed.emit()
	await _wait(0.8)
	board = app.current.get("board")
	_check(str(board.level.get("id", "")) == "ch1_02", "Next opens room 2")

	# Restart is a fresh start: no arrows, back to try 1 with three stars on offer.
	(_find("Go") as Button).pressed.emit()
	await _settle(board)
	_check(int(_find("Hud").get("attempt")) == 2, "a miss on room 2 counts a try")
	_check(not (board.get("_ghost") as Array).is_empty(), "the miss trace shows before Restart")
	board.place_solution()
	(_find("Restart") as Button).pressed.emit()
	await _wait(0.2)
	_check((board.get("_ghost") as Array).is_empty() and board.arrows.is_empty(), "Restart clears the arrows and the trace of the last miss")
	_check(int(_find("Hud").get("attempt")) == 1 and int(_find("Hud").get("stars")) == 3 and SaveSystem.misses("ch1_02") == 0, "Restart resets to try 1 with three stars")
	# A first-try run home on a fresh room is three stars.
	board.place_solution()
	(_find("Go") as Button).pressed.emit()
	await _settle(board)
	await _wait(0.8)
	_check(SaveSystem.stars_for("ch1_02") == 3, "a first-try clear earns three stars")

	app.open_settings(true)
	await _wait(0.3)
	_check(_find("Settings") != null, "settings opens from inside a level")
	_check(_find("Reset") == null, "progress reset is hidden while playing a level")
	_check(_find("PickColours") != null and _find("PickOrbs") != null, "settings offers colour and orb pickers")
	((_find("Row_shake") as Node).find_child("Info", true, false) as Button).pressed.emit()
	await _wait(0.3)
	_check(_find("SettingInfo") != null and _find("Demo") != null, "tapping a setting's name explains it with a demo")
	(_find("BackToSettings") as Button).pressed.emit()
	await _wait(0.3)
	_check(_find("Settings") != null, "the explainer returns to settings")
	app.go_back()
	await _wait(0.3)
	_check(_find("Settings") == null, "back closes settings first")
	app.go_back()
	await _wait(0.6)
	_check(_screen_is("levels_screen.gd"), "back from a room goes to its level grid")
	_check(Levels.level_open("ch1", 2) and not Levels.level_open("ch1", 3), "levels unlock strictly one at a time")
	app.go_back()
	await _wait(0.6)
	_check(_screen_is("chapters_screen.gd"), "back goes to chapters")
	_check(Levels.chapters.size() == 9 and _find("Chapter_ch9") != null, "nine chapters, Pair included")
	var order: Array = Levels.chapters.map(func(c: Dictionary) -> String: return str(c["name"]))
	_check(order == ["Path", "Signs", "Bank", "Gate", "Spin", "Shift", "Crumble", "Count", "Pair"], "chapters run Path, Signs, Bank, Gate, Spin, Shift, Crumble, Count, Pair")
	_check(_find("Art") is ChapterArt, "chapter cards show their chapter's scene")
	_check(not Levels.chapter_open("ch2"), "chapter 2 stays locked until 15 Path clears")
	app.go_back()
	await _wait(0.6)
	_check(_screen_is("home_screen.gd"), "back from chapters goes home")
	app._last_back_msec = -1000
	app.go_back()
	await _wait(0.3)
	_check(_find("Confirm") != null, "back on home asks before quitting")
	(_find("No") as Button).pressed.emit()
	await _wait(0.3)

	# Chapter intro: the opening room of a new chapter teaches its idea.
	app.open_game("ch2", 0)
	await _wait(0.8)
	_check(_find("ChapterIntro") != null, "a chapter's first room opens with its tutorial card")
	(_find("GotIt") as Button).pressed.emit()
	await _wait(0.3)
	_check((app.current.get("board") as Board).hint_showing(), "after the card, the way is shown once")
	_check(SaveSystem.flag("intro_ch2"), "the chapter tutorial is remembered")

	# Shop, product cards, pickers.
	app.open_shop()
	await _wait(0.8)
	_check(_screen_is("shop_screen.gd"), "shop opens")
	for id: String in Store.PRODUCTS:
		_check(_find("Product_" + id) != null, "shop lists %s" % id)
	_check(_find("Product_keys") != null and _find("Product_all_levels") == null, "shop sells level keys, not every level")
	_check(_find("TipJar") != null and _find("Restore") != null, "shop has a tip jar and restore")
	(_find("Product_orb_pack") as Button).pressed.emit()
	await _wait(0.4)
	_check(_find("Product") != null and _find("Buy") != null and _find("Trial") != null, "a cosmetic pack card offers buy and a video trial")
	(_find("Buy") as Button).pressed.emit()
	await _wait(0.3)
	_check(SaveSystem.bought("orb_pack"), "buying the orb pack (simulated in debug) unlocks it")
	app.open_picker("orbs")
	await _wait(0.3)
	(_find("Pick_comet") as Button).pressed.emit()
	await _wait(0.3)
	_check(SaveSystem.orb_style() == "comet", "an owned orb style can be chosen")
	app.open_picker("themes")
	await _wait(0.3)
	(_find("Pick_nord") as Button).pressed.emit()
	await _wait(0.5)
	_check(_find("Product") != null and Palette.theme_id == "chapters", "a locked theme opens its pack instead")
	SaveSystem.start_trial("theme_pack")
	_check(SaveSystem.trial_left("theme_pack") <= 3600 and SaveSystem.trial_clock("theme_pack").begins_with("59:") or SaveSystem.trial_clock("theme_pack").begins_with("60:"), "a video trial lasts one hour, with a live clock")
	app.open_picker("themes")
	await _wait(0.3)
	(_find("Pick_nord") as Button).pressed.emit()
	await _wait(0.8)
	_check(Palette.theme_id == "nord" and Color(Palette.get_palette("ch1")["top"]) == Color("#2E3440"), "a theme on trial repaints the game")
	SaveSystem.data["trials"]["theme_pack"] = 0
	SaveSystem._apply_cosmetics()
	_check(Palette.theme_id == "chapters", "themes fall back to chapter colours when a trial ends")
	app.close_settings()
	_check(Store.complete_saving() > 20, "the complete pack is a real saving (%d%%)" % Store.complete_saving())
	_check(Store.REGIONAL_TIERS["IN"][Store.tier_of("supporter_pack")] == "₹249", "regional price table includes rupees")
	# Level keys: buy with the stepper (simulated), then open any locked room.
	app.open_keys()
	await _wait(0.3)
	(_find("Plus") as Button).pressed.emit()
	(_find("Quick_5") as Button).pressed.emit()
	_check((_find("BuyKeys") as Button).text.contains("5 keys"), "the key stepper picks how many")
	var before_keys: int = SaveSystem.keys()
	(_find("BuyKeys") as Button).pressed.emit()
	await _wait(0.2)
	_check(SaveSystem.keys() == before_keys + 5, "buying 5 keys adds 5 keys")
	_check(Store.keys_price(5).length() > 0 and Store.KEY_UNIT["IN"][1] == 30.0, "keys cost ₹30 each")
	SaveSystem.data["video_key_day"] = ""
	_check(SaveSystem.video_keys_left() == 5, "videos give up to 5 free keys a day")
	app.open_levels("ch5")
	await _wait(0.8)
	_check(_find("Keys") != null and _find("Hero") != null, "the level page shows the hero card and keys")
	_check(_find("Level_40") != null, "every level number is listed, locked ones too")
	(_find("Level_7") as Button).pressed.emit()
	await _wait(0.4)
	_check(_find("Locked") != null and _find("UseKey") != null and _find("VideoKey") != null, "a locked room offers a key or a video")
	(_find("UseKey") as Button).pressed.emit()
	await _wait(0.8)
	_check(SaveSystem.keys() == before_keys + 4 and Levels.level_open("ch5", 6), "a key opens that room for good")
	_check(_screen_is("game_screen.gd"), "and plays it straight away")
	app.open_tips()
	await _wait(0.3)
	_check(_find("Tip_20") != null and _find("Tip_200") != null and _find("TipAmount") != null, "tip jar has preset amounts and a custom one")
	(_find("TipAmount") as LineEdit).text = "563"
	(_find("TipAmount") as LineEdit).text_changed.emit("563")
	_check(int(_find("Tips").call("_custom")) == 560 and (_find("TipCustom") as Button).text.contains(Store.price("tip_560")), "a custom tip rounds to Play's steps")
	app.close_settings()

	# Out of hints with no ad available: the hint is given free, never a dead end.
	app.open_game("ch1", 1)
	await _wait(0.8)
	SaveSystem.data["hints"] = 0
	(_find("Hint") as Button).pressed.emit()
	await _wait(0.2)
	_check((app.current.get("board") as Board).hint_showing() and SaveSystem.hints_left() == 0, "no ad available -> free hint")
	SaveSystem.data["hint_day"] = "2000-01-01"
	_check(SaveSystem.hints_left() == SaveSystem.DAILY_HINTS, "hints refill to exactly 3 on a new day")
	app.open_about()
	await _wait(0.3)
	_check(_find("About") != null and _find("Privacy") != null and _find("Help") != null, "about links to privacy and help")
	app.open_credits()
	await _wait(0.3)
	_check(_find("CardScroll") != null, "credits scroll inside a floating card")
	app.close_settings()

	SaveSystem.data = _backup
	SaveSystem.save()
	SaveSystem._apply_cosmetics()
	print("UI FLOW: ", "FAIL (%d)" % failures if failures > 0 else "PASS")
	get_tree().quit(1 if failures > 0 else 0)
