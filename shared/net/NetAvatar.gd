class_name NetAvatar
extends Node3D

var peer_id: int = 0
var username: String = ""

var _mesh: MeshInstance3D
var _label: Label3D

func setup(p_peer_id: int, p_username: String) -> void:
	peer_id = p_peer_id
	username = p_username
	if _label != null:
		_label.text = "%s\n(peer %d)" % [username, peer_id]

func _ready() -> void:
	# Mesh
	_mesh = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.2
	_mesh.mesh = cap
	add_child(_mesh)

	# Name label
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.01
	_label.position = Vector3(0, 1.6, 0)
	_label.text = "%s\n(peer %d)" % [username, peer_id]
	add_child(_label)
