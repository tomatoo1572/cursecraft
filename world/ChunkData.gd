extends RefCounted
class_name ChunkData

const CHUNK_SIZE: int = 16
const CELL_COUNT: int = CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE

var cx: int = 0
var cy: int = 0
var cz: int = 0

# palette[index] => block_id string (e.g. "core:stone")
var palette: PackedStringArray = PackedStringArray()

# indices[cell_index] => palette index (int)
var indices: PackedInt32Array = PackedInt32Array()

# Cached runtime palette (palette string -> runtime int)
var _runtime_palette: PackedInt32Array = PackedInt32Array()
var _runtime_palette_valid: bool = false

func _init(p_cx: int = 0, p_cy: int = 0, p_cz: int = 0) -> void:
	cx = p_cx
	cy = p_cy
	cz = p_cz
	palette = PackedStringArray()
	indices = PackedInt32Array()
	indices.resize(CELL_COUNT)
	fill_with_palette_id("core:air")

func is_valid() -> bool:
	if indices.size() != CELL_COUNT:
		return false
	if palette.is_empty():
		return false
	for v in indices:
		if v < 0 or v >= palette.size():
			return false
	return true

func fill_with_palette_id(block_id: String) -> void:
	palette = PackedStringArray([block_id])
	indices.resize(CELL_COUNT)
	for i in CELL_COUNT:
		indices[i] = 0
	_invalidate_runtime_palette()

func set_block_id(lx: int, ly: int, lz: int, block_id: String) -> void:
	var idx: int = _to_index(lx, ly, lz)
	if idx < 0:
		return
	var pidx: int = _get_or_add_palette_index(block_id)
	indices[idx] = pidx

func get_block_id(lx: int, ly: int, lz: int) -> String:
	var idx: int = _to_index(lx, ly, lz)
	if idx < 0:
		return "core:air"
	var pidx: int = indices[idx]
	if pidx < 0 or pidx >= palette.size():
		return "core:air"
	return palette[pidx]

func get_block_runtime_id(lx: int, ly: int, lz: int) -> int:
	var idx: int = _to_index(lx, ly, lz)
	if idx < 0:
		return 0
	if not _runtime_palette_valid:
		build_runtime_palette()
	var pidx: int = indices[idx]
	if pidx < 0 or pidx >= _runtime_palette.size():
		return 0
	return int(_runtime_palette[pidx])

func build_runtime_palette() -> void:
	_runtime_palette.resize(palette.size())
	for i in palette.size():
		var bid: String = palette[i]
		var rid: int = 0
		if ContentRegistry != null and ContentRegistry.has_method("get_block_runtime_id"):
			rid = int(ContentRegistry.call("get_block_runtime_id", bid))
		_runtime_palette[i] = rid
	_runtime_palette_valid = true

func clear_runtime_palette_cache() -> void:
	_invalidate_runtime_palette()

func _invalidate_runtime_palette() -> void:
	_runtime_palette_valid = false
	_runtime_palette = PackedInt32Array()

func _get_or_add_palette_index(block_id: String) -> int:
	for i in palette.size():
		if palette[i] == block_id:
			return i
	palette.append(block_id)
	_invalidate_runtime_palette()
	return palette.size() - 1

static func _to_index(lx: int, ly: int, lz: int) -> int:
	if lx < 0 or lx >= CHUNK_SIZE:
		return -1
	if ly < 0 or ly >= CHUNK_SIZE:
		return -1
	if lz < 0 or lz >= CHUNK_SIZE:
		return -1
	# X fastest, then Z, then Y
	return lx + (lz * CHUNK_SIZE) + (ly * CHUNK_SIZE * CHUNK_SIZE)
