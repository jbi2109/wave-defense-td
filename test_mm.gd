extends SceneTree

func _init():
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.instance_count = 1
	var t = Transform2D(0, Vector2(100, 200))
	mm.set_instance_transform_2d(0, t)
	mm.set_instance_color(0, Color(1, 2, 3, 4))
	mm.set_instance_custom_data(0, Color(5, 6, 7, 8))
	
	var data = mm.buffer
	print("Buffer size: ", data.size())
	print("Floats per instance: ", data.size() / 4)
	
	var floats = []
	for i in range(data.size() / 4):
		floats.append(data.decode_float(i * 4))
	print("Data: ", floats)
	
	quit()

