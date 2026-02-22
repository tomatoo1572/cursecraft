extends Node

const WORLD_VERSION: int = 1

func _ready() -> void:
	Paths.ensure_dirs()

func list_worlds() -> Array[Dictionary]:
	Paths.ensure_dirs()

	var result: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(Paths.worlds_dir())
	if dir == null:
		push_error("WorldManager: Cannot open worlds dir: %s" % Paths.worlds_dir())
		return result

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		if dir.current_is_dir():
			var world_id: String = entry_name
			var meta: Dictionary = _read_world_meta(world_id)
			if meta.is_empty():
				continue
			result.append(meta)
	dir.list_dir_end()

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var al: String = str(a.get("last_played_utc", ""))
		var bl: String = str(b.get("last_played_utc", ""))
		if al != bl:
			return al > bl
		var ac: String = str(a.get("created_utc", ""))
		var bc: String = str(b.get("created_utc", ""))
		if ac != bc:
			return ac > bc
		var an: String = str(a.get("name", ""))
		var bn: String = str(b.get("name", ""))
		return an.nocasecmp_to(bn) < 0
	)

	return result

func create_world(world_name: String, world_seed: int, mode: String, preset: String) -> String:
	Paths.ensure_dirs()

	var safe_world_name: String = world_name.strip_edges()
	if safe_world_name.is_empty():
		safe_world_name = "New World"

	var game_mode: String = mode.strip_edges().to_lower()
	if game_mode != "survival" and game_mode != "creative":
		game_mode = "survival"

	var worldgen_preset: String = preset.strip_edges()
	if worldgen_preset.is_empty():
		worldgen_preset = "default"

	var final_seed: int = world_seed
	if final_seed == 0:
		final_seed = _random_seed()

	var world_id: String = _make_world_id(safe_world_name)
	Paths.ensure_world_dir(world_id)
	Paths.ensure_world_chunks_dir(world_id)

	var now_utc: String = Time.get_datetime_string_from_system(true)

	var meta: Dictionary = {
		"world_id": world_id,
		"name": safe_world_name,
		"seed": final_seed,
		"created_utc": now_utc,
		"last_played_utc": now_utc,
		"game_mode": game_mode,
		"spawn": [0, 64, 0],
		"worldgen_preset": worldgen_preset,
		"version": WORLD_VERSION
	}

	_write_world_meta(world_id, meta)
	return world_id

func load_world(world_id: String) -> Dictionary:
	Paths.ensure_dirs()

	var meta: Dictionary = _read_world_meta(world_id)
	if meta.is_empty():
		push_error("WorldManager: Failed to load world meta for world_id=%s" % world_id)
		return {}

	meta["last_played_utc"] = Time.get_datetime_string_from_system(true)
	_write_world_meta(world_id, meta)

	return meta

func save_world_meta(world_id: String, meta: Dictionary) -> void:
	Paths.ensure_dirs()
	if meta.is_empty():
		push_error("WorldManager: save_world_meta called with empty meta (world_id=%s)" % world_id)
		return
	var fixed: Dictionary = _normalize_world_meta(world_id, meta)
	_write_world_meta(world_id, fixed)

func rename_world(world_id: String, new_name: String) -> void:
	var meta: Dictionary = _read_world_meta(world_id)
	if meta.is_empty():
		push_error("WorldManager: rename_world failed; missing world_id=%s" % world_id)
		return
	var trimmed: String = new_name.strip_edges()
	if trimmed.is_empty():
		push_error("WorldManager: rename_world ignored empty new_name for world_id=%s" % world_id)
		return
	meta["name"] = trimmed
	_write_world_meta(world_id, meta)

func delete_world(world_id: String) -> void:
	Paths.ensure_dirs()
	var wdir: String = Paths.world_dir(world_id)
	if not DirAccess.dir_exists_absolute(wdir):
		push_error("WorldManager: delete_world; world dir not found: %s" % wdir)
		return
	var err: int = _remove_dir_recursive(wdir)
	if err != OK:
		push_error("WorldManager: delete_world failed for %s (err=%d)" % [wdir, err])

func duplicate_world(world_id: String, new_name: String) -> String:
	Paths.ensure_dirs()

	var src_dir: String = Paths.world_dir(world_id)
	if not DirAccess.dir_exists_absolute(src_dir):
		push_error("WorldManager: duplicate_world; source world dir not found: %s" % src_dir)
		return ""

	var meta: Dictionary = _read_world_meta(world_id)
	if meta.is_empty():
		push_error("WorldManager: duplicate_world; missing meta for world_id=%s" % world_id)
		return ""

	var safe_world_name: String = new_name.strip_edges()
	if safe_world_name.is_empty():
		safe_world_name = str(meta.get("name", "Copy"))

	var new_id: String = _make_world_id(safe_world_name)
	var dst_dir: String = Paths.world_dir(new_id)
	Paths.ensure_world_dir(new_id)
	Paths.ensure_world_chunks_dir(new_id)

	var err_copy: int = _copy_dir_recursive(src_dir, dst_dir)
	if err_copy != OK:
		push_error("WorldManager: duplicate_world copy failed (err=%d)" % err_copy)
		_remove_dir_recursive(dst_dir)
		return ""

	var now_utc: String = Time.get_datetime_string_from_system(true)
	meta["world_id"] = new_id
	meta["name"] = safe_world_name
	meta["created_utc"] = now_utc
	meta["last_played_utc"] = now_utc
	meta["version"] = WORLD_VERSION
	_write_world_meta(new_id, meta)

	return new_id

# -------------------------
# Internals
# -------------------------

func _normalize_world_meta(world_id: String, meta: Dictionary) -> Dictionary:
	var fixed: Dictionary = meta.duplicate(true)

	fixed["world_id"] = str(fixed.get("world_id", world_id))
	if str(fixed["world_id"]).is_empty():
		fixed["world_id"] = world_id

	var world_name_val: String = str(fixed.get("name", "New World")).strip_edges()
	if world_name_val.is_empty():
		world_name_val = "New World"
	fixed["name"] = world_name_val

	var seed_val: Variant = fixed.get("seed", 0)
	var seed_i: int = 0
	if seed_val is int:
		seed_i = int(seed_val)
	elif seed_val is float:
		seed_i = int(seed_val)
	else:
		seed_i = 0
	if seed_i == 0:
		seed_i = _random_seed()
	fixed["seed"] = seed_i

	var created: String = str(fixed.get("created_utc", ""))
	if created.is_empty():
		created = Time.get_datetime_string_from_system(true)
	fixed["created_utc"] = created

	var lastp: String = str(fixed.get("last_played_utc", ""))
	if lastp.is_empty():
		lastp = created
	fixed["last_played_utc"] = lastp

	var gm: String = str(fixed.get("game_mode", "survival")).to_lower()
	if gm != "survival" and gm != "creative":
		gm = "survival"
	fixed["game_mode"] = gm

	var spawn_v: Variant = fixed.get("spawn", [0, 64, 0])
	var spawn_arr: Array = []
	if spawn_v is Array:
		spawn_arr = spawn_v as Array
	if spawn_arr.size() != 3:
		spawn_arr = [0, 64, 0]
	else:
		spawn_arr[0] = int(spawn_arr[0])
		spawn_arr[1] = int(spawn_arr[1])
		spawn_arr[2] = int(spawn_arr[2])
	fixed["spawn"] = spawn_arr

	var preset_val: String = str(fixed.get("worldgen_preset", "default")).strip_edges()
	if preset_val.is_empty():
		preset_val = "default"
	fixed["worldgen_preset"] = preset_val

	var ver_v: Variant = fixed.get("version", WORLD_VERSION)
	var ver: int = WORLD_VERSION
	if ver_v is int:
		ver = int(ver_v)
	elif ver_v is float:
		ver = int(ver_v)
	fixed["version"] = ver

	return fixed

func _read_world_meta(world_id: String) -> Dictionary:
	var path: String = Paths.world_meta_path(world_id)
	if not FileAccess.file_exists(path):
		return {}

	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("WorldManager: world.json empty or unreadable: %s" % path)
		return {}

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("WorldManager: JSON parse failed for %s" % path)
		return {}
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WorldManager: world.json is not an object: %s" % path)
		return {}

	return _normalize_world_meta(world_id, parsed as Dictionary)

func _write_world_meta(world_id: String, meta: Dictionary) -> void:
	Paths.ensure_world_dir(world_id)
	Paths.ensure_world_chunks_dir(world_id)

	var path: String = Paths.world_meta_path(world_id)
	var fixed: Dictionary = _normalize_world_meta(world_id, meta)
	var json_text: String = JSON.stringify(fixed, "\t")

	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("WorldManager: Failed to open for write: %s" % path)
		return
	f.store_string(json_text)
	f.flush()
	f.close()

func _make_world_id(world_name: String) -> String:
	var ts: int = int(Time.get_unix_time_from_system())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var r: int = rng.randi_range(100000, 999999)

	var base: String = "%s_%d_%d" % [_fs_safe(world_name), ts, r]
	if base.length() > 64:
		base = base.substr(0, 64)
	return base

func _fs_safe(s: String) -> String:
	var t: String = s.strip_edges().to_lower()
	if t.is_empty():
		return "world"

	var out: String = ""
	for i in t.length():
		var ch: String = t.substr(i, 1)
		var ok: bool = false
		if ch >= "a" and ch <= "z":
			ok = true
		elif ch >= "0" and ch <= "9":
			ok = true
		elif ch == "_" or ch == "-":
			ok = true
		elif ch == " ":
			ch = "_"
			ok = true
		if ok:
			out += ch

	while out.find("__") != -1:
		out = out.replace("__", "_")

	while out.begins_with("_") or out.begins_with("-"):
		out = out.substr(1, out.length() - 1)
	while out.ends_with("_") or out.ends_with("-"):
		out = out.substr(0, out.length() - 1)

	if out.is_empty():
		out = "world"
	return out

func _random_seed() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(-2147483647, 2147483647)

func _remove_dir_recursive(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return OK

	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		var full: String = path.path_join(entry_name)
		if dir.current_is_dir():
			var err_child: int = _remove_dir_recursive(full)
			if err_child != OK:
				dir.list_dir_end()
				return err_child
		else:
			var err_rm: int = DirAccess.remove_absolute(full)
			if err_rm != OK:
				dir.list_dir_end()
				return err_rm
	dir.list_dir_end()

	return DirAccess.remove_absolute(path)

func _copy_dir_recursive(src: String, dst: String) -> int:
	if not DirAccess.dir_exists_absolute(src):
		return ERR_DOES_NOT_EXIST

	var mk: int = DirAccess.make_dir_recursive_absolute(dst)
	if mk != OK:
		return mk

	var dir: DirAccess = DirAccess.open(src)
	if dir == null:
		return ERR_CANT_OPEN

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		var src_path: String = src.path_join(entry_name)
		var dst_path: String = dst.path_join(entry_name)
		if dir.current_is_dir():
			var err_sub: int = _copy_dir_recursive(src_path, dst_path)
			if err_sub != OK:
				dir.list_dir_end()
				return err_sub
		else:
			var err_file: int = _copy_file(src_path, dst_path)
			if err_file != OK:
				dir.list_dir_end()
				return err_file
	dir.list_dir_end()

	return OK

func _copy_file(src_path: String, dst_path: String) -> int:
	if not FileAccess.file_exists(src_path):
		return ERR_DOES_NOT_EXIST
	var data: PackedByteArray = FileAccess.get_file_as_bytes(src_path)
	var f: FileAccess = FileAccess.open(dst_path, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_OPEN
	f.store_buffer(data)
	f.flush()
	f.close()
	return OK
