class_name AuthFile
extends RefCounted

# Default path the launcher should write to (Godot user data dir).
const DEFAULT_AUTH_PATH: String = "user://cc_auth.json"

var path: String = DEFAULT_AUTH_PATH
var data: Dictionary = {}

static func load_from(p_path: String) -> AuthFile:
	var af := AuthFile.new()
	af.path = p_path
	af._load()
	return af

func exists() -> bool:
	return FileAccess.file_exists(path)

func _load() -> void:
	data = {}
	if not FileAccess.file_exists(path):
		return

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return

	var txt: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		data = parsed as Dictionary
	else:
		data = {}

func is_valid_shape() -> Dictionary:
	# Shape check only (signature verification happens on server).
	var required: Array[String] = ["version", "username", "uuid", "issued_at", "nonce", "signature"]
	for k: String in required:
		if not data.has(k):
			return {"ok": false, "reason": "missing_%s" % k}
	return {"ok": true, "reason": ""}

func to_rpc_payload() -> Dictionary:
	# Only send what server needs.
	return {
		"version": int(data.get("version", 0)),
		"username": str(data.get("username", "")),
		"uuid": str(data.get("uuid", "")),
		"issued_at": int(data.get("issued_at", 0)),
		"nonce": str(data.get("nonce", "")),
		"signature": str(data.get("signature", "")),
	}
