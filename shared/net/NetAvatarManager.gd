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

func _on_players(players: Array) -> void:
	var local_id: int = _net.get_local_peer_id()

	# Track who should exist
	var should_exist: Dictionary = {}
	var idx := 0

	for p in players:
		if not (p is Dictionary):
			continue
		var d := p as Dictionary
		var pid: int = int(d.get("peer_id", 0))
		if pid == 0:
			continue

		# Only spawn remote avatars (local player is your real player controller later)
		if pid == local_id:
			continue

		should_exist[pid] = true

		if not _avatars.has(pid):
			var avatar := NetAvatar.new()
			avatar.setup(pid, str(d.get("username", "Player")))
			add_child(avatar)

			# Debug placement: line them up so you can see them
			avatar.global_position = Vector3(float(idx) * 2.5, 64.0, 0.0)
			_avatars[pid] = avatar
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
		var a: NetAvatar = _avatars[pid3]
		if is_instance_valid(a):
			a.queue_free()
		_avatars.erase(pid3)
