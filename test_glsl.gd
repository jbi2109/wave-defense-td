extends SceneTree

func _init():
	var rd = RenderingServer.create_local_rendering_device()
	var shader_file = load("res://scripts/compute_physics.glsl")
	if shader_file:
		var spirv = shader_file.get_spirv()
		var shader = rd.shader_create_from_spirv(spirv)
		if shader.is_valid():
			print("SUCCESS")
		else:
			print("SHADER ERROR")
	else:
		print("COULD NOT LOAD FILE")
	quit()
