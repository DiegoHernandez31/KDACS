extends Camera3D

@export var target: Node3D
@export var follow_speed: float = 5.0
@export var offset: Vector3 = Vector3(0, 6, 6)   # Vista 1: isométrica

@export_group("Vista 2: shooter fija")
@export var shooter_offset: Vector3 = Vector3(0.5, 1.9, 3.0)
@export var shooter_pitch_deg: float = -12.0
@export var shooter_fov: float = 65.0

@export_group("Vista 3: shooter libre")
@export var mouse_sensitivity: float = 0.003
@export var orbit_distance: float = 3.2
@export var orbit_height: float = 1.5
@export var orbit_shoulder: float = 0.5
@export var orbit_min_pitch_deg: float = -60.0
@export var orbit_max_pitch_deg: float = 30.0
@export var orbit_start_pitch_deg: float = -12.0
@export var orbit_fov: float = 70.0

@export var crosshair: Control            # Mira propia (reemplaza al cursor del sistema)
@export var transition_speed: float = 6.0

var free_look := false   # true en la vista 3. Lo lee player.gd

var _iso_offset: Vector3
var _iso_pitch: float
var _iso_fov: float
var _base_yaw: float
var _current_offset: Vector3
var _fixed_pitch: float
var _fixed_pos: Vector3
var _mode := 1
var _fixed_mode := 1
var _blend := 0.0
var _yaw := 0.0
var _pitch := 0.0

func _ready():
	# Se actualiza DESPUÉS del jugador en cada tick de física (número mayor = más tarde)
	process_physics_priority = 100

	_iso_offset = offset
	_iso_pitch = rotation.x
	_iso_fov = fov
	_base_yaw = rotation.y
	_current_offset = offset
	_fixed_pitch = rotation.x
	_fixed_pos = global_position
	_yaw = _base_yaw
	_pitch = deg_to_rad(orbit_start_pitch_deg)
	_apply_mouse_mode()

func _apply_mouse_mode() -> void:
	# Vistas 1 y 2: cursor oculto pero dentro de la ventana. Vista 3: capturado en el centro
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if free_look else Input.MOUSE_MODE_CONFINED_HIDDEN

func _set_mode(m: int) -> void:
	if m == _mode:
		return
	_mode = m
	free_look = (m == 3)
	if m != 3:
		_fixed_mode = m
	else:
		_yaw = _base_yaw
		_pitch = deg_to_rad(orbit_start_pitch_deg)
	_apply_mouse_mode()

func _input(event):
	if free_look and event is InputEventMouseMotion:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(orbit_min_pitch_deg), deg_to_rad(orbit_max_pitch_deg))

func _process(_delta):
	if Input.is_action_just_pressed("camera1"):
		_set_mode(1)
	elif Input.is_action_just_pressed("camera2"):
		_set_mode(2)
	elif Input.is_action_just_pressed("camera3"):
		_set_mode(3)
	elif free_look and Input.is_action_just_pressed("ui_cancel"):
		_set_mode(1)

	_update_crosshair()

func _update_crosshair() -> void:
	if crosshair == null:
		return
	crosshair.visible = true
	var p: Vector2
	if free_look:
		p = get_viewport().get_visible_rect().size / 2.0
	else:
		p = get_viewport().get_mouse_position()
	# El centro de la imagen queda exactamente sobre el punto de apuntado
	crosshair.global_position = p - crosshair.size * crosshair.scale / 2.0

func _physics_process(delta):
	if target == null:
		return

	var t := 1.0 - exp(-transition_speed * delta)
	var follow_t := 1.0 - exp(-follow_speed * delta)   # Igual de suave con cualquier FPS

	# --- Vistas fijas (1 y 2) ---
	var fixed_offset := _iso_offset if _fixed_mode == 1 else shooter_offset
	var fixed_pitch_goal := _iso_pitch if _fixed_mode == 1 else deg_to_rad(shooter_pitch_deg)
	var fixed_fov_goal := _iso_fov if _fixed_mode == 1 else shooter_fov

	_current_offset = _current_offset.lerp(fixed_offset, t)
	_fixed_pitch = lerp_angle(_fixed_pitch, fixed_pitch_goal, t)
	_fixed_pos = _fixed_pos.lerp(target.global_position + _current_offset, follow_t)
	var fixed_basis := Basis.from_euler(Vector3(_fixed_pitch, _base_yaw, 0.0))

	# --- Vista libre (3) ---
	var orbit_basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var pivot := target.global_position + Vector3(0.0, orbit_height, 0.0)
	var orbit_pos := pivot + orbit_basis * Vector3(orbit_shoulder, 0.0, orbit_distance)

	# --- Mezcla ---
	_blend = move_toward(_blend, 1.0 if free_look else 0.0, delta * transition_speed * 0.5)
	var w := smoothstep(0.0, 1.0, _blend)

	var q := Quaternion(fixed_basis).slerp(Quaternion(orbit_basis), w)
	global_transform = Transform3D(Basis(q), _fixed_pos.lerp(orbit_pos, w))

	var fov_goal := lerpf(fixed_fov_goal, orbit_fov, w)
	fov = lerpf(fov, fov_goal, t)
