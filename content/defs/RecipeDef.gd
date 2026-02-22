extends Resource
class_name RecipeDef

# Types: "shapeless", "furnace"
@export var id: String = "core:recipe"
@export var recipe_type: String = "shapeless"

# Each entry: {"item_id": String, "count": int}
@export var inputs: Array[Dictionary] = []
@export var outputs: Array[Dictionary] = []

# Furnace-only extras
@export var cook_time_sec: float = 5.0
@export var xp: float = 0.0

func validate() -> String:
	if not _is_valid_content_id(id):
		return "RecipeDef has invalid id='%s' (expected 'namespace:name' lowercase a-z0-9_-. only)" % id

	var rt: String = recipe_type.strip_edges().to_lower()
	if rt != "shapeless" and rt != "furnace":
		return "RecipeDef %s has invalid recipe_type=%s" % [id, recipe_type]

	if inputs.is_empty():
		return "RecipeDef %s has no inputs" % id
	if outputs.is_empty():
		return "RecipeDef %s has no outputs" % id

	for e in inputs:
		var err: String = _validate_entry(e, "inputs")
		if not err.is_empty():
			return "RecipeDef %s %s" % [id, err]

	for e2 in outputs:
		var err2: String = _validate_entry(e2, "outputs")
		if not err2.is_empty():
			return "RecipeDef %s %s" % [id, err2]

	if rt == "furnace":
		if cook_time_sec <= 0.0:
			return "RecipeDef %s cook_time_sec must be > 0" % id

	return ""

func _validate_entry(entry: Dictionary, field_name: String) -> String:
	if not entry.has("item_id"):
		return "%s entry missing item_id" % field_name
	if not entry.has("count"):
		return "%s entry missing count" % field_name

	var item_id_val: String = str(entry.get("item_id", ""))
	if not _is_valid_content_id(item_id_val):
		return "%s entry has invalid item_id='%s'" % [field_name, item_id_val]

	var c: int = int(entry.get("count", 0))
	if c <= 0:
		return "%s entry has invalid count=%d" % [field_name, c]

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
