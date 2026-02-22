extends RefCounted
class_name WorldGen

const AIR_ID: String = "core:air"
const STONE_ID: String = "core:stone"
const DIRT_ID: String = "core:dirt"
const GRASS_ID: String = "core:grass"
const SAND_ID: String = "core:sand"

const SEA_LEVEL: int = 64

var _noise: FastNoiseLite

func _init(world_seed: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = world_seed
	_noise.frequency = 0.008
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

func generate_chunk(cx: int, cy: int, cz: int, preset: String) -> ChunkData:
	var chunk: ChunkData = ChunkData.new(cx, cy, cz)
	chunk.fill_with_palette_id(AIR_ID)

	var preset_lc: String = preset.strip_edges().to_lower()
	if preset_lc.is_empty():
		preset_lc = "default"

	if preset_lc == "flat":
		_generate_flat(chunk)
	else:
		_generate_default(chunk)

	return chunk

func _generate_flat(chunk: ChunkData) -> void:
	var base_height: int = SEA_LEVEL - 1 # grass at y=63

	for ly in ChunkData.CHUNK_SIZE:
		var gy: int = chunk.cy * ChunkData.CHUNK_SIZE + ly
		for lz in ChunkData.CHUNK_SIZE:
			for lx in ChunkData.CHUNK_SIZE:
				var block_id: String = AIR_ID
				if gy < base_height - 3:
					block_id = _pick_existing(STONE_ID)
				elif gy < base_height:
					block_id = _pick_existing(DIRT_ID)
				elif gy == base_height:
					block_id = _pick_existing(GRASS_ID)
				else:
					block_id = AIR_ID

				chunk.set_block_id(lx, ly, lz, block_id)

func _generate_default(chunk: ChunkData) -> void:
	for ly in ChunkData.CHUNK_SIZE:
		var gy: int = chunk.cy * ChunkData.CHUNK_SIZE + ly
		for lz in ChunkData.CHUNK_SIZE:
			var gz: int = chunk.cz * ChunkData.CHUNK_SIZE + lz
			for lx in ChunkData.CHUNK_SIZE:
				var gx: int = chunk.cx * ChunkData.CHUNK_SIZE + lx

				var h: int = _height_at(gx, gz)
				var block_id: String = AIR_ID

				if gy < h - 4:
					block_id = _pick_existing(STONE_ID)
				elif gy < h:
					if h <= SEA_LEVEL + 1 and _sand_chance(gx, gz):
						block_id = _pick_existing(SAND_ID, DIRT_ID)
					else:
						block_id = _pick_existing(DIRT_ID)
				elif gy == h:
					if h <= SEA_LEVEL + 1 and _sand_chance(gx, gz):
						block_id = _pick_existing(SAND_ID, GRASS_ID)
					else:
						block_id = _pick_existing(GRASS_ID)
				else:
					block_id = AIR_ID

				chunk.set_block_id(lx, ly, lz, block_id)

func _height_at(gx: int, gz: int) -> int:
	var n: float = _noise.get_noise_2d(float(gx), float(gz)) # -1..1
	var amp: float = 10.0
	var hh: int = SEA_LEVEL + int(round(n * amp))
	if hh < 1:
		hh = 1
	return hh

func _sand_chance(gx: int, gz: int) -> bool:
	var n: float = _noise.get_noise_2d(float(gx) + 1000.0, float(gz) - 1000.0)
	return n > 0.55

func _pick_existing(primary_id: String, fallback_id: String = AIR_ID) -> String:
	if _has_block(primary_id):
		return primary_id
	if _has_block(fallback_id):
		return fallback_id
	return AIR_ID

func _has_block(block_id: String) -> bool:
	# If registry isn't ready, allow generation anyway.
	if ContentRegistry == null:
		return true
	if ContentRegistry.has_method("has_block"):
		return bool(ContentRegistry.call("has_block", block_id))
	if "blocks_by_id" in ContentRegistry:
		var d: Dictionary = ContentRegistry.blocks_by_id
		return d.has(block_id)
	return true
