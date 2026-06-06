extends SceneTree

func _init():
	var t = Transform2D(0, Vector2(100, 100)).scaled(Vector2(-1, 1))
	print("Origin: ", t.origin)
	quit()
