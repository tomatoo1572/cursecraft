extends Node

var _net: Network = null

var _layer: CanvasLayer
var _panel: PanelContainer
var _status: RichTextLabel
var _hostport: LineEdit
var _username: LineEdit
var _auth_path_label: Label

var _conn_state: String = "idle"
var _auth_state: String = "idle"
var _auth_reason: String = ""
var _players: Array = []

var _auth_path: String = ""

func _ready() -> void:
	_net = _resolve_network_singleton()
	if _net == null:
		push_error("[NetDebugOverlay] Could not find Network autoload at /root/Network or /root/network. Check Project Settings -> Autoload.")
		return

	# IMPORTANT: user:// is shared between multi-instances in the editor.
	# Use per-process auth file so instances don't overwrite each other.
	_auth_path = "user://cc_auth_%d.json" % int(OS.get_process_id())
	_net.set_auth_file_path(_auth_path)

	_build_ui()
	_bind_signals()
	_refresh()

func _resolve_network_singleton() -> Network:
	var root: Node = get_tree().root
	if root.has_node("Network"):
		return root.get_node("Network") as Network
	if root.has_node("network"):
		return root.get_node("network") as Network
	return null

func _unhandled_input(event: InputEvent) -> void:
	# Toggle overlay with F9
	if event is InputEventKey and event.pressed and not event.echo:
		var e := event as InputEventKey
		if e.keycode == KEY_F9:
			_layer.visible = not _layer.visible

func _bind_signals() -> void:
	if not _net.connection_state_changed.is_connected(Callable(self, "_on_conn")):
		_net.connection_state_changed.connect(Callable(self, "_on_conn"))
	if not _net.auth_state_changed.is_connected(Callable(self, "_on_auth")):
		_net.auth_state_changed.connect(Callable(self, "_on_auth"))
	if not _net.player_list_changed.is_connected(Callable(self, "_on_players")):
		_net.player_list_changed.connect(Callable(self, "_on_players"))

func _on_conn(state: String) -> void:
	_conn_state = state
	_refresh()

func _on_auth(state: String, reason: String) -> void:
	_auth_state = state
	_auth_reason = reason
	_refresh()

func _on_players(players: Array) -> void:
	_players = players
	_refresh()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 99
	add_child(_layer)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 12
	_panel.offset_top = 12
	_panel.offset_right = 520
	_panel.offset_bottom = 340
	_layer.add_child(_panel)

	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(500, 320)
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)

	var title := Label.new()
	title.text = "NET DEBUG (F9 to toggle)"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	_auth_path_label = Label.new()
	_auth_path_label.text = "Auth file: " + _auth_path
	root.add_child(_auth_path_label)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	root.add_child(row1)

	_hostport = LineEdit.new()
	_hostport.placeholder_text = "host:port"
	_hostport.text = "127.0.0.1:24500"
	_hostport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_hostport)

	var btn_host := Button.new()
	btn_host.text = "Host"
	btn_host.pressed.connect(Callable(self, "_ui_host"))
	row1.add_child(btn_host)

	var btn_join := Button.new()
	btn_join.text = "Join"
	btn_join.pressed.connect(Callable(self, "_ui_join"))
	row1.add_child(btn_join)

	var btn_leave := Button.new()
	btn_leave.text = "Leave"
	btn_leave.pressed.connect(Callable(self, "_ui_leave"))
	row1.add_child(btn_leave)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	root.add_child(row2)

	_username = LineEdit.new()
	_username.placeholder_text = "username for DEV auth file"
	_username.text = "Player_%d" % int(OS.get_process_id())
	_username.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_username)

	var btn_write := Button.new()
	btn_write.text = "DEV: Write Auth File"
	btn_write.pressed.connect(Callable(self, "_ui_write_auth"))
	row2.add_child(btn_write)

	_status = RichTextLabel.new()
	_status.fit_content = true
	_status.scroll_active = false
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_status)

	var hint := Label.new()
	hint.text = "Tip: Run 2 instances. Host in one, Join from the other."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(hint)

func _refresh() -> void:
	_status.clear()

	_status.append_text("[b]Connection:[/b] %s\n" % _conn_state)
	_status.append_text("[b]Auth:[/b] %s" % _auth_state)
	if not _auth_reason.is_empty():
		_status.append_text("  [color=orange](%s)[/color]" % _auth_reason)
	_status.append_text("\n")

	var mode_text: String = ("SERVER" if _net.is_server else "CLIENT/SINGLE")
	_status.append_text("[b]Mode:[/b] %s\n" % mode_text)

	_status.append_text("[b]Players:[/b] %d\n" % int(_players.size()))
	for p in _players:
		if p is Dictionary:
			var d := p as Dictionary
			var pid := int(d.get("peer_id", 0))
			var uname := str(d.get("username", ""))
			var uid := str(d.get("uuid", ""))
			_status.append_text(" - peer=%d  name=%s  uuid=%s\n" % [pid, uname, uid])

func _parse_hostport(s: String) -> Dictionary:
	var host := "127.0.0.1"
	var port := 24500
	var parts := s.strip_edges().split(":")
	if parts.size() >= 1 and not parts[0].is_empty():
		host = parts[0]
	if parts.size() >= 2:
		port = int(parts[1])
	return {"host": host, "port": port}

func _ui_host() -> void:
	# If no auth file yet, create it first (DEV convenience)
	if not FileAccess.file_exists(_auth_path):
		_ui_write_auth()

	var hp := _parse_hostport(_hostport.text)
	var ok: bool = _net.start_server(int(hp["port"]), Network.DEFAULT_MAX_CLIENTS)
	if not ok:
		_conn_state = "server_start_failed"
		_refresh()
		return

	# Register host as a player so rosters show Host + Clients
	var rr: Dictionary = _net.register_local_player_from_auth_file()
	if bool(rr.get("ok", false)):
		_auth_state = "host_registered"
		_auth_reason = ""
	else:
		_auth_state = "host_register_failed"
		_auth_reason = str(rr.get("reason", "unknown"))

	_refresh()

func _ui_join() -> void:
	var hp := _parse_hostport(_hostport.text)
	_net.connect_to_server(str(hp["host"]), int(hp["port"]))

func _ui_leave() -> void:
	_net.shutdown()

func _ui_write_auth() -> void:
	var uname := _username.text.strip_edges()
	if uname.is_empty():
		uname = "Player_%d" % int(OS.get_process_id())

	var secret := _get_secret_for_dev()
	if secret.is_empty():
		_auth_state = "auth_failed"
		_auth_reason = "no_secret"
		_refresh()
		return

	var payload: Dictionary = AuthToken.make_payload(uname, "", secret)

	var f: FileAccess = FileAccess.open(_auth_path, FileAccess.WRITE)
	if f == null:
		_auth_state = "auth_failed"
		_auth_reason = "cannot_write_auth_file"
		_refresh()
		return

	f.store_string(JSON.stringify(payload, "\t"))
	f.close()

	_auth_state = "auth_file_written"
	_auth_reason = ""
	_refresh()

func _get_secret_for_dev() -> String:
	var env: String = OS.get_environment(Network.AUTH_SECRET_ENV).strip_edges()
	if not env.is_empty():
		return env

	if FileAccess.file_exists(Network.SERVER_SECRET_FALLBACK_PATH):
		var f: FileAccess = FileAccess.open(Network.SERVER_SECRET_FALLBACK_PATH, FileAccess.READ)
		if f != null:
			var s: String = f.get_line().strip_edges()
			f.close()
			return s

	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	var secret: String = Marshalls.raw_to_base64(bytes)

	var wf: FileAccess = FileAccess.open(Network.SERVER_SECRET_FALLBACK_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_line(secret)
		wf.close()

	return secret
