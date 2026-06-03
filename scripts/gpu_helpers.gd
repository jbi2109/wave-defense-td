class_name GPUHelpers

static func align_to(value: int, alignment: int) -> int:
	@warning_ignore("integer_division")
	return ((value + alignment - 1) / alignment) * alignment

static func rid_safe_free(rd: RenderingDevice, rid: RID) -> void:
	if rid.is_valid():
		rd.free_rid(rid)

class ReadbackBuffer:
	var rd: RenderingDevice
	var data_buffer: RID
	var buffer_count: int = 2
	var element_count: int = 1024
	var element_byte_size: int = 16
	var element_byte_alignment: int = 16
	var buffer_byte_size: int = 0
	var last_read: int = 0
	var last_write: int = 0

	func _init(rd_in: RenderingDevice, debug_name: String, 
		buffer_count_in: int = 2, element_count_in: int = 1024, 
		element_byte_size_in: int = 16, element_byte_alignment_in: int = 16) -> void:
		rd = rd_in
		var initial_arr := PackedByteArray()
		buffer_count = buffer_count_in
		element_count = element_count_in
		element_byte_size = element_byte_size_in
		element_byte_alignment = element_byte_alignment_in
		buffer_byte_size = GPUHelpers.align_to(element_byte_size, element_byte_alignment) * element_count

		var byte_count: int = 16 + buffer_count * buffer_byte_size
		initial_arr.resize(byte_count)
		initial_arr.fill(0)
		data_buffer = rd.storage_buffer_create(initial_arr.size(), initial_arr)
		rd.set_resource_name(data_buffer, debug_name)

	func free_rids() -> void:
		GPUHelpers.rid_safe_free(rd, data_buffer)

	func read_counted_async(callable: Callable) -> void:
		rd.buffer_get_data_async(data_buffer, func(data: PackedByteArray) -> void:
			var last_written := data.decode_u32(0)
			while last_read != last_written:
				var buffer_start: int = 16 + last_read * buffer_byte_size
				var valid_element_count: int = data.decode_u32(buffer_start)

				if valid_element_count > 0:
					var data_start := buffer_start + GPUHelpers.align_to(element_byte_size, element_byte_alignment)
					var data_byte_size := valid_element_count * GPUHelpers.align_to(element_byte_size, element_byte_alignment)
					callable.call(valid_element_count, data.slice(data_start, data_start + data_byte_size))
				
				last_read = (last_read + 1) % buffer_count
		)

	func increment_write() -> void:
		last_write = (last_write + 1) % buffer_count
		var last_write_bytes := PackedByteArray()
		last_write_bytes.resize(16)
		last_write_bytes.encode_s32(0, last_write)
		rd.buffer_update(data_buffer, 0, last_write_bytes.size(), last_write_bytes)

		var buffer_element_count_bytes := PackedByteArray()
		buffer_element_count_bytes.resize(4)
		buffer_element_count_bytes.fill(0)
		rd.buffer_update(data_buffer, 16 + last_write * buffer_byte_size, 4, buffer_element_count_bytes)

class ReadbackBufferInt32:
	var rd: RenderingDevice
	var buffer: RID
	var buffer_count: int = 4
	var last_read: int = 0
	var last_write: int = 0

	func _init(rd_in: RenderingDevice, debug_name: String) -> void:
		rd = rd_in
		var initial_arr := PackedInt32Array()
		initial_arr.resize(buffer_count + 1)
		initial_arr.fill(0)
		buffer = rd.storage_buffer_create(initial_arr.size() * 4, initial_arr.to_byte_array())
		rd.set_resource_name(buffer, debug_name)

	func read_accumulated_async(callable: Callable) -> void:
		rd.buffer_get_data_async(buffer, func(data: PackedByteArray) -> void:
			var last_written := data.decode_s32(0)
			var value: int = 0
			while last_read != last_written:
				value += data.decode_s32(4 + last_read * 4)
				last_read = (last_read + 1) % buffer_count
			if value > 0:
				callable.call(value)
		)

	func increment_write() -> void:
		last_write = (last_write + 1) % buffer_count
		rd.buffer_update(buffer, 0, 4, PackedInt32Array([last_write]).to_byte_array())
		rd.buffer_update(buffer, 4 + last_write * 4, 4, PackedInt32Array([0]).to_byte_array())

	func free_rids() -> void:
		GPUHelpers.rid_safe_free(rd, buffer)
