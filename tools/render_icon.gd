extends SceneTree
func _initialize() -> void:
	var base := ProjectSettings.globalize_path("res://assets/")
	var svg := FileAccess.get_file_as_string(base.path_join("openfpv.svg"))
	var sizes := [16, 24, 32, 48, 64, 128, 256]
	var buffers: Array[PackedByteArray] = []
	for size: int in sizes:
		var image := Image.new()
		if image.load_svg_from_string(svg, 2) != OK: quit(1); return
		image.resize(size, size, Image.INTERPOLATE_LANCZOS)
		buffers.append(image.save_png_to_buffer())
	var output := FileAccess.open(base.path_join("openfpv.ico"), FileAccess.WRITE)
	output.store_16(0)
	output.store_16(1)
	output.store_16(sizes.size())
	var offset := 6 + sizes.size() * 16
	for index in sizes.size():
		output.store_8(sizes[index] % 256)
		output.store_8(sizes[index] % 256)
		output.store_16(0)
		output.store_16(1)
		output.store_16(32)
		output.store_32(buffers[index].size())
		output.store_32(offset)
		offset += buffers[index].size()
	for buffer in buffers: output.store_buffer(buffer)
	output.close()
	var preview := Image.new()
	preview.load_svg_from_string(svg)
	preview.save_png(base.path_join("openfpv.png"))
	print("ICON_OK sizes=16,24,32,48,64,128,256")
	quit()
