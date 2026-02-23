class_name Network
extends Node

signal connection_state_changed(state: String)
signal auth_state_changed(state: String, reason: String)
signal player_list_changed(players: Array) # Array[Dictionary]

# World authority (Minecraft-style)
signal server_world_changed(world_id: String)

# Movement sync + chat
signal player_state_changed(peer_id: int, pos: Vector3, yaw: float)
signal chat_message(from_peer_id: int, from_name: String, text: String)

# ---------- Config ----------
const DEFAULT_PORT: int = 24500
const DEFAULT_MAX_CLIENTS: int = 64

const AUTH_SECRET_ENV: String = "CURSECRAFT_AUTH_SECRET"
const SERVER_SECRET_FALLBACK_PATH: String = "user://server_secret.txt"

const AUTH_TIMEOUT_SEC: float = 10.0
const TOKEN_MAX_AGE_SEC: int = 60 * 60 * 24
const ALLOW_INSECURE_DEV_IF_NO_SECRET: bool = true

# Proximity chat
const CHAT_RANGE: float = 32.0
const CHAT_MAX_LEN: int = 200

# ---------- State ----------
var is_server: bool = false
var connected: bool = false

var _pending_auth: Dictionary = {}   # peer_id -> start_time_sec (float)
var _players: Dictionary = {}        # peer_id -> {peer_id, username, uuid}
var _player_states: Dictionary = {}  # peer_id -> {pos:Vector3, yaw:float}
var _used_nonces: Dictionary = {}    # uuid -> {nonce: issued_at}

var _auth_file_path: String = AuthFile.DEFAULT_AUTH_PATH
var _server_world_id: String = ""

func _ready() -> void:
	set_process(true)
	_bind_tree_signals()

func _process(_dt: float) -> void:
	if is_server:
		_tick_auth_timeouts()

# ---------------- Public API ----------------

func set_auth_file_path(p: String) -> void:
	_auth_file_path = p

func is_multiplayer_active() -> bool:
	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer == null:
		return false
	return mp_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func get_local_peer_id() -> int:
	if not is_multiplayer_active():
		return 0
	return multiplayer.get_unique_id()

func get_players() -> Array:
	var arr: Array = []
	for k: Variant in _players.keys():
		arr.append(_players[k])
	return arr

func get_server_world_id() -> String:
	return _server_world_id

# Minecraft-style: server owns the world id
func server_set_world(world_id: String) -> void:
	if not multiplayer.is_server():
		return
	_server_world_id = world_id
	emit_signal("server_world_changed", _server_world_id)
	if is_multiplayer_active():
		rpc("server_world_update", _server_world_id)

func start_server(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> bool:
	_reset_net()
	is_server = true
	_get_server_secret()

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_clients)
	if err != OK:
		push_error("[Network] Failed to create server: %s" % err)
		is_server = false
		return false

	multiplayer.multiplayer_peer = peer
	emit_signal("connection_state_changed", "server_started")
	print("[Network] Server listening on port %d" % port)
	return true

func connect_to_server(host: String, port: int = DEFAULT_PORT) -> bool:
	_reset_net()
	is_server = false

	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(host, port)
	if err != OK:
		push_error("[Network] Failed to create client: %s" % err)
		return false

	multiplayer.multiplayer_peer = peer
	emit_signal("connection_state_changed", "connecting")
	print("[Network] Connecting to %s:%d" % [host, port])
	return true

func shutdown() -> void:
	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer != null:
		mp_peer.close()
	multiplayer.multiplayer_peer = null
	_reset_state_only()
	emit_signal("connection_state_changed", "disconnected")

# Host (listen-server) registers itself as a player
func register_local_player_from_auth_file() -> Dictionary:
	var af: AuthFile = AuthFile.load_from(_auth_file_path)
	if not af.exists():
		return {"ok": false, "reason": "auth_file_missing"}

	var shape: Dictionary = af.is_valid_shape()
	if not bool(shape.get("ok", false)):
		return {"ok": false, "reason": str(shape.get("reason", "bad_auth_file"))}

	var payload: Dictionary = af.to_rpc_payload()
	var username: String = str(payload.get("username", "")).strip_edges()
	var uuid: String = str(payload.get("uuid", "")).strip_edges()
	if username.is_empty() or uuid.is_empty():
		return {"ok": false, "reason": "bad_local_identity"}

	var local_id: int = get_local_peer_id()
	if local_id == 0:
		return {"ok": false, "reason": "no_multiplayer_peer"}

	_players[local_id] = {"peer_id": local_id, "username": username, "uuid": uuid}
	_broadcast_player_list()
	return {"ok": true, "reason": ""}

# ---------------- Movement Sync ----------------
func submit_local_state(pos: Vector3, yaw: float) -> void:
	if not is_multiplayer_active():
		return

	var local_id: int = get_local_peer_id()
	if local_id == 0:
		return

	if multiplayer.is_server():
		_server_accept_state(local_id, pos, yaw, true)
	else:
		if _peer_exists(1):
			rpc_id(1, "state_submit", pos, yaw)

# ---------------- Proximity Chat ----------------
func send_chat(text: String) -> void:
	var msg: String = text.strip_edges()
	if msg.is_empty():
		return
	if msg.length() > CHAT_MAX_LEN:
		msg = msg.substr(0, CHAT_MAX_LEN)

	if not is_multiplayer_active():
		emit_signal("chat_message", 0, "Local", msg)
		return

	var local_id: int = get_local_peer_id()
	var from_name: String = "Player"
	if _players.has(local_id):
		from_name = str((_players[local_id] as Dictionary).get("username", "Player"))

	if multiplayer.is_server():
		_server_chat_submit(local_id, from_name, msg)
	else:
		if _peer_exists(1):
			rpc_id(1, "chat_submit", msg)

# ---------------- Internal ----------------

func _reset_state_only() -> void:
	connected = false
	_pending_auth.clear()
	_players.clear()
	_player_states.clear()
	_server_world_id = ""

func _reset_net() -> void:
	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer != null:
		mp_peer.close()
	multiplayer.multiplayer_peer = null
	_reset_state_only()

func _bind_tree_signals() -> void:
	var mp: MultiplayerAPI = multiplayer

	var c_peer_connected: Callable = Callable(self, "_on_peer_connected")
	var c_peer_disconnected: Callable = Callable(self, "_on_peer_disconnected")
	var c_connected: Callable = Callable(self, "_on_connected_to_server")
	var c_failed: Callable = Callable(self, "_on_connection_failed")
	var c_srv_disc: Callable = Callable(self, "_on_server_disconnected")

	if not mp.peer_connected.is_connected(c_peer_connected):
		mp.peer_connected.connect(c_peer_connected)
	if not mp.peer_disconnected.is_connected(c_peer_disconnected):
		mp.peer_disconnected.connect(c_peer_disconnected)
	if not mp.connected_to_server.is_connected(c_connected):
		mp.connected_to_server.connect(c_connected)
	if not mp.connection_failed.is_connected(c_failed):
		mp.connection_failed.connect(c_failed)
	if not mp.server_disconnected.is_connected(c_srv_disc):
		mp.server_disconnected.connect(c_srv_disc)

func _on_connected_to_server() -> void:
	connected = true
	emit_signal("connection_state_changed", "connected")
	emit_signal("auth_state_changed", "auth_pending", "")
	_submit_auth_from_file()

func _on_connection_failed() -> void:
	connected = false
	emit_signal("connection_state_changed", "connection_failed")
	emit_signal("auth_state_changed", "auth_failed", "connection_failed")

func _on_server_disconnected() -> void:
	connected = false
	emit_signal("connection_state_changed", "server_disconnected")
	emit_signal("auth_state_changed", "auth_failed", "server_disconnected")
	_players.clear()
	_player_states.clear()
	_server_world_id = ""
	emit_signal("player_list_changed", get_players())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_pending_auth[peer_id] = float(Time.get_ticks_msec()) / 1000.0

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_pending_auth.erase(peer_id)
		_players.erase(peer_id)
		_player_states.erase(peer_id)
		_broadcast_player_list()

func _tick_auth_timeouts() -> void:
	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	var to_kick: Array[int] = []

	for k: Variant in _pending_auth.keys():
		var peer_id: int = int(k)
		var t0: float = float(_pending_auth.get(peer_id, 0.0))
		if now_s - t0 > AUTH_TIMEOUT_SEC:
			to_kick.append(peer_id)

	for pid: int in to_kick:
		_kick_peer(pid, "auth_timeout")

func _peer_exists(peer_id: int) -> bool:
	if not is_multiplayer_active():
		return false
	if peer_id == multiplayer.get_unique_id():
		return true
	var peers: PackedInt32Array = multiplayer.get_peers() # Godot 4.6 valid
	return peers.has(peer_id)

func _kick_peer(peer_id: int, reason: String) -> void:
	if _peer_exists(peer_id):
		rpc_id(peer_id, "kick", reason)

	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer != null and mp_peer.has_method("disconnect_peer") and _peer_exists(peer_id):
		mp_peer.disconnect_peer(peer_id, true)

	_pending_auth.erase(peer_id)
	_players.erase(peer_id)
	_player_states.erase(peer_id)
	_broadcast_player_list()

func _broadcast_player_list() -> void:
	emit_signal("player_list_changed", get_players())
	if multiplayer.is_server() and is_multiplayer_active():
		rpc("player_list_update", get_players())

func _submit_auth_from_file() -> void:
	var af: AuthFile = AuthFile.load_from(_auth_file_path)

	if not af.exists():
		emit_signal("auth_state_changed", "auth_failed", "auth_file_missing")
		if _peer_exists(1):
			rpc_id(1, "auth_submit", {})
		return

	var shape: Dictionary = af.is_valid_shape()
	if not bool(shape.get("ok", false)):
		emit_signal("auth_state_changed", "auth_failed", str(shape.get("reason", "bad_auth_file")))
		if _peer_exists(1):
			rpc_id(1, "auth_submit", af.to_rpc_payload())
		return

	if _peer_exists(1):
		rpc_id(1, "auth_submit", af.to_rpc_payload())

func _get_server_secret() -> String:
	var env: String = OS.get_environment(AUTH_SECRET_ENV).strip_edges()
	if not env.is_empty():
		return env

	if FileAccess.file_exists(SERVER_SECRET_FALLBACK_PATH):
		var f: FileAccess = FileAccess.open(SERVER_SECRET_FALLBACK_PATH, FileAccess.READ)
		if f != null:
			var s: String = f.get_line().strip_edges()
			f.close()
			return s

	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	var secret: String = Marshalls.raw_to_base64(bytes)

	var wf: FileAccess = FileAccess.open(SERVER_SECRET_FALLBACK_PATH, FileAccess.WRITE)
	if wf != null:
		wf.store_line(secret)
		wf.close()

	return secret

func _nonce_seen_before(uuid: String, nonce: String) -> bool:
	if not _used_nonces.has(uuid):
		return false
	var m: Dictionary = (_used_nonces.get(uuid, {}) as Dictionary)
	return m.has(nonce)

func _remember_nonce(uuid: String, nonce: String, issued_at: int) -> void:
	var m: Dictionary = {}
	if _used_nonces.has(uuid):
		m = (_used_nonces.get(uuid, {}) as Dictionary)
	m[nonce] = issued_at
	_used_nonces[uuid] = m

# ---------------- RPC (World) ----------------

@rpc("authority", "reliable")
func server_world_update(world_id: String) -> void:
	_server_world_id = world_id
	emit_signal("server_world_changed", _server_world_id)

# ---------------- RPC (Auth) ----------------

@rpc("any_peer", "reliable")
func auth_submit(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _peer_exists(peer_id):
		return

	var now_unix: int = int(Time.get_unix_time_from_system())

	if typeof(payload) != TYPE_DICTIONARY or payload.is_empty():
		_kick_peer(peer_id, "missing_payload")
		return

	var username: String = str(payload.get("username", "")).strip_edges()
	var uuid: String = str(payload.get("uuid", "")).strip_edges()
	var nonce: String = str(payload.get("nonce", "")).strip_edges()
	var issued_at: int = int(payload.get("issued_at", 0))

	if username.is_empty() or uuid.is_empty() or nonce.is_empty() or issued_at <= 0:
		_kick_peer(peer_id, "bad_payload_fields")
		return

	if _nonce_seen_before(uuid, nonce):
		_kick_peer(peer_id, "replay_detected")
		return

	var secret: String = _get_server_secret()
	var secret_ok: bool = not secret.is_empty()

	if not secret_ok and not ALLOW_INSECURE_DEV_IF_NO_SECRET:
		_kick_peer(peer_id, "server_no_secret")
		return

	if secret_ok:
		var vr: Dictionary = AuthToken.verify_payload(payload, secret, now_unix, TOKEN_MAX_AGE_SEC)
		if not bool(vr.get("ok", false)):
			_kick_peer(peer_id, "auth_%s" % str(vr.get("reason", "failed")))
			return

	_remember_nonce(uuid, nonce, issued_at)

	_players[peer_id] = {"peer_id": peer_id, "username": username, "uuid": uuid}
	_pending_auth.erase(peer_id)

	rpc_id(peer_id, "auth_result", true, "", now_unix, get_players())
	_broadcast_player_list()

	# tell new client current world (if any)
	if not _server_world_id.is_empty():
		rpc_id(peer_id, "server_world_update", _server_world_id)

@rpc("authority", "reliable")
func auth_result(ok: bool, reason: String, _server_time_unix: int, players: Array) -> void:
	if ok:
		emit_signal("auth_state_changed", "auth_ok", "")
		_players.clear()
		for d: Variant in players:
			if d is Dictionary:
				var dd: Dictionary = d as Dictionary
				_players[int(dd.get("peer_id", 0))] = dd
		emit_signal("player_list_changed", get_players())
	else:
		emit_signal("auth_state_changed", "auth_failed", reason)
		shutdown()

@rpc("authority", "reliable")
func player_list_update(players: Array) -> void:
	_players.clear()
	for d: Variant in players:
		if d is Dictionary:
			var dd: Dictionary = d as Dictionary
			_players[int(dd.get("peer_id", 0))] = dd
	emit_signal("player_list_changed", get_players())

@rpc("authority", "reliable")
func kick(reason: String) -> void:
	emit_signal("auth_state_changed", "auth_failed", "kicked_%s" % reason)
	shutdown()

# ---------------- RPC (Movement) ----------------

func _server_accept_state(peer_id: int, pos: Vector3, yaw: float, broadcast: bool) -> void:
	_player_states[peer_id] = {"pos": pos, "yaw": yaw}
	emit_signal("player_state_changed", peer_id, pos, yaw)
	if broadcast and is_multiplayer_active():
		rpc("state_update", peer_id, pos, yaw)

@rpc("any_peer", "unreliable")
func state_submit(pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _players.has(peer_id):
		return
	_server_accept_state(peer_id, pos, yaw, true)

@rpc("authority", "unreliable")
func state_update(peer_id: int, pos: Vector3, yaw: float) -> void:
	_player_states[peer_id] = {"pos": pos, "yaw": yaw}
	emit_signal("player_state_changed", peer_id, pos, yaw)

# ---------------- RPC (Chat) ----------------

func _server_chat_submit(from_id: int, from_name: String, text: String) -> void:
	var has_pos: bool = _player_states.has(from_id)
	var from_pos: Vector3 = Vector3.ZERO
	if has_pos:
		var st: Dictionary = (_player_states[from_id] as Dictionary)
		from_pos = st.get("pos", Vector3.ZERO)

	for k: Variant in _players.keys():
		var to_id: int = int(k)
		if to_id == 0:
			continue

		if to_id != from_id and has_pos and _player_states.has(to_id):
			var st2: Dictionary = (_player_states[to_id] as Dictionary)
			var to_pos: Vector3 = st2.get("pos", Vector3.ZERO)
			if from_pos.distance_to(to_pos) > CHAT_RANGE:
				continue

		# deliver
		if to_id == get_local_peer_id() and multiplayer.is_server():
			chat_recv(from_id, from_name, text)
		elif _peer_exists(to_id):
			rpc_id(to_id, "chat_recv", from_id, from_name, text)

@rpc("any_peer", "reliable")
func chat_submit(text: String) -> void:
	if not multiplayer.is_server():
		return
	var from_id: int = multiplayer.get_remote_sender_id()
	if not _players.has(from_id):
		return
	var from_name: String = str((_players[from_id] as Dictionary).get("username", "Player"))
	var msg: String = text.strip_edges()
	if msg.is_empty():
		return
	if msg.length() > CHAT_MAX_LEN:
		msg = msg.substr(0, CHAT_MAX_LEN)
	_server_chat_submit(from_id, from_name, msg)

@rpc("authority", "reliable")
func chat_recv(from_peer_id: int, from_name: String, text: String) -> void:
	emit_signal("chat_message", from_peer_id, from_name, text)
