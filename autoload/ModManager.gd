extends Node

# Mod folder layout:
# user://mods/<mod_id>/mod.json
# user://mods/<mod_id>/content/(blocks|items|recipes)/*.tres
#
# Enabled list is stored in:
# user://mods/enabled_mods.json  -> { "enabled": ["mod_a","mod_b"] }

const MOD_MANIFEST_FILE: String = "mod.json"

var _enabled_ids: PackedStringArray = PackedStringArray()
var _loaded_enabled_list: bool = false

func _ready() -> void:
	Paths.ensure_dirs()
	_load_enabled_list()

func list_mods() -> Array[Dictionary]:
	Paths.ensure_dirs()
	_load_enabled_list()

	var result: Array[Dictionary] = []
	var root: String = Paths.mods_dir()
	if not DirAccess.dir_exists_absolute(root):
		return result

	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		push_error("ModManager: Cannot open mods dir: %s" % root)
		return result

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue
		if not dir.current_is_dir():
			continue

		var mod_id: String = entry_name
		var mod_root: String = root.path_join(mod_id)
		var manifest_path: String = mod_root.path_join(MOD_MANIFEST_FILE)

		var meta: Dictionary = {}
		if FileAccess.file_exists(manifest_path):
			meta = _read_json_dict(manifest_path)

		if meta.is_empty():
			meta = {
				"id": mod_id,
				"name": mod_id,
				"version": "0.0.0",
				"author": "",
				"description": ""
			}

		var has_content: bool = DirAccess.dir_exists_absolute(mod_root.path_join("content"))
		var enabled: bool = is_mod_enabled(mod_id)

		meta["id"] = str(meta.get("id", mod_id))
		meta["path"] = mod_root
		meta["enabled"] = enabled
		meta["has_content"] = has_content

		result.append(meta)

	dir.list_dir_end()

	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ae: bool = bool(a.get("enabled", false))
		var be: bool = bool(b.get("enabled", false))
		if ae != be:
			return ae and not be
		var an: String = str(a.get("name", ""))
		var bn: String = str(b.get("name", ""))
		return an.nocasecmp_to(bn) < 0
	)

	return result

func get_enabled_mod_ids() -> PackedStringArray:
	_load_enabled_list()
	return _enabled_ids.duplicate()

func is_mod_enabled(mod_id: String) -> bool:
	_load_enabled_list()
	for e in _enabled_ids:
		if e == mod_id:
			return true
	return false

func set_mod_enabled(mod_id: String, enabled: bool) -> void:
	Paths.ensure_dirs()
	_load_enabled_list()

	var new_list: PackedStringArray = PackedStringArray()
	var already: bool = false

	for e in _enabled_ids:
		if e == mod_id:
			already = true
			if enabled:
				new_list.append(e)
		else:
			new_list.append(e)

	if enabled and not already:
		new_list.append(mod_id)

	_enabled_ids = new_list
	_save_enabled_list()

func create_mod(mod_id: String, display_name: String, enable_now: bool = true) -> String:
	Paths.ensure_dirs()
	_load_enabled_list()

	var safe_id: String = _fs_safe(mod_id)
	if safe_id.is_empty():
		safe_id = "new_mod"

	var root: String = Paths.mods_dir().path_join(safe_id)
	if DirAccess.dir_exists_absolute(root):
		push_error("ModManager: Mod folder already exists: %s" % root)
		return ""

	var err: int = DirAccess.make_dir_recursive_absolute(root)
	if err != OK:
		push_error("ModManager: Failed to create mod root: %s (err=%d)" % [root, err])
		return ""

	DirAccess.make_dir_recursive_absolute(root.path_join("content/blocks"))
	DirAccess.make_dir_recursive_absolute(root.path_join("content/items"))
	DirAccess.make_dir_recursive_absolute(root.path_join("content/recipes"))

	var name_val: String = display_name.strip_edges()
	if name_val.is_empty():
		name_val = safe_id

	var manifest: Dictionary = {
		"id": safe_id,
		"name": name_val,
		"version": "1.0.0",
		"author": "",
		"description": ""
	}
	_write_json_dict(root.path_join(MOD_MANIFEST_FILE), manifest)

	if enable_now:
		set_mod_enabled(safe_id, true)

	return safe_id

func reload_enabled_list() -> void:
	_loaded_enabled_list = false
	_enabled_ids = PackedStringArray()
	_load_enabled_list()

# -------------------------
# Internals
# -------------------------

func _load_enabled_list() -> void:
	if _loaded_enabled_list:
		return
	_loaded_enabled_list = true

	var path: String = Paths.enabled_mods_path()
	if not FileAccess.file_exists(path):
		_enabled_ids = PackedStringArray()
		return

	var data: Dictionary = _read_json_dict(path)
	var arr_v: Variant = data.get("enabled", [])
	if arr_v is Array:
		var arr: Array = arr_v as Array
		var out: PackedStringArray = PackedStringArray()
		for v in arr:
			var s: String = str(v).strip_edges()
			if not s.is_empty():
				out.append(s)
		_enabled_ids = out
	else:
		_enabled_ids = PackedStringArray()

func _save_enabled_list() -> void:
	var path: String = Paths.enabled_mods_path()
	var arr: Array = []
	for e in _enabled_ids:
		arr.append(e)
	_write_json_dict(path, {"enabled": arr})

func _read_json_dict(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("ModManager: JSON parse failed or not an object: %s" % path)
		return {}
	return parsed as Dictionary

func _write_json_dict(path: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ModManager: Failed to open for write: %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()

func _fs_safe(s: String) -> String:
	var t: String = s.strip_edges().to_lower()
	if t.is_empty():
		return ""

	var out: String = ""
	for i in t.length():
		var ch: String = t.substr(i, 1)
		var ok: bool = false
		if ch >= "a" and ch <= "z":
			ok = true
		elif ch >= "0" and ch <= "9":
			ok = true
		elif ch == "_" or ch == "-" or ch == ".":
			ok = true
		if ok:
			out += ch

	while out.find("..") != -1:
		out = out.replace("..", ".")
	while out.find("__") != -1:
		out = out.replace("__", "_")

	while out.begins_with(".") or out.begins_with("_") or out.begins_with("-"):
		out = out.substr(1, out.length() - 1)
	while out.ends_with(".") or out.ends_with("_") or out.ends_with("-"):
		out = out.substr(0, out.length() - 1)

	return out
