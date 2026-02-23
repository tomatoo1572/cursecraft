class_name VoxelChunkMesh
extends Node3D

static var _mat: StandardMaterial3D = null

var cx: int = 0
var cy: int = 0
var cz: int = 0

var _mi: MeshInstance3D = null

func _ensure_ready() -> void:
	if _mi == null:
		_mi = MeshInstance3D.new()
		add_child(_mi)

	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 1.0
		_mat.metallic = 0.0

func set_chunk(chunk: ChunkData, sim: WorldSim = null) -> void:
	if chunk == null:
		return
	_ensure_ready()

	cx = chunk.cx
	cy = chunk.cy
	cz = chunk.cz

	var S: int = ChunkData.CHUNK_SIZE
	position = Vector3(float(cx * S), float(cy * S), float(cz * S))

	var m: ArrayMesh = VoxelMesher.build_mesh(chunk, sim)
	_mi.mesh = m
	_mi.material_override = _mat
