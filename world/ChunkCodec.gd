extends RefCounted
class_name ChunkCodec

const VERSION: int = 1
const MAGIC_U32: int = 0x43434B31 # "CCK1" (CurseCraft Chunk v1), little-endian write/read

static func encode(chunk: ChunkData) -> PackedByteArray:
	if chunk == null or not chunk.is_valid():
		push_error("ChunkCodec.encode: chunk invalid")
		return PackedByteArray()

	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.big_endian = false

	sp.put_u32(MAGIC_U32)
	sp.put_u8(VERSION)
	sp.put_u8(ChunkData.CHUNK_SIZE)
	sp.put_32(chunk.cx)
	sp.put_32(chunk.cy)
	sp.put_32(chunk.cz)

	# palette
	var pal_count: int = chunk.palette.size()
	if pal_count <= 0 or pal_count > 65535:
		push_error("ChunkCodec.encode: invalid palette size=%d" % pal_count)
		return PackedByteArray()
	sp.put_u16(pal_count)

	for i in pal_count:
		var s: String = chunk.palette[i]
		var bytes: PackedByteArray = s.to_utf8_buffer()
		if bytes.size() > 65535:
			push_error("ChunkCodec.encode: palette string too long index=%d" % i)
			return PackedByteArray()
		sp.put_u16(bytes.size())
		sp.put_data(bytes)

	# RLE over indices
	var runs: Array[Dictionary] = _build_rle_runs(chunk.indices, pal_count)
	sp.put_u32(runs.size())

	for r in runs:
		var run_len: int = int(r["len"])
		var pal_idx: int = int(r["idx"])
		sp.put_u16(run_len)
		sp.put_u16(pal_idx)

	return sp.data_array

static func decode(bytes: PackedByteArray) -> ChunkData:
	if bytes.is_empty():
		return null

	var sp: StreamPeerBuffer = StreamPeerBuffer.new()
	sp.big_endian = false
	sp.data_array = bytes
	sp.seek(0)

	if sp.get_available_bytes() < 4:
		push_error("ChunkCodec.decode: buffer too small")
		return null

	var magic: int = int(sp.get_u32())
	if magic != MAGIC_U32:
		push_error("ChunkCodec.decode: bad magic")
		return null

	var ver: int = int(sp.get_u8())
	if ver != VERSION:
		push_error("ChunkCodec.decode: unsupported version=%d" % ver)
		return null

	var size: int = int(sp.get_u8())
	if size != ChunkData.CHUNK_SIZE:
		push_error("ChunkCodec.decode: unsupported chunk size=%d" % size)
		return null

	var cx: int = int(sp.get_32())
	var cy: int = int(sp.get_32())
	var cz: int = int(sp.get_32())

	var pal_count: int = int(sp.get_u16())
	if pal_count <= 0:
		push_error("ChunkCodec.decode: palette count invalid")
		return null

	var palette: PackedStringArray = PackedStringArray()
	palette.resize(pal_count)

	for i in pal_count:
		var slen: int = int(sp.get_u16())
		if slen < 0 or slen > sp.get_available_bytes():
			push_error("ChunkCodec.decode: invalid string length")
			return null
		var data: PackedByteArray = sp.get_data(slen)
		palette[i] = data.get_string_from_utf8()

	var run_count: int = int(sp.get_u32())
	if run_count <= 0:
		push_error("ChunkCodec.decode: invalid run_count=%d" % run_count)
		return null

	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(ChunkData.CELL_COUNT)

	var cursor: int = 0
	for _i in run_count:
		if sp.get_available_bytes() < 4:
			push_error("ChunkCodec.decode: truncated runs")
			return null
		var run_len: int = int(sp.get_u16())
		var pal_idx: int = int(sp.get_u16())
		if run_len <= 0:
			push_error("ChunkCodec.decode: run_len invalid")
			return null
		if pal_idx < 0 or pal_idx >= pal_count:
			push_error("ChunkCodec.decode: pal_idx out of range")
			return null
		for _j in run_len:
			if cursor >= ChunkData.CELL_COUNT:
				push_error("ChunkCodec.decode: too many cells in runs")
				return null
			indices[cursor] = pal_idx
			cursor += 1

	if cursor != ChunkData.CELL_COUNT:
		push_error("ChunkCodec.decode: cell count mismatch got=%d expected=%d" % [cursor, ChunkData.CELL_COUNT])
		return null

	var chunk: ChunkData = ChunkData.new(cx, cy, cz)
	chunk.palette = palette
	chunk.indices = indices

	if not chunk.is_valid():
		push_error("ChunkCodec.decode: decoded chunk invalid")
		return null

	return chunk

static func _build_rle_runs(indices: PackedInt32Array, pal_count: int) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	if indices.size() != ChunkData.CELL_COUNT:
		push_error("ChunkCodec: indices size mismatch")
		return runs

	var current: int = int(indices[0])
	if current < 0 or current >= pal_count:
		current = 0
	var run_len: int = 1

	for i in range(1, indices.size()):
		var v: int = int(indices[i])
		if v < 0 or v >= pal_count:
			v = 0
		if v == current and run_len < 65535:
			run_len += 1
		else:
			runs.append({"len": run_len, "idx": current})
			current = v
			run_len = 1

	runs.append({"len": run_len, "idx": current})

	if runs.is_empty():
		# should never happen
		runs.append({"len": ChunkData.CELL_COUNT, "idx": 0})

	return runs
