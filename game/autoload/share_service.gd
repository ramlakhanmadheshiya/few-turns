extends Node
## Sharing and saving the result card.
## - Android: the system share sheet with the picture attached (through the app's
##   FileProvider), and "Save" writes it to Pictures/Few Turns.
## - Web: the browser's share sheet where it can share files, else a download.
## - Desktop: saves to the Pictures folder and shows it.
## Every path falls back to copying the link, so sharing never dead-ends.

signal finished(ok: bool, message: String)

const URL: String = "https://theramlakhan.com/few-turns/"
const DIR: String = "user://share"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))


func message_for(info: Dictionary) -> String:
	return "Few Turns · %s, level %d: %s Can you find the turns? %s" % [info["chapter"], int(info["number"]), str(info["verdict"]), URL]


func file_name(info: Dictionary) -> String:
	return "few-turns-%s-%02d.png" % [str(info["chapter"]).to_lower(), int(info["number"])]


## Writes the picture to the app's share folder; returns the absolute path.
func _write(img: Image, name: String) -> String:
	var path: String = ProjectSettings.globalize_path(DIR + "/" + name)
	if img == null or img.save_png(path) != OK:
		return ""
	return path


func share(img: Image, info: Dictionary) -> void:
	var text: String = message_for(info)
	var path: String = _write(img, file_name(info))
	if OS.has_feature("android") and _android_share(path, text):
		finished.emit(true, "")
		return
	if OS.has_feature("web") and img != null:
		_web_share(img, file_name(info), text)
		return
	if not path.is_empty() and not OS.has_feature("mobile"):
		save(img, info)
		DisplayServer.clipboard_set(text)
		return
	DisplayServer.clipboard_set(text)
	finished.emit(true, "Link copied: paste it anywhere")


func save(img: Image, info: Dictionary) -> void:
	var name: String = file_name(info)
	if img == null:
		finished.emit(false, "Couldn't make the picture on this device.")
		return
	if OS.has_feature("android"):
		var path: String = _write(img, name)
		if _android_save(path, name):
			finished.emit(true, "Saved to Pictures › Few Turns")
		else:
			# Older Android: hand it to the share sheet ("Save to device" lives there).
			finished.emit(_android_share(path, message_for(info)), "")
		return
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), name, "image/png")
		finished.emit(true, "Downloaded " + name)
		return
	var dir: String = OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir.is_empty():
		dir = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var out: String = dir.path_join(name)
	if img.save_png(out) == OK:
		OS.shell_show_in_file_manager(out)
		finished.emit(true, "Saved to " + out.get_base_dir().get_file())
	else:
		finished.emit(false, "Couldn't save the picture.")


func copy_link(info: Dictionary) -> void:
	DisplayServer.clipboard_set(message_for(info))
	finished.emit(true, "Link copied: paste it anywhere")


# --- Android --------------------------------------------------------------------
# The FewTurnsShare plugin (plugins_src/fewturns_share) does the work; if it is
# missing, the same calls are made straight from GDScript through JavaClassWrapper.

func _plugin() -> Object:
	return Engine.get_singleton("FewTurnsShare") if Engine.has_singleton("FewTurnsShare") else null


func _activity() -> Object:
	var rt: Object = Engine.get_singleton("AndroidRuntime") if Engine.has_singleton("AndroidRuntime") else null
	return rt.call("getActivity") if rt != null else null


func _android_share(path: String, text: String) -> bool:
	var plugin: Object = _plugin()
	if plugin != null:
		return bool(plugin.call("share", path, "image/png", text))
	var activity: Object = _activity()
	if activity == null:
		return false
	var intent_class: Object = JavaClassWrapper.wrap("android.content.Intent")
	if intent_class == null:
		return false
	var intent: Object = intent_class.call("Intent")
	intent.call("setAction", intent_class.get("ACTION_SEND"))
	intent.call("putExtra", intent_class.get("EXTRA_TEXT"), text)
	var uri: Object = null
	if not path.is_empty():
		var file_class: Object = JavaClassWrapper.wrap("java.io.File")
		var provider: Object = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
		if file_class != null and provider != null:
			uri = provider.call("getUriForFile", activity, str(activity.call("getPackageName")) + ".fileprovider", file_class.call("File", path))
	if uri != null:
		intent.call("setType", "image/png")
		intent.call("putExtra", intent_class.get("EXTRA_STREAM"), uri)
		intent.call("addFlags", intent_class.get("FLAG_GRANT_READ_URI_PERMISSION"))
	else:
		intent.call("setType", "text/plain")
	var chooser: Object = intent_class.call("createChooser", intent, "Share your run")
	if chooser == null:
		return false
	chooser.call("addFlags", intent_class.get("FLAG_GRANT_READ_URI_PERMISSION"))
	activity.call("startActivity", chooser)
	return true


## Android 10+: insert into MediaStore under Pictures/Few Turns.
func _android_save(path: String, name: String) -> bool:
	var plugin: Object = _plugin()
	if plugin != null and not path.is_empty():
		return bool(plugin.call("saveImage", path, name))
	var activity: Object = _activity()
	if activity == null or path.is_empty():
		return false
	var version: Object = JavaClassWrapper.wrap("android.os.Build$VERSION")
	if version == null or int(version.get("SDK_INT")) < 29:
		return false
	var values_class: Object = JavaClassWrapper.wrap("android.content.ContentValues")
	var media: Object = JavaClassWrapper.wrap("android.provider.MediaStore$Images$Media")
	var file_utils: Object = JavaClassWrapper.wrap("android.os.FileUtils")
	var input_class: Object = JavaClassWrapper.wrap("java.io.FileInputStream")
	if values_class == null or media == null or file_utils == null or input_class == null:
		return false
	var values: Object = values_class.call("ContentValues")
	values.call("put", "_display_name", name)
	values.call("put", "mime_type", "image/png")
	values.call("put", "relative_path", "Pictures/Few Turns")
	var resolver: Object = activity.call("getContentResolver")
	var uri: Object = resolver.call("insert", media.get("EXTERNAL_CONTENT_URI"), values)
	if uri == null:
		return false
	var out: Object = resolver.call("openOutputStream", uri)
	var src: Object = input_class.call("FileInputStream", path)
	if out == null or src == null:
		return false
	file_utils.call("copy", src, out)
	src.call("close")
	out.call("close")
	return true


# --- Web -------------------------------------------------------------------------

func _web_share(img: Image, name: String, text: String) -> void:
	var b64: String = Marshalls.raw_to_base64(img.save_png_to_buffer())
	var js: String = """
	(async () => {
	  try {
	    const bytes = Uint8Array.from(atob('%s'), c => c.charCodeAt(0));
	    const file = new File([bytes], '%s', {type: 'image/png'});
	    if (navigator.canShare && navigator.canShare({files: [file]})) {
	      await navigator.share({files: [file], text: %s});
	      return 'shared';
	    }
	    if (navigator.share) { await navigator.share({text: %s}); return 'shared'; }
	  } catch (e) { if (e && e.name === 'AbortError') return 'cancelled'; }
	  return 'fallback';
	})()
	""" % [b64, name, JSON.stringify(text), JSON.stringify(text)]
	JavaScriptBridge.eval(js, true)
	# The promise resolves on its own; also hand over the file and the link so a
	# browser without file sharing still gets something useful.
	if not bool(JavaScriptBridge.eval("!!(navigator.canShare)", true)):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), name, "image/png")
		DisplayServer.clipboard_set(text)
		finished.emit(true, "Picture downloaded and link copied")
	else:
		finished.emit(true, "")
