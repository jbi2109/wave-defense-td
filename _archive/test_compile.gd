extends SceneTree
func _init():
	var rd = RenderingServer.get_rendering_device()
	var file = load("res://scripts/compute_flow_field.glsl")
	var spirv = file.get_spirv()
	if spirv:
		print("SUCCESS")
	else:
		print("FAILED")
	quit()
