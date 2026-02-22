extends Control
class_name MainMenu

@export var world_list_ui_path: NodePath
@export var world_create_ui_path: NodePath

const GAME_SCENE_PATH: String = "res://game/Game.tscn"

var _list_ui: WorldListUI
var _create_ui: WorldCreateUI
var _game_ui: Control = null

func _ready() -> void:
	_list_ui = _get_list_ui(world_list_ui_path, "WorldListUI")
	_create_ui = _get_create_ui(world_create_ui_path, "WorldCreateUI")

	_connect_signals()
	_show_list()

func _connect_signals() -> void:
	if _list_ui != null:
		_list_ui.request_play_world.connect(_on_request_play_world)
		_list_ui.request_create_world.connect(_on_request_create_world)
		_list_ui.request_rename_world.connect(_on_request_rename_world)
		_list_ui.request_duplicate_world.connect(_on_request_duplicate_world)

	if _create_ui != null:
		_create_ui.created_world.connect(_on_created_world)
		_create_ui.canceled.connect(_on_create_canceled)

func _show_list() -> void:
	if _list_ui != null:
		_list_ui.visible = true
		_list_ui.refresh_worlds()
	if _create_ui != null:
		_create_ui.visible = false
	if _game_ui != null:
		_game_ui.visible = false

func _show_create() -> void:
	if _list_ui != null:
		_list_ui.visible = false
	if _create_ui != null:
		_create_ui.visible = true
	if _game_ui != null:
		_game_ui.visible = false

func _show_game() -> void:
	if _list_ui != null:
		_list_ui.visible = false
	if _create_ui != null:
		_create_ui.visible = false
	if _game_ui != null:
		_game_ui.visible = true

func _on_request_create_world() -> void:
	_show_create()

func _on_create_canceled() -> void:
	_show_list()

func _on_created_world(_world_id: String) -> void:
	_show_list()

func _on_request_rename_world(world_id: String, current_name: String) -> void:
	var new_world_name: String = "%s (Renamed)" % current_name
	WorldManager.rename_world(world_id, new_world_name)
	if _list_ui != null:
		_list_ui.refresh_worlds()

func _on_request_duplicate_world(world_id: String, current_name: String) -> void:
	var duplicate_name: String = "%s (Copy)" % current_name
	var new_id: String = WorldManager.duplicate_world(world_id, duplicate_name)
	if new_id.is_empty():
		push_error("MainMenu: Duplicate failed for world_id=%s" % world_id)
	if _list_ui != null:
		_list_ui.refresh_worlds()

func _on_request_play_world(world_id: String) -> void:
	var meta: Dictionary = WorldManager.load_world(world_id)
	if meta.is_empty():
		push_error("MainMenu: Failed to load world meta for world_id=%s" % world_id)
		return

	_ensure_game_ui()
	if _game_ui == null:
		push_error("MainMenu: Game scene failed to instantiate.")
		return

	_show_game()

	if _game_ui.has_method("start_world"):
		_game_ui.call("start_world", meta)
	else:
		push_error("MainMenu: Game UI missing start_world(meta) method.")

func _ensure_game_ui() -> void:
	if _game_ui != null:
		return

	var ps: PackedScene = load(GAME_SCENE_PATH) as PackedScene
	if ps == null:
		push_error("MainMenu: Cannot load %s" % GAME_SCENE_PATH)
		return

	var inst: Node = ps.instantiate()
	var c: Control = inst as Control
	if c == null:
		push_error("MainMenu: Game.tscn root must be a Control.")
		return

	_game_ui = c
	add_child(_game_ui)

	if _game_ui.has_signal("request_exit_to_menu"):
		_game_ui.connect("request_exit_to_menu", Callable(self, "_on_game_exit"))

func _on_game_exit() -> void:
	if _game_ui != null and _game_ui.has_method("stop_world"):
		_game_ui.call("stop_world")
	_show_list()

func _get_list_ui(path: NodePath, fallback_name: String) -> WorldListUI:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var ui: WorldListUI = node as WorldListUI
	if ui == null:
		push_error("MainMenu: Missing WorldListUI node '%s'." % fallback_name)
	return ui

func _get_create_ui(path: NodePath, fallback_name: String) -> WorldCreateUI:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var ui: WorldCreateUI = node as WorldCreateUI
	if ui == null:
		push_error("MainMenu: Missing WorldCreateUI node '%s'." % fallback_name)
	return ui
