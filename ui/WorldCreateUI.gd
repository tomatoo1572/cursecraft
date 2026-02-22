extends Control
class_name WorldCreateUI

signal created_world(world_id: String)
signal canceled()

@export var name_edit_path: NodePath
@export var seed_edit_path: NodePath
@export var mode_option_path: NodePath
@export var preset_option_path: NodePath
@export var create_button_path: NodePath
@export var back_button_path: NodePath

var _name_edit: LineEdit
var _seed_edit: LineEdit
var _mode_opt: OptionButton
var _preset_opt: OptionButton
var _create_btn: Button
var _back_btn: Button

func _ready() -> void:
	_name_edit = _get_line_edit(name_edit_path, "NameEdit")
	_seed_edit = _get_line_edit(seed_edit_path, "SeedEdit")
	_mode_opt = _get_option_button(mode_option_path, "ModeOption")
	_preset_opt = _get_option_button(preset_option_path, "PresetOption")
	_create_btn = _get_button(create_button_path, "CreateButton")
	_back_btn = _get_button(back_button_path, "BackButton")

	_setup_defaults()
	_connect_ui()

func _setup_defaults() -> void:
	if _name_edit != null and _name_edit.text.strip_edges().is_empty():
		_name_edit.text = "New World"

	if _seed_edit != null:
		_seed_edit.placeholder_text = "Leave blank for random"

	if _mode_opt != null and _mode_opt.item_count == 0:
		_mode_opt.add_item("Survival", 0)
		_mode_opt.add_item("Creative", 1)
		_mode_opt.select(0)

	if _preset_opt != null and _preset_opt.item_count == 0:
		_preset_opt.add_item("Default", 0)
		_preset_opt.add_item("Flat", 1)
		_preset_opt.select(0)

func _connect_ui() -> void:
	if _create_btn != null:
		_create_btn.pressed.connect(_on_create_pressed)
	if _back_btn != null:
		_back_btn.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	canceled.emit()

func _on_create_pressed() -> void:
	if _name_edit == null or _mode_opt == null or _preset_opt == null:
		push_error("WorldCreateUI: Missing required UI nodes.")
		return

	var world_name: String = _name_edit.text.strip_edges()
	if world_name.is_empty():
		world_name = "New World"

	var world_seed: int = 0
	if _seed_edit != null:
		var seed_text: String = _seed_edit.text.strip_edges()
		if not seed_text.is_empty():
			if seed_text.is_valid_int():
				world_seed = int(seed_text)
			elif seed_text.is_valid_float():
				world_seed = int(float(seed_text))
			else:
				world_seed = 0

	var mode: String = "survival"
	if _mode_opt.selected == 1:
		mode = "creative"

	var preset: String = "default"
	if _preset_opt.selected == 1:
		preset = "flat"

	var wid: String = WorldManager.create_world(world_name, world_seed, mode, preset)
	if wid.is_empty():
		push_error("WorldCreateUI: World creation failed.")
		return

	created_world.emit(wid)

func _get_line_edit(path: NodePath, fallback_name: String) -> LineEdit:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var le: LineEdit = node as LineEdit
	if le == null:
		push_error("WorldCreateUI: Missing LineEdit '%s'. Set exported NodePath or create node with that name." % fallback_name)
	return le

func _get_option_button(path: NodePath, fallback_name: String) -> OptionButton:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var ob: OptionButton = node as OptionButton
	if ob == null:
		push_error("WorldCreateUI: Missing OptionButton '%s'. Set exported NodePath or create node with that name." % fallback_name)
	return ob

func _get_button(path: NodePath, fallback_name: String) -> Button:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var btn: Button = node as Button
	if btn == null:
		push_error("WorldCreateUI: Missing Button '%s'. Set exported NodePath or create node with that name." % fallback_name)
	return btn
