extends Node
## Short vibrations on phones, scaled to how important the moment is.


func tap(ms: int = 10) -> void:
	if not bool(SaveSystem.get_setting("haptics", true)):
		return
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		Input.vibrate_handheld(ms)
