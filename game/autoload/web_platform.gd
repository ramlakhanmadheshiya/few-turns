extends Node
## The browser rules, read from the Brainnova Studio play page
## (theramlakhan.com/BrainnovaStudio/play/few-turns/, see its play.js):
## - iPhone, iPad and Mac play every level, with every ad type;
## - other computers play the first `level_cap()` levels, with no full-screen ads;
## - Android never reaches the web build (it is sent to Google Play).
## Anywhere else (Android app, desktop, or the bare web export) nothing is limited.

var _bn: JavaScriptObject = null
var _cap: int = 0
var _interstitials: bool = true


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_bn = JavaScriptBridge.get_interface("Brainnova")
	if _bn == null:
		return
	var policy: Variant = JSON.parse_string(str(_bn.policyJSON()))
	if policy is Dictionary:
		_cap = int(policy.get("levelCap", 0))
		_interstitials = bool(policy.get("interstitials", false))


## True when running on the studio play page.
func active() -> bool:
	return _bn != null


## The JS object behind it all (for the web ad provider).
func api() -> JavaScriptObject:
	return _bn


## How many levels the browser may play (0 = all of them).
func level_cap() -> int:
	return _cap


func interstitials_allowed() -> bool:
	return _interstitials


## True if (chapter_id, index) lies beyond the free levels, counted in play order.
func over_cap(chapter_id: String, index: int) -> bool:
	if _cap <= 0:
		return false
	var n: int = 0
	for c: Dictionary in Levels.chapters:
		if str(c["id"]) == chapter_id:
			return n + index >= _cap
		n += (c.get("levels", []) as Array).size()
	return true


## Where to stream an asset that the web pack leaves out ("music/ch1.ogg"), or "".
func asset_url(rel: String) -> String:
	if _bn == null:
		return ""
	return str(_bn.assetUrl(rel))


## Shows the page's "get the full game" card over the game.
func show_full_game() -> void:
	if _bn != null:
		_bn.capReached()
