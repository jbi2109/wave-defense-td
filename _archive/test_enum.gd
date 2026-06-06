extends SceneTree
func _init():
	for k in ClassDB.class_get_integer_constant_list('RenderingDevice'):
		print(k)
	quit()

