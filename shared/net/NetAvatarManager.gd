extends Node3D

# peer_id -> NetAvatar
var _avatars: Dictionary = {}
var _net: Network = null

func _ready() -> void:
	_net = _resolve_network_singleton()
	if _net == null:
		push_error("[NetAvatarManager] Network autoload not found at /root/Network or /root/network.")
		return

	if not _net.player_list_changed.is_connected(Callable(self, "_on_players")):
		_net.player_list_changed.connect(Callable(self, "_on_players"))

	# Apply current roster immediately
	_on_players(_net.get_players())

func _resolve_network_singleton() -> Network:
	var root: Node = get_tree().root
	if root.has_node("Network"):
		return root.get_node("Network") as Network
	if root.has_node("network"):
		return root.get_node("network") as Network
	return null

func _clear_all() -> void:
	for k in _avatars.keys():
		var a: Node = _avatars[k]
		if is_instance_valid(a):
			a.queue_free()
	_avatars.clear()

func _get_camera() -> Camera3D:
	var cam := get_viewport().get_camera_3d()
	return cam

func _on_players(players: Array) -> void:
	# If multiplayer isn't active yet (or we got disconnected), don't spawn anything.
	var local_id: int = _net.get_local_peer_id()
	if local_id == 0:
		_clear_all()
		return

	var cam: Camera3D = _get_camera()
	var base_pos := Vector3(0, 64, 0)
	if cam != null:
		# Place in front of the camera so you can always see them.
		base_pos = cam.global_position + (-cam.global_transform.basis.z * 6.0)

	# Track who should exist
	var should_exist: Dictionary = {}
	var idx := 0

	print("[NetAvatarManager] roster size=%d local_id=%d" % [players.size(), local_id])

	for p in players:
		if not (p is Dictionary):
			continue
		var d := p as Dictionary
		var pid: int = int(d.get("peer_id", 0))
		if pid == 0:
			continue

		# Spawn only remotes
		if pid == local_id:
			continue

		should_exist[pid] = true

		if not _avatars.has(pid):
			var avatar := NetAvatar.new()
			avatar.setup(pid, str(d.get("username", "Player")))
			add_child(avatar)

			# Spread them out a bit
			avatar.global_position = base_pos + Vector3(float(idx) * 2.0, 0.0, 0.0)
			_avatars[pid] = avatar

			print("[NetAvatarManager] spawned avatar for peer=%d" % pid)
		else:
			var avatar2: NetAvatar = _avatars[pid]
			avatar2.setup(pid, str(d.get("username", "Player")))

		idx += 1

	# Remove avatars for players who left
	var to_remove: Array[int] = []
	for k in _avatars.keys():
		var pid2: int = int(k)
		if not should_exist.has(pid2):
			to_remove.append(pid2)

	for pid3 in to_remove:
		var a2: NetAvatar = _avatars[pid3]
		if is_instance_valid(a2):
			a2.queue_free()
		_avatars.erase(pid3)
		print("[NetAvatarManager] removed avatar peer=%d" % pid3)
