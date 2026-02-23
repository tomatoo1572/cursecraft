class_name VoxelMesher
extends RefCounted

const AIR_ID: String = "core:air"

static func build_mesh(chunk: ChunkData, sim: WorldSim = null) -> ArrayMesh:
	if chunk == null or not chunk.is_valid():
		return null

	var S: int = ChunkData.CHUNK_SIZE
	var palette_size: int = chunk.palette.size()
	if palette_size <= 0:
		return null

	# palette properties
	var solid: PackedByteArray = PackedByteArray()
	var transparent: PackedByteArray = PackedByteArray()
	var colors: PackedColorArray = PackedColorArray()
	solid.resize(palette_size)
	transparent.resize(palette_size)
	colors.resize(palette_size)

	for i in palette_size:
		var bid: String = chunk.palette[i]
		var is_solid: bool = (bid != AIR_ID)
		var is_trans: bool = false

		if ContentRegistry != null and ContentRegistry.has_method("has_block") and bool(ContentRegistry.call("has_block", bid)):
			var bd: BlockDef = ContentRegistry.call("get_block", bid) as BlockDef
			if bd != null:
				is_solid = bd.is_solid
				is_trans = bd.is_transparent

		solid[i] = 1 if is_solid else 0
		transparent[i] = 1 if is_trans else 0
		colors[i] = _color_for_block_id(bid)

	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var idxs: PackedInt32Array = PackedInt32Array()

	var indices: PackedInt32Array = chunk.indices

	# Chunk global origin (block coords)
	var base_gx: int = chunk.cx * S
	var base_gy: int = chunk.cy * S
	var base_gz: int = chunk.cz * S

	for ly in S:
		for lz in S:
			for lx in S:
				var cell: int = lx + (lz * S) + (ly * S * S)
				var pidx: int = int(indices[cell])
				if pidx < 0 or pidx >= palette_size:
					continue
				if solid[pidx] == 0:
					continue

				var c: Color = colors[pidx]

				var gx: int = base_gx + lx
				var gy: int = base_gy + ly
				var gz: int = base_gz + lz

				# +X
				if _face_visible(sim, indices, S, lx, ly, lz, 1, 0, 0, gx + 1, gy, gz, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx + 1, ly,     lz),
						Vector3(lx + 1, ly + 1, lz),
						Vector3(lx + 1, ly + 1, lz + 1),
						Vector3(lx + 1, ly,     lz + 1),
						Vector3(1, 0, 0), c)

				# -X
				if _face_visible(sim, indices, S, lx, ly, lz, -1, 0, 0, gx - 1, gy, gz, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx, ly,     lz + 1),
						Vector3(lx, ly + 1, lz + 1),
						Vector3(lx, ly + 1, lz),
						Vector3(lx, ly,     lz),
						Vector3(-1, 0, 0), c)

				# +Y
				if _face_visible(sim, indices, S, lx, ly, lz, 0, 1, 0, gx, gy + 1, gz, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx,     ly + 1, lz),
						Vector3(lx,     ly + 1, lz + 1),
						Vector3(lx + 1, ly + 1, lz + 1),
						Vector3(lx + 1, ly + 1, lz),
						Vector3(0, 1, 0), c)

				# -Y
				if _face_visible(sim, indices, S, lx, ly, lz, 0, -1, 0, gx, gy - 1, gz, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx,     ly, lz + 1),
						Vector3(lx,     ly, lz),
						Vector3(lx + 1, ly, lz),
						Vector3(lx + 1, ly, lz + 1),
						Vector3(0, -1, 0), c)

				# +Z
				if _face_visible(sim, indices, S, lx, ly, lz, 0, 0, 1, gx, gy, gz + 1, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx + 1, ly,     lz + 1),
						Vector3(lx + 1, ly + 1, lz + 1),
						Vector3(lx,     ly + 1, lz + 1),
						Vector3(lx,     ly,     lz + 1),
						Vector3(0, 0, 1), c)

				# -Z
				if _face_visible(sim, indices, S, lx, ly, lz, 0, 0, -1, gx, gy, gz - 1, solid, transparent):
					_add_face(verts, norms, cols, idxs,
						Vector3(lx,     ly,     lz),
						Vector3(lx,     ly + 1, lz),
						Vector3(lx + 1, ly + 1, lz),
						Vector3(lx + 1, ly,     lz),
						Vector3(0, 0, -1), c)

	if verts.is_empty():
		return null

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _face_visible(
	sim: WorldSim,
	indices: PackedInt32Array,
	S: int,
	lx: int, ly: int, lz: int,
	dx: int, dy: int, dz: int,
	ng_x: int, ng_y: int, ng_z: int,
	solid: PackedByteArray,
	transparent: PackedByteArray
) -> bool:
	var nx: int = lx + dx
	var ny: int = ly + dy
	var nz: int = lz + dz

	# Neighbor inside same chunk → use palette flags
	if nx >= 0 and nx < S and ny >= 0 and ny < S and nz >= 0 and nz < S:
		var cell: int = nx + (nz * S) + (ny * S * S)
		var n_pidx: int = int(indices[cell])
		if n_pidx < 0 or n_pidx >= solid.size():
			return true
		var occludes: bool = (solid[n_pidx] == 1 and transparent[n_pidx] == 0)
		return not occludes

	# Neighbor is in another chunk → ask WorldSim (prevents z-fighting)
	if sim == null:
		return true

	var n_id: String = sim.get_block_id_global(ng_x, ng_y, ng_z)
	return not _occludes_id(n_id)

static func _occludes_id(block_id: String) -> bool:
	if block_id == AIR_ID:
		return false
	if ContentRegistry != null and ContentRegistry.has_method("has_block") and bool(ContentRegistry.call("has_block", block_id)):
		var bd: BlockDef = ContentRegistry.call("get_block", block_id) as BlockDef
		if bd != null:
			return bd.is_solid and (not bd.is_transparent)
	# Fallback: treat unknown as solid
	return true

static func _add_face(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	cols: PackedColorArray,
	idxs: PackedInt32Array,
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	n: Vector3, c: Color
) -> void:
	var base: int = verts.size()
	verts.append(v0); verts.append(v1); verts.append(v2); verts.append(v3)
	norms.append(n);  norms.append(n);  norms.append(n);  norms.append(n)
	cols.append(c);   cols.append(c);   cols.append(c);   cols.append(c)

	idxs.append(base + 0); idxs.append(base + 1); idxs.append(base + 2)
	idxs.append(base + 0); idxs.append(base + 2); idxs.append(base + 3)

static func _color_for_block_id(block_id: String) -> Color:
	match block_id:
		"core:grass":
			return Color(0.25, 0.75, 0.25)
		"core:dirt":
			return Color(0.45, 0.30, 0.18)
		"core:stone":
			return Color(0.55, 0.55, 0.55)
		"core:cobblestone":
			return Color(0.45, 0.45, 0.45)
		"core:sand":
			return Color(0.85, 0.80, 0.55)
		_:
			# If you ever see this, your generator is producing unknown IDs.
			return Color(0.9, 0.1, 0.9)
