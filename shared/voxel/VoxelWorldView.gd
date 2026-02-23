class_name VoxelWorldView
extends Node3D

@export var radius_xz: int = 1
@export var cy_radius: int = 1
@export var refresh_interval: float = 0.35
@export var max_chunks_per_frame: int = 1
@export var unload_far: bool = true

var _sim: WorldSim = null
var _player: PlayerSave = null

var _accum: float = 0.0
var _chunk_nodes: Dictionary = {} # key -> VoxelChunkMesh
var _want: Dictionary = {}        # key -> true

var _queue: Array[String] = []
var _queued: Dictionary = {}      # key -> true
var _last_center: Vector3i = Vector3i(999999, 999999, 999999)

func set_world(sim: WorldSim, player: PlayerSave) -> void:
	_sim = sim
	_player = player
	_clear_all()
	_last_center = Vector3i(999999, 999999, 999999)
	_rebuild_targets(true)

func clear_world() -> void:
	_clear_all()
	_sim = null
	_player = null

func _process(dt: float) -> void:
	if _sim == null or _player == null:
		return

	_accum += dt
	if _accum >= refresh_interval:
		_accum = 0.0
		_rebuild_targets(false)

	# Build a few queued chunks per frame (prevents big pauses)
	var n: int = max_chunks_per_frame
	while n > 0 and _queue.size() > 0:
		var key: String = _queue.pop_front()
		_queued.erase(key)

		if not _want.has(key):
			n -= 1
			continue
		if _chunk_nodes.has(key):
			n -= 1
			continue

		var parts := key.split(",")
		if parts.size() != 3:
			n -= 1
			continue

		var cx: int = int(parts[0])
		var cy: int = int(parts[1])
		var cz: int = int(parts[2])

		var chunk: ChunkData = _sim.get_chunk(cx, cy, cz)
		var node := VoxelChunkMesh.new()
		add_child(node)
		node.set_chunk(chunk, _sim)
		_chunk_nodes[key] = node

		n -= 1

	# Unload far chunks
	if unload_far:
		_unload_not_wanted()

func _rebuild_targets(force: bool) -> void:
	var wx: int = _player.pos.x
	var wy: int = _player.pos.y
	var wz: int = _player.pos.z

	var ccx: int = WorldSim.floor_div_int(wx, ChunkData.CHUNK_SIZE)
	var ccy: int = WorldSim.floor_div_int(wy, ChunkData.CHUNK_SIZE)
	var ccz: int = WorldSim.floor_div_int(wz, ChunkData.CHUNK_SIZE)

	var center := Vector3i(ccx, ccy, ccz)
	if (not force) and center == _last_center:
		return
	_last_center = center

	_want.clear()

	for dz in range(-radius_xz, radius_xz + 1):
		for dx in range(-radius_xz, radius_xz + 1):
			var cx: int = ccx + dx
			var cz: int = ccz + dz
			for dy in range(-cy_radius, cy_radius + 1):
				var cy: int = ccy + dy
				var key: String = "%d,%d,%d" % [cx, cy, cz]
				_want[key] = true
				if not _chunk_nodes.has(key) and not _queued.has(key):
					_queue.append(key)
					_queued[key] = true

func _unload_not_wanted() -> void:
	var to_remove: Array[String] = []
	for k in _chunk_nodes.keys():
		var key: String = str(k)
		if not _want.has(key):
			to_remove.append(key)

	for key2 in to_remove:
		var n: Node = _chunk_nodes[key2]
		if is_instance_valid(n):
			n.queue_free()
		_chunk_nodes.erase(key2)

func _clear_all() -> void:
	for k in _chunk_nodes.keys():
		var n: Node = _chunk_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
	_chunk_nodes.clear()
	_want.clear()
	_queue.clear()
	_queued.clear()
