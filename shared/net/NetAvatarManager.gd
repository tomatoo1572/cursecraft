extends Node3D

var _avatars: Dictionary = {} # peer_id -> NetAvatar
var _net: Network = null

func _ready() -> void:
	_net = _resolve_network()
	if _net == null:
		return

	if not _net.player_list_changed.is_connected(Callable(self, "_on_players")):
		_net.player_list_changed.connect(Callable(self, "_on_players"))
	if not _net.player_state_changed.is_connected(Callable(self, "_on_state")):
		_net.player_state_changed.connect(Callable(self, "_on_state"))

	_on_players(_net.get_players())

func _resolve_network() -> Network:
	var root: Node = get_tree().root
	if root.has_node("Network"):
		return root.get_node("Network") as Network
	if root.has_node("network"):
		return root.get_node("network") as Network
	return null

func _on_players(players: Array) -> void:
	if _net == null:
		return
	var local_id: int = _net.get_local_peer_id()
	if local_id == 0:
		_clear_all()
		return

	var want: Dictionary = {}
	for p in players:
		if not (p is Dictionary):
			continue
		var d := p as Dictionary
		var pid: int = int(d.get("peer_id", 0))
		if pid == 0 or pid == local_id:
			continue
		want[pid] = true

		if not _avatars.has(pid):
			var a := NetAvatar.new()
			a.setup(pid, str(d.get("username", "Player")))
			add_child(a)
			_avatars[pid] = a

	# remove missing
	var to_remove: Array[int] = []
	for k in _avatars.keys():
		var pid2: int = int(k)
		if not want.has(pid2):
			to_remove.append(pid2)
	for pid3 in to_remove:
		var a2: Node = _avatars[pid3]
		if is_instance_valid(a2):
			a2.queue_free()
		_avatars.erase(pid3)

func _on_state(peer_id: int, pos: Vector3, yaw: float) -> void:
	if _net == null:
		return
	var local_id: int = _net.get_local_peer_id()
	if local_id == 0 or peer_id == local_id:
		return
	if not _avatars.has(peer_id):
		return
	var a: NetAvatar = _avatars[peer_id]
	a.global_position = pos
	a.rotation.y = yaw

func _clear_all() -> void:
	for k in _avatars.keys():
		var n: Node = _avatars[k]
		if is_instance_valid(n):
			n.queue_free()
	_avatars.clear()
