extends Node
## Renders store/feature_graphic.png (1024 x 500) and store/icon_512.png.
## Run: godot --path . --resolution 1024x500 res://tools/render_feature_graphic.tscn


func _ready() -> void:
	# Draw 1:1 in pixels, not through the game's 720 x 1280 stretch.
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = Vector2i(1024, 500)
	var art: Control = load("res://tools/feature_graphic.gd").new()
	art.size = Vector2(1024, 500)
	add_child(art)
	for i: int in 6:
		await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img.get_size() != Vector2i(1024, 500):
		img.resize(1024, 500, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	img.save_png(ProjectSettings.globalize_path("res://store/feature_graphic.png"))
	# Play icon: a full-bleed square (Play rounds the corners itself), no transparency.
	var svg: String = FileAccess.get_file_as_string("res://assets/icon.svg").replace('rx="232"', 'rx="0"')
	var icon: Image = Image.new()
	icon.load_svg_from_string(svg, 0.5)
	icon.convert(Image.FORMAT_RGB8)
	icon.save_png(ProjectSettings.globalize_path("res://store/icon_512.png"))
	print("rendered feature graphic and icon")
	get_tree().quit()
