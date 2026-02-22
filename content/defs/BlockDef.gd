extends Resource
class_name BlockDef

@export var id: String = "core:air"
@export var display_name: String = "Air"

# Gameplay
@export var hardness: float = 0.0
@export var resistance: float = 0.0
@export var max_stack: int = 64
@export var is_solid: bool = false
@export var is_transparent: bool = true
@export var emits_light: int = 0 # 0..15
@export var requires_tool: bool = false

# Rendering-agnostic icon reference (atlas index)
@export var atlas_index: int = 0

# Optional drop / item link
@export var item_id: String = "core:air"

# Tags / flags
@export var tags: PackedStringArray = PackedStringArray()

func validate() -> String:
	if not _is_valid_content_id(id):
		return "BlockDef has invalid id='%s' (expected 'namespace:name' lowercase a-z0-9_-. only)" % id
	if display_name.strip_edges().is_empty():
		return "BlockDef %s display_name is empty" % id
	if max_stack <= 0:
		return "BlockDef %s has invalid max_stack=%d" % [id, max_stack]
	if emits_light < 0 or emits_light > 15:
		return "BlockDef %s emits_light out of range: %d" % [id, emits_light]
	if atlas_index < 0:
		return "BlockDef %s atlas_index must be >= 0" % id
	if not item_id.is_empty() and not _is_valid_content_id(item_id):
		return "BlockDef %s has invalid item_id='%s'" % [id, item_id]
	return ""

static func _is_valid_content_id(s: String) -> bool:
	var t: String = s.strip_edges()
	if t.is_empty():
		return false
	var parts: PackedStringArray = t.split(":", false)
	if parts.size() != 2:
		return false
	var ns: String = parts[0]
	var nm: String = parts[1]
	if ns.is_empty() or nm.is_empty():
		return false
	return _is_valid_id_part(ns) and _is_valid_id_part(nm)

static func _is_valid_id_part(p: String) -> bool:
	for i in p.length():
		var ch: String = p.substr(i, 1)
		var ok: bool = false
		if ch >= "a" and ch <= "z":
			ok = true
		elif ch >= "0" and ch <= "9":
			ok = true
		elif ch == "_" or ch == "-" or ch == ".":
			ok = true
		if not ok:
			return false
	return true
