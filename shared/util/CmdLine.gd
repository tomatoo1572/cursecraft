class_name CmdLine
extends RefCounted

static func parse(args: PackedStringArray = OS.get_cmdline_args()) -> Dictionary:
	var out: Dictionary = {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val := ""
			var eq := key.find("=")
			if eq != -1:
				val = key.substr(eq + 1)
				key = key.substr(0, eq)
			else:
				if i + 1 < args.size() and not args[i + 1].begins_with("-"):
					val = args[i + 1]
					i += 1
				else:
					val = "true"
			out[key] = val
		i += 1
	return out

static func get_str(m: Dictionary, key: String, default_value: String = "") -> String:
	if not m.has(key):
		return default_value
	return str(m[key])

static func get_int(m: Dictionary, key: String, default_value: int = 0) -> int:
	if not m.has(key):
		return default_value
	return int(m[key])

static func get_bool(m: Dictionary, key: String, default_value: bool = false) -> bool:
	if not m.has(key):
		return default_value
	var v := str(m[key]).strip_edges().to_lower()
	return v in ["1", "true", "yes", "y", "on"]
