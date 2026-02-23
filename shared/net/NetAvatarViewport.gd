extends SubViewportContainer

@export var initial_size: Vector2i = Vector2i(640, 360)

const NetAvatarManagerScript: Script = preload("res://shared/net/NetAvatarManager.gd")
const VOXEL_WORLD_VIEW_SCRIPT_PATH: String = "res://shared/voxel/VoxelWorldView.gd"
const PlayerControllerScript: Script = preload("res://shared/net/ViewportPlayerController.gd")

var _vp: SubViewport
var _root3d: Node3D
var _world_view: Node = null
var _player: CharacterBody3D = null

func _ready() -> void:
	# Never steal UI clicks
	z_index = -10
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# IMPORTANT: allow manual viewport resizing (fixes your warning spam)
	stretch = false
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	_vp = SubViewport.new()
	_vp.disable_3d = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	_root3d = Node3D.new()
	_root3d.name = "NetDebug3D"
	_vp.add_child(_root3d)

	# Background
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.60, 0.70)
	we.environment = env
	_root3d.add_child(we)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	_root3d.add_child(light)

	# Debug ground (visual)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	ground.position = Vector3(0.0, 64.0, 0.0)
	_root3d.add_child(ground)

	# Debug ground collision (solid)
	var ground_body := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	ground_shape.shape = box
	ground_shape.position = Vector3(0.0, 64.0 - 0.5, 0.0)
	ground_body.add_child(ground_shape)
	_root3d.add_child(ground_body)

	# Player (solid movement + mouse look handled by controller)
	_player = PlayerControllerScript.new() as CharacterBody3D
	_player.name = "ViewportPlayer"
	_root3d.add_child(_player)

	# Networking capsules
	var mgr: Node3D = NetAvatarManagerScript.new()
	mgr.name = "NetAvatarManager"
	_root3d.add_child(mgr)

	# Optional terrain view
	_try_create_optional_world_view()

	# Manual viewport sizing
	_vp.size = initial_size
	_resync_viewport_size()
	resized.connect(Callable(self, "_resync_viewport_size"))

func _resync_viewport_size() -> void:
	if _vp == null:
		return
	var s: Vector2 = size
	_vp.size = Vector2i(max(1, int(s.x)), max(1, int(s.y)))

func _try_create_optional_world_view() -> void:
	if not ResourceLoader.exists(VOXEL_WORLD_VIEW_SCRIPT_PATH):
		return
	var scr: Script = load(VOXEL_WORLD_VIEW_SCRIPT_PATH) as Script
	if scr == null:
		return
	_world_view = scr.new()
	if _world_view != null:
		_world_view.name = "VoxelWorldView"
		_root3d.add_child(_world_view)

func set_world(sim: WorldSim, player_save: PlayerSave) -> void:
	if _world_view != null and _world_view.has_method("set_world"):
		_world_view.call("set_world", sim, player_save)

	# Spawn player above the save position
	if _player != null and player_save != null:
		_player.global_position = Vector3(
			float(player_save.pos.x) + 0.5,
			float(player_save.pos.y) + 3.0,
			float(player_save.pos.z) + 0.5
		)

func clear_world() -> void:
	if _world_view != null and _world_view.has_method("clear_world"):
		_world_view.call("clear_world")
