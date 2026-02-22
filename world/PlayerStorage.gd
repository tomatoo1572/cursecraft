extends RefCounted
class_name PlayerStorage

func ensure_player_uuid() -> String:
	Paths.ensure_dirs()

	var path: String = Paths.player_uuid_path()
	if FileAccess.file_exists(path):
		var s: String = FileAccess.get_file_as_string(path).strip_edges()
		if not s.is_empty():
			return s

	var uuid: String = _generate_uuid_v4()
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(uuid)
		f.flush()
		f.close()
	return uuid

func load_or_create_player(world_id: String, default_spawn: Vector3i) -> PlayerSave:
	Paths.ensure_world_players_dir(world_id)

	var pid: String = ensure_player_uuid()
	var path: String = Paths.player_save_path(world_id, pid)

	if FileAccess.file_exists(path):
		var d: Dictionary = _read_json_dict(path)
		if not d.is_empty():
			var p: PlayerSave = PlayerSave.from_dict(d)
			if p.player_id.strip_edges().is_empty():
				p.player_id = pid
			return p

	# Create new
	var pnew: PlayerSave = PlayerSave.new()
	pnew.player_id = pid
	pnew.display_name = "Player"
	pnew.pos = default_spawn
	var now: String = Time.get_datetime_string_from_system(true)
	pnew.created_utc = now
	pnew.last_saved_utc = now
	save_player(world_id, pnew)
	return pnew

func save_player(world_id: String, player: PlayerSave) -> bool:
	if player == null:
		return false

	Paths.ensure_world_players_dir(world_id)

	var pid: String = player.player_id.strip_edges()
	if pid.is_empty():
		pid = ensure_player_uuid()
		player.player_id = pid

	player.last_saved_utc = Time.get_datetime_string_from_system(true)
	if player.created_utc.strip_edges().is_empty():
		player.created_utc = player.last_saved_utc

	var path: String = Paths.player_save_path(world_id, pid)
	return _write_json_dict(path, player.to_dict(world_id))

func _read_json_dict(path: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("PlayerStorage: JSON parse failed or not an object: %s" % path)
		return {}
	return parsed as Dictionary

func _write_json_dict(path: String, data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("PlayerStorage: Failed to open for write: %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.flush()
	f.close()
	return true

func _generate_uuid_v4() -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var b: PackedByteArray = PackedByteArray()
	b.resize(16)
	for i in 16:
		b[i] = rng.randi_range(0, 255)

	# Version 4
	b[6] = (b[6] & 0x0F) | 0x40
	# Variant 10xxxxxx
	b[8] = (b[8] & 0x3F) | 0x80

	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3],
		b[4], b[5],
		b[6], b[7],
		b[8], b[9],
		b[10], b[11], b[12], b[13], b[14], b[15]
	]
