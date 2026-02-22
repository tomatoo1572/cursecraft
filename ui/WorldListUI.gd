extends Control
class_name WorldListUI

signal request_play_world(world_id: String)
signal request_create_world()
signal request_rename_world(world_id: String, current_name: String)
signal request_refresh()
signal request_duplicate_world(world_id: String, current_name: String)

@export var worlds_list_path: NodePath
@export var play_button_path: NodePath
@export var create_button_path: NodePath
@export var rename_button_path: NodePath
@export var delete_button_path: NodePath
@export var duplicate_button_path: NodePath
@export var refresh_button_path: NodePath

var _worlds_list: ItemList
var _play_btn: Button
var _create_btn: Button
var _rename_btn: Button
var _delete_btn: Button
var _duplicate_btn: Button
var _refresh_btn: Button

var _index_to_world_id: Dictionary = {} # int -> String

func _ready() -> void:
	_worlds_list = _get_item_list(worlds_list_path, "WorldsList")
	_play_btn = _get_button(play_button_path, "PlayButton")
	_create_btn = _get_button(create_button_path, "CreateButton")
	_rename_btn = _get_button(rename_button_path, "RenameButton")
	_delete_btn = _get_button(delete_button_path, "DeleteButton")
	_duplicate_btn = _get_button(duplicate_button_path, "DuplicateButton")
	_refresh_btn = _get_button(refresh_button_path, "RefreshButton")

	_connect_ui()
	refresh_worlds()

func refresh_worlds() -> void:
	if _worlds_list == null:
		return

	_worlds_list.clear()
	_index_to_world_id.clear()

	var worlds: Array[Dictionary] = WorldManager.list_worlds()
	for w in worlds:
		var wid: String = str(w.get("world_id", ""))
		var world_name: String = str(w.get("name", ""))
		var mode: String = str(w.get("game_mode", "survival"))
		var lastp: String = str(w.get("last_played_utc", ""))
		var label: String = "%s  [%s]  (%s)" % [world_name, mode, lastp]
		var idx: int = _worlds_list.add_item(label)
		_index_to_world_id[idx] = wid

	_update_buttons_enabled()

func get_selected_world_id() -> String:
	if _worlds_list == null:
		return ""
	var sel: PackedInt32Array = _worlds_list.get_selected_items()
	if sel.is_empty():
		return ""
	var idx: int = int(sel[0])
	return str(_index_to_world_id.get(idx, ""))

func get_selected_world_name() -> String:
	if _worlds_list == null:
		return ""
	var sel: PackedInt32Array = _worlds_list.get_selected_items()
	if sel.is_empty():
		return ""
	var idx: int = int(sel[0])
	var text: String = _worlds_list.get_item_text(idx)
	var parts: PackedStringArray = text.split("  ", false, 1)
	if parts.size() >= 1:
		return parts[0]
	return text

func _connect_ui() -> void:
	if _worlds_list != null:
		_worlds_list.item_selected.connect(_on_item_selected)
		_worlds_list.item_activated.connect(_on_item_activated)

	if _play_btn != null:
		_play_btn.pressed.connect(_on_play_pressed)
	if _create_btn != null:
		_create_btn.pressed.connect(_on_create_pressed)
	if _rename_btn != null:
		_rename_btn.pressed.connect(_on_rename_pressed)
	if _delete_btn != null:
		_delete_btn.pressed.connect(_on_delete_pressed)
	if _duplicate_btn != null:
		_duplicate_btn.pressed.connect(_on_duplicate_pressed)
	if _refresh_btn != null:
		_refresh_btn.pressed.connect(_on_refresh_pressed)

func _on_item_selected(_index: int) -> void:
	_update_buttons_enabled()

func _on_item_activated(_index: int) -> void:
	_on_play_pressed()

func _on_play_pressed() -> void:
	var wid: String = get_selected_world_id()
	if wid.is_empty():
		push_warning("WorldListUI: No world selected.")
		return
	request_play_world.emit(wid)

func _on_create_pressed() -> void:
	request_create_world.emit()

func _on_rename_pressed() -> void:
	var wid: String = get_selected_world_id()
	if wid.is_empty():
		push_warning("WorldListUI: No world selected.")
		return
	request_rename_world.emit(wid, get_selected_world_name())

func _on_delete_pressed() -> void:
	var wid: String = get_selected_world_id()
	if wid.is_empty():
		push_warning("WorldListUI: No world selected.")
		return
	WorldManager.delete_world(wid)
	refresh_worlds()

func _on_duplicate_pressed() -> void:
	var wid: String = get_selected_world_id()
	if wid.is_empty():
		push_warning("WorldListUI: No world selected.")
		return
	request_duplicate_world.emit(wid, get_selected_world_name())

func _on_refresh_pressed() -> void:
	refresh_worlds()
	request_refresh.emit()

func _update_buttons_enabled() -> void:
	var has_sel: bool = not get_selected_world_id().is_empty()
	if _play_btn != null:
		_play_btn.disabled = not has_sel
	if _rename_btn != null:
		_rename_btn.disabled = not has_sel
	if _delete_btn != null:
		_delete_btn.disabled = not has_sel
	if _duplicate_btn != null:
		_duplicate_btn.disabled = not has_sel

func _get_item_list(path: NodePath, fallback_name: String) -> ItemList:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var list: ItemList = node as ItemList
	if list == null:
		push_error("WorldListUI: Missing ItemList. Set worlds_list_path or create node named '%s'." % fallback_name)
	return list

func _get_button(path: NodePath, fallback_name: String) -> Button:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var btn: Button = node as Button
	if btn == null:
		push_error("WorldListUI: Missing Button '%s'. Set exported NodePath or create node with that name." % fallback_name)
	return btn
