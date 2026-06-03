extends SceneTree

func _init():
	var obj = Node.new()
	var id = obj.get_instance_id()
	print("Instance ID: ", id)
	print("Is > 32 bits: ", id > 4294967295)
	var trunc = id & 0xFFFFFFFF
	print("Truncated: ", trunc)
	print("Instance from truncated: ", instance_from_id(trunc))
	quit()
