extends Node

const WORLDS_DIR: String = "user://worlds"
const MODS_DIR: String = "user://mods"
const LOGS_DIR: String = "user://logs"

# Optional enabled-mod list path (used by ModManager if present)
const ENABLED_MODS_FILE: String = "user://mods/enabled_mods.json"

# Local player identity (used by PlayerStorage)
const PLAYER_UUID_FILE: String = "user://player_uuid.txt"

func _ready() -> void:
	ensure_dirs()

func ensure_dirs() -> void:
	_ensure_dir(WORLDS_DIR)
	_ensure_dir(MODS_DIR)
	_ensure_dir(LOGS_DIR)

func worlds_dir() -> String:
	return WORLDS_DIR

func mods_dir() -> String:
	return MODS_DIR

func logs_dir() -> String:
	return LOGS_DIR

func enabled_mods_path() -> String:
	return ENABLED_MODS_FILE

func player_uuid_path() -> String:
	return PLAYER_UUID_FILE

func world_dir(world_id: String) -> String:
	return WORLDS_DIR.path_join(world_id)

func world_meta_path(world_id: String) -> String:
	return world_dir(world_id).path_join("world.json")

func world_chunks_dir(world_id: String) -> String:
	return world_dir(world_id).path_join("chunks")

func world_players_dir(world_id: String) -> String:
	return world_dir(world_id).path_join("players")

func player_save_path(world_id: String, player_id: String) -> String:
	return world_players_dir(world_id).path_join("%s.json" % player_id)

func ensure_world_dir(world_id: String) -> void:
	_ensure_dir(world_dir(world_id))

func ensure_world_chunks_dir(world_id: String) -> void:
	_ensure_dir(world_chunks_dir(world_id))

func ensure_world_players_dir(world_id: String) -> void:
	_ensure_dir(world_players_dir(world_id))

func _ensure_dir(path: String) -> void:
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("Paths: Failed to ensure directory exists: %s (err=%d)" % [path, err])
