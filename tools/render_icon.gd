extends SceneTree
## Renders every icon from its SVG source:
## - store/icon_512.png: the Play Store icon, a full-bleed square (Play rounds the
##   corners itself, so the tile's own rounding is dropped);
## - assets/android/icon_*.png: the launcher icon and its adaptive layers;
## - assets/splash.png: the boot splash (the rounded tile).
## Run: godot --headless --path . -s res://tools/render_icon.gd


func _init() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var tile: String = FileAccess.get_file_as_string("res://assets/icon.svg")
	_render(tile.replace('rx="232"', 'rx="0"'), 512, root.path_join("store/icon_512.png"))
	_render(tile, 192, root.path_join("assets/android/icon_main.png"))
	_render(tile, 348, root.path_join("assets/splash.png"))
	for layer: String in ["background", "foreground", "monochrome"]:
		var svg: String = FileAccess.get_file_as_string("res://assets/android/src/%s.svg" % layer)
		_render(svg, 432, root.path_join("assets/android/icon_%s.png" % layer))
	quit()


func _render(svg: String, px: int, out: String) -> void:
	var img: Image = Image.new()
	img.load_svg_from_string(svg, float(px) / 1024.0)
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(out)
	print("icon ", img.get_size(), " -> ", out)
