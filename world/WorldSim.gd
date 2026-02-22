extends RefCounted
class_name WorldSim

var world_id: String = ""
var world_seed: int = 0
var world_preset: String = "default"
var game_mode: String = "survival"

var _storage: ChunkStorage
var _gen: WorldGen

# key "cx,cy,cz" -> ChunkData
var _chunks: Dictionary = {}
# dirty keys -> true
var _dirty: Dictionary = {}

func _init(p_world_id: String, p_seed: int, p_preset: String, p_mode: String) -> void:
	world_id = p_world_id
	world_seed = p_seed
	world_preset = p_preset
	game_mode = p_mode

	_storage = ChunkStorage.new()
	_storage.ensure_world_chunks_dir(world_id)

	_gen = WorldGen.new(world_seed)

func preload_spawn_area(spawn_xyz: Array, radius_chunks: int = 1) -> int:
	var sx: int = 0
	var sy: int = 64
	var sz: int = 0
	if spawn_xyz.size() == 3:
		sx = int(spawn_xyz[0])
		sy = int(spawn_xyz[1])
		sz = int(spawn_xyz[2])

	var ccx: int = floor_div_int(sx, ChunkData.CHUNK_SIZE)
	var ccy: int = floor_div_int(sy, ChunkData.CHUNK_SIZE)
	var ccz: int = floor_div_int(sz, ChunkData.CHUNK_SIZE)

	var created_count: int = 0
	for dz in range(-radius_chunks, radius_chunks + 1):
		for dx in range(-radius_chunks, radius_chunks + 1):
			var cx: int = ccx + dx
			var cz: int = ccz + dz
			var before: bool = _storage.has_chunk(world_id, cx, ccy, cz)
			_get_or_load_or_generate_chunk(cx, ccy, cz)
			if not before:
				created_count += 1
	return created_count

func get_block_id_global(wx: int, wy: int, wz: int) -> String:
	var cx: int = floor_div_int(wx, ChunkData.CHUNK_SIZE)
	var cy: int = floor_div_int(wy, ChunkData.CHUNK_SIZE)
	var cz: int = floor_div_int(wz, ChunkData.CHUNK_SIZE)

	var lx: int = floor_mod_int(wx, ChunkData.CHUNK_SIZE)
	var ly: int = floor_mod_int(wy, ChunkData.CHUNK_SIZE)
	var lz: int = floor_mod_int(wz, ChunkData.CHUNK_SIZE)

	var chunk: ChunkData = _get_or_load_or_generate_chunk(cx, cy, cz)
	return chunk.get_block_id(lx, ly, lz)

func set_block_id_global(wx: int, wy: int, wz: int, block_id: String) -> void:
	var safe_id: String = _sanitize_block_id(block_id)

	var cx: int = floor_div_int(wx, ChunkData.CHUNK_SIZE)
	var cy: int = floor_div_int(wy, ChunkData.CHUNK_SIZE)
	var cz: int = floor_div_int(wz, ChunkData.CHUNK_SIZE)

	var lx: int = floor_mod_int(wx, ChunkData.CHUNK_SIZE)
	var ly: int = floor_mod_int(wy, ChunkData.CHUNK_SIZE)
	var lz: int = floor_mod_int(wz, ChunkData.CHUNK_SIZE)

	var chunk: ChunkData = _get_or_load_or_generate_chunk(cx, cy, cz)
	chunk.set_block_id(lx, ly, lz, safe_id)

	var k: String = _key(cx, cy, cz)
	_dirty[k] = true

func save_dirty() -> int:
	var keys: Array = _dirty.keys()
	var saved: int = 0
	for k in keys:
		var ck: String = str(k)
		var chunk: ChunkData = _chunks.get(ck, null) as ChunkData
		if chunk == null:
			continue
		if _storage.save_chunk(world_id, chunk):
			saved += 1
	_dirty.clear()
	return saved

func unload_all(save_first: bool = true) -> void:
	if save_first:
		save_dirty()
	_chunks.clear()
	_dirty.clear()

# -------------------------
# Internals
# -------------------------

func _get_or_load_or_generate_chunk(cx: int, cy: int, cz: int) -> ChunkData:
	var k: String = _key(cx, cy, cz)
	if _chunks.has(k):
		return _chunks[k] as ChunkData

	var loaded: ChunkData = _storage.load_chunk(world_id, cx, cy, cz)
	if loaded != null:
		_chunks[k] = loaded
		return loaded

	var created: ChunkData = _gen.generate_chunk(cx, cy, cz, world_preset)
	_storage.save_chunk(world_id, created)
	_chunks[k] = created
	return created

func _sanitize_block_id(block_id: String) -> String:
	var id: String = block_id.strip_edges()
	if id.is_empty():
		return "core:air"
	if ContentRegistry != null and ContentRegistry.has_method("has_block"):
		if not bool(ContentRegistry.call("has_block", id)):
			return "core:air"
	return id

static func _key(cx: int, cy: int, cz: int) -> String:
	return "%d,%d,%d" % [cx, cy, cz]

static func floor_div_int(a: int, b: int) -> int:
	return int(floor(float(a) / float(b)))

static func floor_mod_int(a: int, b: int) -> int:
	var d: int = floor_div_int(a, b)
	return a - d * b
