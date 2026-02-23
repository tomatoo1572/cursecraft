extends Camera3D
class_name ViewportFlyCam

@export var move_speed: float = 18.0
@export var sprint_mult: float = 2.5
@export var mouse_sens: float = 0.003
@export var max_pitch_deg: float = 89.0

@export var toggle_capture_key: Key = KEY_F6

var _yaw: float = 0.0
var _pitch: float = 0.0
var _captured: bool = false

func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x

func set_captured(v: bool) -> void:
	_captured = v
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE)

func is_captured() -> bool:
	return _captured

func _unhandled_input(event: InputEvent) -> void:
	# Toggle capture with F6 (works even when UI is on top)
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == toggle_capture_key:
			set_captured(not _captured)
			get_viewport().set_input_as_handled()
			return

		# ESC releases
		if k.keycode == KEY_ESCAPE and _captured:
			set_captured(false)
			get_viewport().set_input_as_handled()
			return

	# Mouse look
	if _captured and event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sens
		_pitch -= mm.relative.y * mouse_sens

		var max_pitch := deg_to_rad(max_pitch_deg)
		_pitch = clamp(_pitch, -max_pitch, max_pitch)

		rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()

func _physics_process(dt: float) -> void:
	if not _captured:
		return

	var dir := Vector3.ZERO
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var up := Vector3.UP

	if Input.is_key_pressed(KEY_W):
		dir += fwd
	if Input.is_key_pressed(KEY_S):
		dir -= fwd
	if Input.is_key_pressed(KEY_A):
		dir -= right
	if Input.is_key_pressed(KEY_D):
		dir += right

	if Input.is_key_pressed(KEY_SPACE):
		dir += up
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C):
		dir -= up

	if dir == Vector3.ZERO:
		return

	dir = dir.normalized()
	var spd := move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		spd *= sprint_mult

	global_position += dir * spd * dt
