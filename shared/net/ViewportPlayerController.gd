extends CharacterBody3D
class_name ViewportPlayerController

@export var walk_speed: float = 8.0
@export var sprint_mult: float = 1.8
@export var jump_velocity: float = 6.5
@export var gravity: float = 18.0

@export var mouse_sens: float = 0.003
@export var max_pitch_deg: float = 89.0
@export var toggle_capture_key: Key = KEY_F6
@export var net_send_hz: float = 20.0

var _cam: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _captured: bool = false

var _prev_toggle: bool = false
var _prev_esc: bool = false

var _net: Network = null
var _net_accum: float = 0.0

func _ready() -> void:
	# Collision
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.2
	cs.shape = cap
	add_child(cs)

	# Camera
	_cam = Camera3D.new()
	_cam.current = true
	_cam.position = Vector3(0, 1.55, 0)
	add_child(_cam)

	_net = _resolve_network()

func _resolve_network() -> Network:
	var root: Node = get_tree().root
	if root.has_node("Network"):
		return root.get_node("Network") as Network
	if root.has_node("network"):
		return root.get_node("network") as Network
	return null

func set_captured(v: bool) -> void:
	_captured = v
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE)

func _process(dt: float) -> void:
	# Toggle capture (F6)
	var tdown: bool = Input.is_key_pressed(toggle_capture_key)
	if tdown and not _prev_toggle:
		set_captured(not _captured)
	_prev_toggle = tdown

	# ESC releases
	var esc: bool = Input.is_key_pressed(KEY_ESCAPE)
	if esc and not _prev_esc and _captured:
		set_captured(false)
	_prev_esc = esc

	# Mouse look via polling (reliable even in SubViewport)
	if _captured:
		var vel: Vector2 = Input.get_last_mouse_velocity()
		_yaw -= vel.x * mouse_sens * dt
		_pitch -= vel.y * mouse_sens * dt

		var max_pitch := deg_to_rad(max_pitch_deg)
		_pitch = clamp(_pitch, -max_pitch, max_pitch)

		rotation = Vector3(0.0, _yaw, 0.0)
		_cam.rotation = Vector3(_pitch, 0.0, 0.0)

func _physics_process(dt: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * dt
	else:
		velocity.y = 0.0

	# Jump
	if _captured and is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	# Movement
	var input_dir := Vector3.ZERO
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x

	if _captured:
		if Input.is_key_pressed(KEY_W):
			input_dir += fwd
		if Input.is_key_pressed(KEY_S):
			input_dir -= fwd
		if Input.is_key_pressed(KEY_D):
			input_dir += right
		if Input.is_key_pressed(KEY_A):
			input_dir -= right

	var spd := walk_speed
	if _captured and Input.is_key_pressed(KEY_SHIFT):
		spd *= sprint_mult

	input_dir.y = 0.0
	if input_dir.length_squared() > 0.0:
		input_dir = input_dir.normalized()
		velocity.x = input_dir.x * spd
		velocity.z = input_dir.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0.0, spd * 8.0 * dt)
		velocity.z = move_toward(velocity.z, 0.0, spd * 8.0 * dt)

	move_and_slide()

	# Send state to server / broadcast from host
	_net_accum += dt
	if _net != null and net_send_hz > 0.0 and _net_accum >= (1.0 / net_send_hz):
		_net_accum = 0.0
		_net.submit_local_state(global_position, rotation.y)
