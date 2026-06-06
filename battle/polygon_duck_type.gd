extends Polygon2D

class PointArrayHelper:
	var vertices: PackedVector2Array
	func _init(v: PackedVector2Array):
		vertices = v
	func get_vertices() -> PackedVector2Array:
		return vertices

func get_point_array() -> PointArrayHelper:
	return PointArrayHelper.new(polygon)
