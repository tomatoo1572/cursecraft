class_name Network
extends Node

signal connection_state_changed(state: String)
signal auth_state_changed(state: String, reason: String)
signal player_list_changed(players: Array) # Array[Dictionary]

# ---------- Config ----------
const DEFAULT_PORT: int = 24500
const DEFAULT_MAX_CLIENTS: int = 64

const AUTH_SECRET_ENV: String = "CURSECRAFT_AUTH_SECRET"
const SERVER_SECRET_FALLBACK_PATH: String = "user://server_secret.txt"

const AUTH_TIMEOUT_SEC: float = 10.0
const TOKEN_MAX_AGE_SEC: int = 60 * 60 * 24

# If true, server will accept payloads that *look* valid even if no secret is set (DEV ONLY).
const ALLOW_INSECURE_DEV_IF_NO_SECRET: bool = true

# ---------- State ----------
var is_server: bool = false
var connected: bool = false # avoid Object.is_connected collision

var _pending_auth: Dictionary = {} # peer_id -> start_time_sec (float)
var _players: Dictionary = {}      # peer_id -> Dictionary
var _used_nonces: Dictionary = {}  # uuid -> Dictionary[nonce -> issued_at]

var _auth_file_path: String = AuthFile.DEFAULT_AUTH_PATH

func _ready() -> void:
	set_process(true)
	_bind_tree_signals()

func _process(_dt: float) -> void:
	if is_server:
		_tick_auth_timeouts()

# ---------------- Public API ----------------

func set_auth_file_path(p: String) -> void:
	_auth_file_path = p

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

func start_server(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> bool:
	_reset_net()
	is_server = true

	# Ensure secret exists at server start (so DEV auth can be generated reliably)
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

# NOTE: Do NOT name this "disconnect" (collides with Object.disconnect)
func shutdown() -> void:
	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer != null:
		mp_peer.close()
	multiplayer.multiplayer_peer = null

	_reset_state_only()
	emit_signal("connection_state_changed", "disconnected")

func get_players() -> Array:
	var arr: Array = []
	for k: Variant in _players.keys():
		arr.append(_players[k])
	return arr

# NEW: Register the local host (listen-server style) from auth file
func register_local_player_from_auth_file() -> Dictionary:
	# This is intended for the HOST instance after start_server().
	# Dedicated servers can simply not call this.
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
	_players[local_id] = {"peer_id": local_id, "username": username, "uuid": uuid}
	_broadcast_player_list()
	return {"ok": true, "reason": ""}

# ---------------- Internal ----------------

func _reset_state_only() -> void:
	connected = false
	_pending_auth.clear()
	_players.clear()

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
	emit_signal("player_list_changed", get_players())

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_pending_auth[peer_id] = float(Time.get_ticks_msec()) / 1000.0
	print("[Network] Peer connected: %d (pending auth)" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		_pending_auth.erase(peer_id)
		if _players.has(peer_id):
			var p: Dictionary = (_players.get(peer_id, {}) as Dictionary)
			print("[Network] Peer %d left (%s)" % [peer_id, str(p.get("username", ""))])
			_players.erase(peer_id)
			_broadcast_player_list()

func _tick_auth_timeouts() -> void:
	var now_s: float = float(Time.get_ticks_msec()) / 1000.0
	var to_kick: Array[int] = []

	for k: Variant in _pending_auth.keys():
		var peer_id: int = int(k)
		var t0: float = float(_pending_auth.get(peer_id, 0.0))
		if now_s - t0 > AUTH_TIMEOUT_SEC:
			to_kick.append(peer_id)

	for peer_id: int in to_kick:
		print("[Network] Auth timeout for peer %d" % peer_id)
		_kick_peer(peer_id, "auth_timeout")

func _kick_peer(peer_id: int, reason: String) -> void:
	rpc_id(peer_id, "kick", reason)

	var mp_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if mp_peer != null:
		mp_peer.disconnect_peer(peer_id, true)

	_pending_auth.erase(peer_id)
	_players.erase(peer_id)
	_broadcast_player_list()

func _broadcast_player_list() -> void:
	emit_signal("player_list_changed", get_players())
	rpc("player_list_update", get_players())

func _submit_auth_from_file() -> void:
	var af: AuthFile = AuthFile.load_from(_auth_file_path)

	if not af.exists():
		emit_signal("auth_state_changed", "auth_failed", "auth_file_missing")
		rpc_id(1, "auth_submit", {})
		return

	var shape: Dictionary = af.is_valid_shape()
	if not bool(shape.get("ok", false)):
		emit_signal("auth_state_changed", "auth_failed", str(shape.get("reason", "bad_auth_file")))
		rpc_id(1, "auth_submit", af.to_rpc_payload())
		return

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

	print("[Network] Generated DEV server secret at %s (set %s in prod!)" % [SERVER_SECRET_FALLBACK_PATH, AUTH_SECRET_ENV])
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

# ---------------- RPC (Handshake) ----------------

@rpc("any_peer", "reliable")
func auth_submit(payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	var now_unix: int = int(Time.get_unix_time_from_system())

	if not _pending_auth.has(peer_id) and not _players.has(peer_id):
		_pending_auth[peer_id] = float(Time.get_ticks_msec()) / 1000.0

	if _players.has(peer_id):
		return

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

	var p := PlayerInfo.new()
	p.peer_id = peer_id
	p.username = username
	p.uuid = uuid

	_players[peer_id] = p.to_dict()
	_pending_auth.erase(peer_id)

	print("[Network] Auth OK peer=%d user=%s uuid=%s" % [peer_id, username, uuid])

	rpc_id(peer_id, "auth_result", true, "", now_unix, get_players())
	_broadcast_player_list()

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
