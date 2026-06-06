@tool
extends McpTestSuite

func suite_name() -> String:
	return "shader"

func test_compile_physics_shader() -> void:
	var file = load("res://shaders/compute_physics.glsl")
	assert_true(file != null, "compute_physics.glsl should load")
	if file != null:
		var spirv = file.get_spirv()
		assert_true(spirv != null, "compute_physics.glsl should compile successfully to SPIR-V")
