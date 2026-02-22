extends Control
class_name Game

signal request_exit_to_menu()

@export var title_label_path: NodePath
@export var output_richtext_path: NodePath
@export var input_line_path: NodePath
@export var run_button_path: NodePath
@export var save_button_path: NodePath
@export var exit_button_path: NodePath

var _title_label: Label
var _output: RichTextLabel
var _input: LineEdit
var _run_btn: Button
var _save_btn: Button
var _exit_btn: Button

var _session: WorldSession
var _player: PlayerSave
var _player_storage: PlayerStorage

func _ready() -> void:
	_title_label = _get_label(title_label_path, "TitleLabel")
	_output = _get_richtext(output_richtext_path, "Output")
	_input = _get_line_edit(input_line_path, "CommandInput")
	_run_btn = _get_button(run_button_path, "RunButton")
	_save_btn = _get_button(save_button_path, "SaveButton")
	_exit_btn = _get_button(exit_button_path, "ExitButton")

	if _run_btn != null:
		_run_btn.pressed.connect(_on_run_pressed)
	if _save_btn != null:
		_save_btn.pressed.connect(_on_save_pressed)
	if _exit_btn != null:
		_exit_btn.pressed.connect(_on_exit_pressed)

	if _input != null:
		_input.text_submitted.connect(_on_input_submitted)

	_player_storage = PlayerStorage.new()

	_log("Game: ready. Use /help")

func start_world(meta: Dictionary) -> void:
	_session = WorldSession.new(meta)

	var wid: String = str(meta.get("world_id", ""))
	var wname: String = str(meta.get("name", ""))
	var preset: String = str(meta.get("worldgen_preset", "default"))
	var mode: String = str(meta.get("game_mode", "survival"))
	var seed_i: int = int(meta.get("seed", 0))

	if _title_label != null:
		_title_label.text = "World: %s (%s) [%s]" % [wname, wid, mode]

	var spawn_arr: Array = _session.get_spawn_array()
	var spawn_pos: Vector3i = Vector3i(int(spawn_arr[0]), int(spawn_arr[1]), int(spawn_arr[2]))

	_player = _player_storage.load_or_create_player(wid, spawn_pos)

	_log("World loaded.")
	_log("seed=%d preset=%s spawn=%s" % [seed_i, preset, str(spawn_pos)])
	_log("player_id=%s name=%s pos=%s" % [_player.player_id, _player.display_name, str(_player.pos)])

	var created: int = _session.sim.preload_spawn_area([_player.pos.x, _player.pos.y, _player.pos.z], 1)
	_log("preload radius=1 created_chunks=%d chunks_dir=%s" % [created, Paths.world_chunks_dir(wid)])

func stop_world() -> void:
	_save_all()
	if _session != null:
		_session.sim.unload_all(false)
	_session = null
	_player = null

func _save_all() -> void:
	if _session == null:
		return
	var wid: String = _session.world_id
	if _player != null:
		_player_storage.save_player(wid, _player)
	var saved_chunks: int = _session.sim.save_dirty()
	_log("Saved: player=%s chunks=%d" % [wid, saved_chunks])

func _on_input_submitted(text: String) -> void:
	_execute_command(text)

func _on_run_pressed() -> void:
	if _input == null:
		return
	_execute_command(_input.text)

func _on_save_pressed() -> void:
	if _session == null:
		_log("No session.")
		return
	_save_all()

func _on_exit_pressed() -> void:
	stop_world()
	request_exit_to_menu.emit()

func _execute_command(text: String) -> void:
	var line: String = text.strip_edges()
	if _input != null:
		_input.text = ""

	if line.is_empty():
		return

	_log("> %s" % line)

	if _session == null or _player == null:
		_log("No session loaded.")
		return

	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty():
		return

	var cmd: String = parts[0].to_lower()

	if cmd == "/help":
		_log("Commands:")
		_log("/help")
		_log("/whoami")
		_log("/setname name")
		_log("/where")
		_log("/tp x y z")
		_log("/getblock x y z")
		_log("/setblock x y z namespace:block")
		_log("/give namespace:item count")
		_log("/inv")
		_log("/save")
		_log("/preload r   (r = chunk radius)")
		_log("/meta")
		return

	if cmd == "/whoami":
		_log("player_id=%s name=%s" % [_player.player_id, _player.display_name])
		return

	if cmd == "/setname":
		if parts.size() < 2:
			_log("Usage: /setname name")
			return
		var new_name: String = line.substr(9, line.length() - 9).strip_edges()
		if new_name.is_empty():
			_log("setname: name cannot be empty")
			return
		_player.display_name = new_name
		_log("name set to '%s'" % new_name)
		return

	if cmd == "/where":
		_log("pos=%s" % str(_player.pos))
		return

	if cmd == "/tp":
		if parts.size() != 4:
			_log("Usage: /tp x y z")
			return
		if not (parts[1].is_valid_int() and parts[2].is_valid_int() and parts[3].is_valid_int()):
			_log("tp: x y z must be ints")
			return
		_player.pos = Vector3i(int(parts[1]), int(parts[2]), int(parts[3]))
		_log("teleported pos=%s" % str(_player.pos))
		return

	if cmd == "/getblock":
		if parts.size() != 4:
			_log("Usage: /getblock x y z")
			return
		if not (parts[1].is_valid_int() and parts[2].is_valid_int() and parts[3].is_valid_int()):
			_log("getblock: x y z must be ints")
			return
		var x: int = int(parts[1])
		var y: int = int(parts[2])
		var z: int = int(parts[3])
		var bid: String = _session.sim.get_block_id_global(x, y, z)
		_log("block(%d,%d,%d)=%s" % [x, y, z, bid])
		return

	if cmd == "/setblock":
		if parts.size() != 5:
			_log("Usage: /setblock x y z namespace:block")
			return
		if not (parts[1].is_valid_int() and parts[2].is_valid_int() and parts[3].is_valid_int()):
			_log("setblock: x y z must be ints")
			return
		var x2: int = int(parts[1])
		var y2: int = int(parts[2])
		var z2: int = int(parts[3])
		var block_id: String = parts[4]
		_session.sim.set_block_id_global(x2, y2, z2, block_id)
		_log("setblock ok (%d,%d,%d)=%s (dirty)" % [x2, y2, z2, block_id])
		return

	if cmd == "/give":
		if parts.size() != 3:
			_log("Usage: /give namespace:item count")
			return
		var item_id: String = parts[1].strip_edges()
		if not parts[2].is_valid_int():
			_log("give: count must be int")
			return
		var amount: int = int(parts[2])
		if amount <= 0:
			_log("give: count must be > 0")
			return
		var added: int = _player.add_item(item_id, amount)
		_log("give: requested=%d added=%d item=%s" % [amount, added, item_id])
		return

	if cmd == "/inv":
		var lines: int = 0
		for i in _player.inventory.size():
			var s: Dictionary = _player.inventory[i]
			var iid: String = str(s.get("item_id", "core:air"))
			var cnt: int = int(s.get("count", 0))
			if cnt > 0 and iid != "core:air":
				_log("slot %02d: %s x%d" % [i, iid, cnt])
				lines += 1
		if lines == 0:
			_log("(inventory empty)")
		return

	if cmd == "/save":
		_save_all()
		return

	if cmd == "/preload":
		if parts.size() != 2 or not parts[1].is_valid_int():
			_log("Usage: /preload r")
			return
		var r: int = int(parts[1])
		if r < 0:
			r = 0
		if r > 8:
			r = 8
		var created2: int = _session.sim.preload_spawn_area([_player.pos.x, _player.pos.y, _player.pos.z], r)
		_log("preload radius=%d created_chunks=%d" % [r, created2])
		return

	if cmd == "/meta":
		_log(JSON.stringify(_session.meta, "\t"))
		return

	_log("Unknown command. Use /help")

func _log(s: String) -> void:
	print(s)
	if _output != null:
		_output.append_text(s + "\n")

func _get_label(path: NodePath, fallback_name: String) -> Label:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: Label = node as Label
	if v == null:
		push_error("Game: Missing Label '%s'." % fallback_name)
	return v

func _get_richtext(path: NodePath, fallback_name: String) -> RichTextLabel:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: RichTextLabel = node as RichTextLabel
	if v == null:
		push_error("Game: Missing RichTextLabel '%s'." % fallback_name)
	return v

func _get_line_edit(path: NodePath, fallback_name: String) -> LineEdit:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: LineEdit = node as LineEdit
	if v == null:
		push_error("Game: Missing LineEdit '%s'." % fallback_name)
	return v

func _get_button(path: NodePath, fallback_name: String) -> Button:
	var node: Node = null
	if not path.is_empty():
		node = get_node_or_null(path)
	if node == null:
		node = find_child(fallback_name, true, false)
	var v: Button = node as Button
	if v == null:
		push_error("Game: Missing Button '%s'." % fallback_name)
	return v
