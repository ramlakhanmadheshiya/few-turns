@tool
extends EditorPlugin
## Bundles the FewTurnsShare Android library (built by CI from plugins_src/fewturns_share)
## into Android exports. Without the .aar the export still works; the game then
## falls back to calling Android directly.

var _export: AndroidExport


func _enter_tree() -> void:
	_export = AndroidExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class AndroidExport:
	extends EditorExportPlugin
	const AAR: String = "fewturns_share/bin/fewturns_share-release.aar"

	func _get_name() -> String:
		return "FewTurnsShare"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if FileAccess.file_exists("res://addons/" + AAR):
			return PackedStringArray([AAR])
		return PackedStringArray()
