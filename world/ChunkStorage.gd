extends RefCounted
class_name ChunkStorage

func ensure_world_chunks_dir(world_id: String) -> void:
	Paths.ensure_world_chunks_dir(world_id)

func chunk_path(world_id: String, cx: int, cy: int, cz: int) -> String:
	var fname: String = "c.%d.%d.%d.bin" % [cx, cy, cz]
	return Paths.world_chunks_dir(world_id).path_join(fname)

func has_chunk(world_id: String, cx: int, cy: int, cz: int) -> bool:
	return FileAccess.file_exists(chunk_path(world_id, cx, cy, cz))

func load_chunk(world_id: String, cx: int, cy: int, cz: int) -> ChunkData:
	var path: String = chunk_path(world_id, cx, cy, cz)
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_error("ChunkStorage: chunk file empty: %s" % path)
		return null
	var chunk: ChunkData = ChunkCodec.decode(bytes)
	if chunk == null:
		push_error("ChunkStorage: decode failed: %s" % path)
		return null
	return chunk

func save_chunk(world_id: String, chunk: ChunkData) -> bool:
	if chunk == null or not chunk.is_valid():
		push_error("ChunkStorage: save_chunk invalid chunk")
		return false

	ensure_world_chunks_dir(world_id)
	var path: String = chunk_path(world_id, chunk.cx, chunk.cy, chunk.cz)
	var bytes: PackedByteArray = ChunkCodec.encode(chunk)
	if bytes.is_empty():
		push_error("ChunkStorage: encode failed: %s" % path)
		return false

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ChunkStorage: cannot open for write: %s" % path)
		return false
	f.store_buffer(bytes)
	f.flush()
	f.close()
	return true
