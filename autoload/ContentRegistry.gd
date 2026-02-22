extends Node

var blocks_by_id: Dictionary = {} # String -> BlockDef
var items_by_id: Dictionary = {} # String -> ItemDef
var recipes_by_id: Dictionary = {} # String -> RecipeDef

# Runtime numeric IDs (stable-per-run; deterministic order)
var block_runtime_id_by_string: Dictionary = {} # String -> int
var block_string_by_runtime_id: PackedStringArray = PackedStringArray()

var item_runtime_id_by_string: Dictionary = {} # String -> int
var item_string_by_runtime_id: PackedStringArray = PackedStringArray()

const RES_BLOCKS_DIR: String = "res://content/blocks"
const RES_ITEMS_DIR: String = "res://content/items"
const RES_RECIPES_DIR: String = "res://content/recipes"

const _MOD_MANAGER_ROOT: String = "/root/ModManager"

func _ready() -> void:
	Paths.ensure_dirs()
	reload_all()

func reload_all() -> void:
	blocks_by_id.clear()
	items_by_id.clear()
	recipes_by_id.clear()

	block_runtime_id_by_string.clear()
	block_string_by_runtime_id = PackedStringArray()
	item_runtime_id_by_string.clear()
	item_string_by_runtime_id = PackedStringArray()

	_load_from_dir(RES_BLOCKS_DIR, "block")
	_load_from_dir(RES_ITEMS_DIR, "item")
	_load_from_dir(RES_RECIPES_DIR, "recipe")

	_load_mods()

	_ensure_builtin_core_air()
	_validate_references()
	_build_runtime_maps()

	print("ContentRegistry: Loaded blocks=%d items=%d recipes=%d" % [
		blocks_by_id.size(),
		items_by_id.size(),
		recipes_by_id.size()
	])

func get_block(id: String) -> BlockDef:
	var v: Variant = blocks_by_id.get(id, null)
	if v == null:
		push_error("ContentRegistry: Missing BlockDef id=%s" % id)
		return null
	return v as BlockDef

func get_item(id: String) -> ItemDef:
	var v: Variant = items_by_id.get(id, null)
	if v == null:
		push_error("ContentRegistry: Missing ItemDef id=%s" % id)
		return null
	return v as ItemDef

func get_recipe(id: String) -> RecipeDef:
	var v: Variant = recipes_by_id.get(id, null)
	if v == null:
		push_error("ContentRegistry: Missing RecipeDef id=%s" % id)
		return null
	return v as RecipeDef

func has_block(id: String) -> bool:
	return blocks_by_id.has(id)

func has_item(id: String) -> bool:
	return items_by_id.has(id)

func has_recipe(id: String) -> bool:
	return recipes_by_id.has(id)

func get_all_block_ids() -> PackedStringArray:
	var keys: Array = blocks_by_id.keys()
	keys.sort()
	var out: PackedStringArray = PackedStringArray()
	for k in keys:
		out.append(str(k))
	return out

func get_all_item_ids() -> PackedStringArray:
	var keys: Array = items_by_id.keys()
	keys.sort()
	var out: PackedStringArray = PackedStringArray()
	for k in keys:
		out.append(str(k))
	return out

# -------------------------
# Runtime ID API
# -------------------------

func get_block_runtime_id(id: String) -> int:
	var v: Variant = block_runtime_id_by_string.get(id, null)
	if v == null:
		return 0 # default to core:air
	return int(v)

func get_block_id_from_runtime(runtime_id: int) -> String:
	if runtime_id < 0 or runtime_id >= block_string_by_runtime_id.size():
		return "core:air"
	return block_string_by_runtime_id[runtime_id]

func get_item_runtime_id(id: String) -> int:
	var v: Variant = item_runtime_id_by_string.get(id, null)
	if v == null:
		return 0 # default to core:air
	return int(v)

func get_item_id_from_runtime(runtime_id: int) -> String:
	if runtime_id < 0 or runtime_id >= item_string_by_runtime_id.size():
		return "core:air"
	return item_string_by_runtime_id[runtime_id]

# -------------------------
# Internals
# -------------------------

func _load_mods() -> void:
	var mods_root: String = Paths.mods_dir()
	if not DirAccess.dir_exists_absolute(mods_root):
		return

	# If ModManager exists and has enabled list, load enabled mods only.
	# Otherwise, load ALL mod folders.
	var enabled_ids: PackedStringArray = PackedStringArray()
	var mm: Node = get_node_or_null(_MOD_MANAGER_ROOT)
	if mm != null and mm.has_method("get_enabled_mod_ids"):
		var v: Variant = mm.call("get_enabled_mod_ids")
		if v is PackedStringArray:
			enabled_ids = v as PackedStringArray

	if enabled_ids.is_empty():
		_load_all_mod_folders(mods_root)
	else:
		for mod_id in enabled_ids:
			var mod_root: String = mods_root.path_join(mod_id)
			if not DirAccess.dir_exists_absolute(mod_root):
				push_warning("ContentRegistry: Enabled mod folder missing: %s" % mod_root)
				continue
			_load_mod_content(mod_root)

func _load_all_mod_folders(mods_root: String) -> void:
	var mods_dir: DirAccess = DirAccess.open(mods_root)
	if mods_dir == null:
		push_error("ContentRegistry: Cannot open mods dir: %s" % mods_root)
		return

	mods_dir.list_dir_begin()
	while true:
		var mod_folder: String = mods_dir.get_next()
		if mod_folder.is_empty():
			break
		if mod_folder == "." or mod_folder == "..":
			continue
		if not mods_dir.current_is_dir():
			continue
		_load_mod_content(mods_root.path_join(mod_folder))
	mods_dir.list_dir_end()

func _load_mod_content(mod_root: String) -> void:
	var content_root: String = mod_root.path_join("content")
	var blocks_path: String = content_root.path_join("blocks")
	var items_path: String = content_root.path_join("items")
	var recipes_path: String = content_root.path_join("recipes")

	if DirAccess.dir_exists_absolute(blocks_path):
		_load_from_dir(blocks_path, "block")
	if DirAccess.dir_exists_absolute(items_path):
		_load_from_dir(items_path, "item")
	if DirAccess.dir_exists_absolute(recipes_path):
		_load_from_dir(recipes_path, "recipe")

func _load_from_dir(dir_path: String, kind: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("ContentRegistry: Cannot open dir: %s" % dir_path)
		return

	dir.list_dir_begin()
	while true:
		var entry_name: String = dir.get_next()
		if entry_name.is_empty():
			break
		if entry_name == "." or entry_name == "..":
			continue

		var full: String = dir_path.path_join(entry_name)
		if dir.current_is_dir():
			_load_from_dir(full, kind)
			continue

		if not entry_name.ends_with(".tres"):
			continue

		var res: Resource = ResourceLoader.load(full)
		if res == null:
			push_error("ContentRegistry: Failed to load resource: %s" % full)
			continue

		if kind == "block":
			var b: BlockDef = res as BlockDef
			if b == null:
				push_error("ContentRegistry: Resource is not BlockDef: %s" % full)
				continue
			_register_block(b, full)
		elif kind == "item":
			var it: ItemDef = res as ItemDef
			if it == null:
				push_error("ContentRegistry: Resource is not ItemDef: %s" % full)
				continue
			_register_item(it, full)
		elif kind == "recipe":
			var rp: RecipeDef = res as RecipeDef
			if rp == null:
				push_error("ContentRegistry: Resource is not RecipeDef: %s" % full)
				continue
			_register_recipe(rp, full)

	dir.list_dir_end()

func _register_block(b: BlockDef, src_path: String) -> void:
	var err: String = b.validate()
	if not err.is_empty():
		push_error("ContentRegistry: Invalid BlockDef at %s: %s" % [src_path, err])
		return
	if blocks_by_id.has(b.id):
		push_error("ContentRegistry: Duplicate BlockDef id=%s (new=%s)" % [b.id, src_path])
		return
	blocks_by_id[b.id] = b

func _register_item(it: ItemDef, src_path: String) -> void:
	var err: String = it.validate()
	if not err.is_empty():
		push_error("ContentRegistry: Invalid ItemDef at %s: %s" % [src_path, err])
		return
	if items_by_id.has(it.id):
		push_error("ContentRegistry: Duplicate ItemDef id=%s (new=%s)" % [it.id, src_path])
		return
	items_by_id[it.id] = it

func _register_recipe(rp: RecipeDef, src_path: String) -> void:
	var err: String = rp.validate()
	if not err.is_empty():
		push_error("ContentRegistry: Invalid RecipeDef at %s: %s" % [src_path, err])
		return
	if recipes_by_id.has(rp.id):
		push_error("ContentRegistry: Duplicate RecipeDef id=%s (new=%s)" % [rp.id, src_path])
		return
	recipes_by_id[rp.id] = rp

func _ensure_builtin_core_air() -> void:
	# Always ensure core:air exists, even if you didn't make a .tres for it.
	if not blocks_by_id.has("core:air"):
		var air_block: BlockDef = BlockDef.new()
		air_block.id = "core:air"
		air_block.display_name = "Air"
		air_block.hardness = 0.0
		air_block.resistance = 0.0
		air_block.max_stack = 64
		air_block.is_solid = false
		air_block.is_transparent = true
		air_block.emits_light = 0
		air_block.requires_tool = false
		air_block.atlas_index = 0
		air_block.item_id = "core:air"
		air_block.tags = PackedStringArray(["builtin"])
		blocks_by_id["core:air"] = air_block

	if not items_by_id.has("core:air"):
		var air_item: ItemDef = ItemDef.new()
		air_item.id = "core:air"
		air_item.display_name = "Air"
		air_item.max_stack = 64
		air_item.is_placeable = false
		air_item.place_block_id = ""
		air_item.atlas_index = 0
		air_item.tags = PackedStringArray(["builtin"])
		items_by_id["core:air"] = air_item

func _build_runtime_maps() -> void:
	block_runtime_id_by_string.clear()
	block_string_by_runtime_id = PackedStringArray()
	item_runtime_id_by_string.clear()
	item_string_by_runtime_id = PackedStringArray()

	# Blocks: reserve 0 for core:air
	var block_keys: Array = blocks_by_id.keys()
	block_keys.sort()
	if block_keys.has("core:air"):
		block_keys.erase("core:air")
	block_keys.insert(0, "core:air")

	for i in block_keys.size():
		var id: String = str(block_keys[i])
		block_runtime_id_by_string[id] = i
		block_string_by_runtime_id.append(id)

	# Items: reserve 0 for core:air
	var item_keys: Array = items_by_id.keys()
	item_keys.sort()
	if item_keys.has("core:air"):
		item_keys.erase("core:air")
	item_keys.insert(0, "core:air")

	for j in item_keys.size():
		var iid: String = str(item_keys[j])
		item_runtime_id_by_string[iid] = j
		item_string_by_runtime_id.append(iid)

func _validate_references() -> void:
	# Block -> Item link check
	for v in blocks_by_id.values():
		var b: BlockDef = v as BlockDef
		if b == null:
			continue
		if b.item_id.is_empty() or b.item_id == "core:air":
			continue
		if not items_by_id.has(b.item_id):
			push_warning("ContentRegistry: Block '%s' references missing item_id '%s'" % [b.id, b.item_id])

	# Item -> Block placement check
	for v2 in items_by_id.values():
		var it: ItemDef = v2 as ItemDef
		if it == null:
			continue
		if it.is_placeable and not blocks_by_id.has(it.place_block_id):
			push_warning("ContentRegistry: Item '%s' place_block_id missing block '%s'" % [it.id, it.place_block_id])

	# Recipe IO check
	for v3 in recipes_by_id.values():
		var rp: RecipeDef = v3 as RecipeDef
		if rp == null:
			continue

		for e in rp.inputs:
			var item_id_val: String = str(e.get("item_id", ""))
			if not items_by_id.has(item_id_val):
				push_warning("ContentRegistry: Recipe '%s' input references missing item '%s'" % [rp.id, item_id_val])

		for e2 in rp.outputs:
			var item_id_val2: String = str(e2.get("item_id", ""))
			if not items_by_id.has(item_id_val2):
				push_warning("ContentRegistry: Recipe '%s' output references missing item '%s'" % [rp.id, item_id_val2])
