extends Node
## Drives the real app through every screen and saves screenshots.
## Run (needs a window): godot --path . res://tests/capture.tscn -- <out_dir> [--store]
## --store renders a full 1080 x 1920 phone screen, whatever the monitor, and saves
## the raw shots tools/store_art.py composes into the store screenshots.

var out_dir: String = "user://captures"
var _store_vp: SubViewport
var app: Control
var _backup: Dictionary


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty() and not args[0].begins_with("--"):
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	AudioManager.mute_for_tests = true
	_backup = SaveSystem.data.duplicate(true)
	app = (load("res://game/scenes/main.tscn") as PackedScene).instantiate()
	if args.has("--store"):
		_store_vp = SubViewport.new()
		_store_vp.size = Vector2i(1080, 1920)
		_store_vp.size_2d_override = Vector2i(720, 1280)
		_store_vp.size_2d_override_stretch = true
		_store_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_store_vp)
		_store_vp.add_child(app)
	else:
		add_child(app)
	_run.call_deferred()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = (_store_vp if _store_vp != null else get_viewport()).get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("captured ", name)


func _board() -> Board:
	return app.current.get("board") as Board


## A believable save: Path well under way, a few chapters open, some stars.
func _progress() -> void:
	SaveSystem.reset_progress()
	SaveSystem.data["owned"] = {}
	for cid: String in ["ch1", "ch2", "ch3"]:
		var n: int = 40 if cid == "ch1" else (24 if cid == "ch2" else 16)
		for i: int in n:
			SaveSystem.data["levels"]["%s_%02d" % [cid, i + 1]] = {"stars": 3 if i % 4 != 2 else 2, "best": 1}
	for f: String in ["tutorial_done", "intro_ch1", "intro_ch2", "intro_ch3"]:
		SaveSystem.data["flags"][f] = true
	SaveSystem.data["last"] = {"chapter": "ch3", "index": 16}


## Opens a room, lays all but `hold` of its solution's arrows, and waits.
func _room(cid: String, index: int, hold: int = 0) -> Board:
	app.open_game(cid, index)
	await _wait(1.2)
	var b: Board = _board()
	var sol: Dictionary = RouteSim.solution_arrows(b.level)
	var keys: Array = sol.keys()
	for k: int in maxi(0, keys.size() - hold):
		b.point_cell(int(keys[k]), int(sol[keys[k]]))
	await _wait(0.6)
	return b


## Presses Go and waits `seconds` into the run.
func _roll(b: Board, seconds: float) -> void:
	b.go()
	await _wait(seconds)


func _run() -> void:
	if OS.get_cmdline_user_args().has("--store"):
		await _store()
		get_tree().quit()
		return
	SaveSystem.reset_progress()
	SaveSystem.data["owned"] = {}
	await _wait(0.6)
	await _shot("00_splash")
	await _wait(2.6)
	await _shot("01_home")
	app.open_game("ch1", 0)
	await _wait(1.4)
	await _shot("02_tutorial")
	_progress()
	app.open_home()
	await _wait(1.2)
	await _shot("03_home_progress")
	app.open_chapters()
	await _wait(1.4)
	await _shot("04_chapters")
	app.open_levels("ch3")
	await _wait(1.0)
	await _shot("05_levels")
	SaveSystem.data["flags"].erase("intro_ch4")
	app.open_game("ch4", 0)
	await _wait(1.2)
	await _shot("06_chapter_intro")
	app.current.find_child("GotIt", true, false).emit_signal("pressed")
	await _wait(0.8)
	await _shot("07_intro_spotlight")
	SaveSystem.set_flag("intro_ch4")
	var specs: Array = [["ch1", 14], ["ch2", 22], ["ch3", 30], ["ch4", 20], ["ch5", 24], ["ch6", 18], ["ch7", 26], ["ch8", 28], ["ch9", 33]]
	for spec: Array in specs:
		var b: Board = await _room(spec[0], spec[1], 99)
		await _shot("10_%s_%02d_room" % [spec[0], int(spec[1]) + 1])
		b = await _room(spec[0], spec[1], 0)
		await _shot("11_%s_%02d_laid" % [spec[0], int(spec[1]) + 1])
		await _roll(b, 1.2)
		await _shot("12_%s_%02d_rolling" % [spec[0], int(spec[1]) + 1])
	await _wait(5.0)
	await _shot("13_result")
	app.current.find_child("Share", true, false).emit_signal("pressed")
	await _wait(1.5)
	await _shot("14_share")
	app.close_settings()
	var m: Board = await _room("ch1", 20, 1)
	m.go()
	while m.playing:
		await _wait(0.1)
	await _wait(0.5)
	await _shot("15_missed")
	app.current.find_child("Hint", true, false).emit_signal("pressed")
	await _wait(0.6)
	await _shot("16_hint")
	app.open_settings(true)
	await _wait(0.6)
	await _shot("17_settings")
	app.open_how_to_play()
	await _wait(0.6)
	await _shot("18_how_to_play")
	app.open_setting_info("long_guide")
	await _wait(0.8)
	await _shot("19_guide_info")
	app.close_settings()
	app.open_shop()
	await _wait(1.0)
	await _shot("20_shop")
	app.open_about()
	await _wait(0.8)
	await _shot("21_about")
	app.close_settings()
	SaveSystem.data = _backup
	SaveSystem.save()
	get_tree().quit()


## Raw shots for the store screenshots (tools/store_art.py lays them out).
func _store() -> void:
	_progress()
	await _wait(3.2)
	app.open_home()
	await _wait(1.6)
	await _shot("raw_home")
	var b: Board = await _room("ch1", 24, 99)
	await _shot("raw_room")
	b = await _room("ch1", 24, 0)
	await _shot("raw_laid")
	await _roll(b, 1.6)
	await _shot("raw_rolling")
	await _wait(6.0)
	await _shot("raw_result")
	for spec: Array in [["ch3", 30], ["ch5", 24], ["ch6", 18], ["ch9", 33]]:
		b = await _room(spec[0], spec[1], 0)
		await _roll(b, 0.5)
		await _shot("raw_%s" % spec[0])
	var m: Board = await _room("ch2", 26, 1)
	m.go()
	while m.playing:
		await _wait(0.1)
	await _wait(0.4)
	app.current.find_child("Hint", true, false).emit_signal("pressed")
	await _wait(0.8)
	await _shot("raw_hint")
	app.open_chapters()
	await _wait(1.6)
	await _shot("raw_chapters")
	SaveSystem.data = _backup
	SaveSystem.save()
