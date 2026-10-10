extends CharacterBody3D

@onready var camera = get_viewport().get_camera_3d()
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false)
@onready var aim_pivot = $AimPivot

@export var health: int = 100

var is_dead: bool = false # <--- ¡Aquí la definimos!

const SPEED = 5.0
const JUMP_VELOCITY = 6.0

# --- ROLL ---
const ROLL_SPEED = 11.0
const ROLL_DURATION = 0.35      # Cuánto dura el roll (y la invulnerabilidad)
const ROLL_COOLDOWN = 0.8       # Espera entre rolls
const ROLL_ENERGY_BONUS = 9.0   # Energía ganada si lo haces en beat

var is_rolling := false
var is_invulnerable := false
var roll_timer := 0.0
var roll_cooldown_timer := 0.0
var roll_direction := Vector3.ZERO

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

const PICKUP_RANGE := 1.8
const THROW_HOLD_TIME := 0.25   # Segundos de click derecho para que sea lanzamiento
const THROW_SPEED := 16.0

var weapon_hold_time := 0.0
var weapon_hold_active := false

# --- MELEE ---
const MELEE_RANGE := 1.4        # A qué distancia del jugador está el centro del golpe
const MELEE_RADIUS := 0.9       # Tamaño del área de golpe
const MELEE_DAMAGE := 1.0
const MELEE_COOLDOWN := 0.15

var melee_cooldown_timer := 0.0
const MELEE_OFFBEAT_MULT := 0.0   # Multiplicador de daño fuera de ritmo (0 = el golpe no hace daño)

# 1. Añade estas variables al principio de tu script
@export var mouse_sensitivity: float = 0.003
@onready var head = $Head # Asegúrate de que este nombre coincida con el nodo que creaste

func _ready():
	# Tu código anterior (health, etc...)
	add_to_group("player")
	# 2. Esto atrapa el mouse y lo vuelve invisible para jugar cómodamente
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	model_base_scale = model.scale
	model_base_pos = model.position
	for n in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n)
	_setup_skeleton()

# 3. Añadimos esta nueva función para detectar los movimientos del mouse
func _unhandled_input(event):
  if Input.is_action_just_pressed("shoot"):
      if aim_pivot.has_node("Weapon"):
        var weapon = aim_pivot.get_node("Weapon")

        if not RhythmManager.es_en_beat():
          RhythmManager.registrar_fallo() 

        _on_shoot_pose()
        weapon.shoot()
      else:
        _melee_attack()
	# Verificamos que el juego no esté pausado (por si el jugador murió)
	if not is_dead and event is InputEventMouseMotion:
		
		# Gira TODO EL CUERPO de izquierda a derecha (Eje Y)
		rotate_y(-event.relative.x * mouse_sensitivity)
		
		# Gira SOLO LA CABEZA de arriba a abajo (Eje X)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		
		# Limitamos la cabeza para no dar vueltas de 360 grados (mirar al techo/piso)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _process(delta):
	# Si presionas Shift, alterna el estado del mouse
	if Input.is_action_just_pressed("toggle_camera"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED: # (O CONFINED si usas Top-Down)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED) # (O CONFINED si usas Top-Down)
# --- MODELO 3D ---
# Ángulos de la caminata (radianes). Súbelos/bájalos para exagerar o suavizar.
const WALK_THIGH := 0.5     # Balanceo de cadera (pasos)
const WALK_KNEE := 0.9      # Flexión de rodilla al levantar el pie
const WALK_ARM := 0.3       # Balanceo de brazos
const WALK_HAND_COUNTER := 0.6  # 0..1: cuánto se contrarresta el giro del brazo en la mano

# --- BRAZO AL DISPARAR ---
const SHOOT_ARM_RAISE := -1.4   # Cuánto sube el brazo derecho (negativo = hacia adelante/arriba)
const SHOOT_ARM_HOLD := 0.45    # Segundos que se queda arriba después del último disparo
const SHOOT_ARM_SPEED := 14.0   # Qué tan rápido sube/baja (mayor = más brusco)
const SHOOT_RECOIL := 0.2       # Pequeño "latigazo" extra hacia arriba en cada disparo
const SHOOT_RECOIL_DECAY := 2.5 # Qué tan rápido se disipa el retroceso

# --- ARMA EN LA MANO ---
const GRIP_OFFSET := Vector3(0.0, 0.2, 0.1)
const WEAPON_GRIP_NUDGE := Vector3.ZERO
const WEAPON_LOWERED_PITCH := 70.0
var _hand_idx := -1
var _arm_r_angle := 0.0   # Ángulo actual del brazo derecho (lo escribe _animate_model)

var shoot_arm_timer := 0.0
var shoot_arm_blend := 0.0
var shoot_recoil := 0.0

var model_base_scale := Vector3.ONE
var model_base_pos := Vector3.ZERO
var walk_time := 0.0
var walk_blend := 0.0
var _meshes: Array[MeshInstance3D] = []
var _swing_axis := {}

func _physics_process(delta):
	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# --- NUEVO: Lógica de Salto ---
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Cooldown del roll
	if roll_cooldown_timer > 0.0:
		roll_cooldown_timer -= delta
	
	if melee_cooldown_timer > 0.0:
		melee_cooldown_timer -= delta

	# Iniciar roll
	if Input.is_action_just_pressed("roll") and can_roll():
		_start_roll()

	if is_rolling:
		# Durante el roll el movimiento es fijo en la dirección elegida
		roll_timer -= delta
		velocity.x = roll_direction.x * ROLL_SPEED
		velocity.z = roll_direction.z * ROLL_SPEED
		if roll_timer <= 0.0:
			_end_roll()
	else:
		var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)

	_handle_weapon_input(delta)
	_aim_at_mouse()
	_animate_model(delta)
	move_and_slide()
	_update_weapon_to_hand()  # Después de mover al personaje, para que no vaya un frame atrás

func _aim_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	var floor_plane = Plane(Vector3.UP, global_position.y)
	var intersection = floor_plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection != null:
		var look_target = Vector3(intersection.x, aim_pivot.global_position.y, intersection.z)
		
		if not aim_pivot.global_position.is_equal_approx(look_target):
			aim_pivot.look_at(look_target, Vector3.UP)

		var dir = intersection - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			visual.global_rotation.y = atan2(dir.x, dir.z)

# --- ANIMACIÓN PROCEDURAL ---

func _setup_skeleton() -> void:
	if skeleton == null:
		push_warning("No se encontró Skeleton3D")
		return
	for n in ["upper_arm.L", "upper_arm.R", "hand.L", "hand.R",
			"thigh.L", "thigh.R", "shin.L", "shin.R"]:
		var i := skeleton.find_bone(n)
		if i == -1:
			push_warning("Hueso no encontrado: " + n)
			continue
		var rest_basis := skeleton.get_bone_global_rest(i).basis
		_swing_axis[n] = {
			"idx": i,
			"axis": (rest_basis.inverse() * Vector3.RIGHT).normalized(),
			"rest_q": skeleton.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
		}
	_hand_idx = skeleton.find_bone("hand.R")

func _swing(n: String, angle: float) -> void:
	if not _swing_axis.has(n):
		return
	var d = _swing_axis[n]
	skeleton.set_bone_pose_rotation(d.idx, d.rest_q * Quaternion(d.axis, angle))

func _animate_model(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := speed > 0.1 and is_on_floor() and not is_rolling
	walk_blend = move_toward(walk_blend, 1.0 if moving else 0.0, delta * 8.0)
	if moving:
		walk_time += delta * speed * 2.2

	var s := sin(walk_time)
	var c := cos(walk_time)

	_swing("thigh.L",  s * WALK_THIGH * walk_blend)
	_swing("thigh.R", -s * WALK_THIGH * walk_blend)

	_swing("shin.L", maxf(0.0, -c) * WALK_KNEE * walk_blend)
	_swing("shin.R", maxf(0.0,  c) * WALK_KNEE * walk_blend)

	var arm_l := -s * WALK_ARM * walk_blend
	var arm_r_walk :=  s * WALK_ARM * walk_blend

	shoot_arm_timer = maxf(0.0, shoot_arm_timer - delta)
	var raise_target := 1.0 if (shoot_arm_timer > 0.0 and not is_rolling) else 0.0
	shoot_arm_blend = move_toward(shoot_arm_blend, raise_target, delta * SHOOT_ARM_SPEED)
	shoot_recoil = move_toward(shoot_recoil, 0.0, delta * SHOOT_RECOIL_DECAY)
	var arm_r := lerpf(arm_r_walk, SHOOT_ARM_RAISE - shoot_recoil, shoot_arm_blend)
	_arm_r_angle = arm_r

	_swing("upper_arm.L", arm_l)
	_swing("upper_arm.R", arm_r)
	_swing("hand.L", -arm_l * WALK_HAND_COUNTER)
	_swing("hand.R", -arm_r_walk * WALK_HAND_COUNTER * (1.0 - shoot_arm_blend))

	if moving:
		model.position.y = model_base_pos.y + absf(s) * 0.04
		model.rotation.z = s * 0.05
	else:
		model.position.y = lerpf(model.position.y, model_base_pos.y, 10.0 * delta)
		model.rotation.z = lerp_angle(model.rotation.z, 0.0, 10.0 * delta)

func _update_weapon_to_hand() -> void:
	var w := _get_weapon()
	if w == null or skeleton == null or _hand_idx == -1:
		return
	if not w.has_meta("hold_basis"):
		w.set_meta("hold_basis", w.basis)
	var hold_basis: Basis = w.get_meta("hold_basis")
	var aim_blend := 1.0
	if shoot_arm_timer <= 0.0:
		aim_blend = clampf(_arm_r_angle / SHOOT_ARM_RAISE, 0.0, 1.0)
	var pitch := deg_to_rad(WEAPON_LOWERED_PITCH) * (1.0 - aim_blend)
	w.basis = Basis(Vector3.RIGHT, -pitch) * hold_basis

	var hand_xf: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(_hand_idx)
	var grip_world: Vector3 = hand_xf * GRIP_OFFSET
	var grip_local := _weapon_grip_point(w) + WEAPON_GRIP_NUDGE
	w.global_position = grip_world - w.global_basis * grip_local

func _weapon_grip_point(w: Node3D) -> Vector3:
	if w.has_meta("grip_point"):
		return w.get_meta("grip_point")
	var point := Vector3.ZERO
	var grip := w.get_node_or_null("Grip") as Node3D
	if grip:
		point = w.to_local(grip.global_position)
	else:
		var inv := w.global_transform.affine_inverse()
		var box := AABB()
		var first := true
		var visuals := w.find_children("*", "VisualInstance3D", true, false)
		if w is VisualInstance3D:
			visuals.append(w)
		for n in visuals:
			var vi := n as VisualInstance3D
			var b: AABB = (inv * vi.global_transform) * vi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if not first:
			point = box.get_center()
	w.set_meta("grip_point", point)
	return point

func _on_shoot_pose() -> void:
	shoot_arm_timer = SHOOT_ARM_HOLD
	shoot_recoil = SHOOT_RECOIL
	_update_weapon_to_hand()

func _set_model_alpha(a: float) -> void:
	for m in _meshes:
		m.transparency = 1.0 - a

# --- ROLL ---

func can_roll() -> bool:
	return not is_rolling and roll_cooldown_timer <= 0.0 and is_on_floor()

func _start_roll():
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if dir == Vector3.ZERO:
		dir = -aim_pivot.global_transform.basis.z
		dir.y = 0
		dir = dir.normalized()
	roll_direction = dir

	is_rolling = true
	is_invulnerable = true
	roll_timer = ROLL_DURATION
	roll_cooldown_timer = ROLL_COOLDOWN

	if RhythmManager.es_en_beat():
		RhythmManager.ganar_energia(ROLL_ENERGY_BONUS)

	model.position = model_base_pos
	model.rotation.z = 0.0
	var tween = create_tween().set_parallel(true)
	tween.tween_method(_set_model_alpha, 1.0, 0.5, 0.05)
	tween.tween_property(model, "scale", model_base_scale * Vector3(1.2, 0.7, 1.0), 0.05)

func _end_roll():
	is_rolling = false
	is_invulnerable = false
	var tween = create_tween().set_parallel(true)
	tween.tween_method(_set_model_alpha, 0.5, 1.0, 0.1)
	tween.tween_property(model, "scale", model_base_scale, 0.1)

# --- SOLTAR / LANZAR / RECOGER ---

func _get_weapon() -> Node3D:
	return aim_pivot.get_node_or_null("Weapon") as Node3D

func _handle_weapon_input(delta: float) -> void:
	if Input.is_action_just_pressed("drop_weapon"):
		var nearby := _find_nearby_weapon()
		if nearby:
			_pickup(nearby)
			weapon_hold_active = false
		elif _get_weapon():
			weapon_hold_active = true
			weapon_hold_time = 0.0

	if weapon_hold_active:
		if Input.is_action_pressed("drop_weapon"):
			weapon_hold_time += delta
		if Input.is_action_just_released("drop_weapon"):
			if weapon_hold_time >= THROW_HOLD_TIME:
				_detach_weapon(true)
			else:
				_detach_weapon(false)
			weapon_hold_active = false

func _find_nearby_weapon() -> DroppedWeapon:
	var closest: DroppedWeapon = null
	var best := PICKUP_RANGE
	for node in get_tree().get_nodes_in_group("dropped_weapons"):
		var dw := node as DroppedWeapon
		if dw == null or dw.thrown:
			continue
		var d := global_position.distance_to(dw.global_position)
		if d < best:
			best = d
			closest = dw
	return closest

func _detach_weapon(throw: bool) -> void:
	var w := _get_weapon()
	if w == null:
		return

	if w.has_meta("hold_basis"):
		w.basis = w.get_meta("hold_basis")
	w.set_meta("hold_transform", w.transform)
	aim_pivot.remove_child(w)

	var dir = -aim_pivot.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()

	var dropped := DroppedWeapon.new()
	get_tree().current_scene.add_child(dropped)
	dropped.global_position = aim_pivot.global_position + dir * 0.8
	dropped.setup(w, self)

	if throw:
		dropped.launch(dir, THROW_SPEED)
	else:
		dropped.linear_velocity = dir * 1.0 + Vector3.UP * 1.5

func _pickup(dw: DroppedWeapon) -> void:
	if _get_weapon():
		_detach_weapon(false)

	var w := dw.weapon
	dw.remove_child(w)
	dw.queue_free()

	aim_pivot.add_child(w)
	w.name = "Weapon"
	w.transform = w.get_meta("hold_transform", Transform3D.IDENTITY)

func _melee_attack() -> void:
	if is_rolling or melee_cooldown_timer > 0.0:
		return
	melee_cooldown_timer = MELEE_COOLDOWN

	var en_beat: bool = RhythmManager.es_en_beat()
	if not en_beat:
		RhythmManager.registrar_fallo("melee fuera de ritmo")

	var dir = -aim_pivot.global_transform.basis.z
	dir.y = 0.0
	dir = dir.normalized()
	var center = aim_pivot.global_position + dir * MELEE_RANGE

	var shape := SphereShape3D.new()
	shape.radius = MELEE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.exclude = [get_rid()]
	query.collision_mask = 0xFFFFFFFF

	var damage := MELEE_DAMAGE if en_beat else MELEE_DAMAGE * MELEE_OFFBEAT_MULT

	if damage > 0.0:
		var hits := get_world_3d().direct_space_state.intersect_shape(query, 8)
		for h in hits:
			var body = h.collider
			if body.has_method("take_damage"):
				body.take_damage(damage)
				RhythmManager.registrar_exito()

	var escala := Vector3(1.25, 0.9, 1.0) if en_beat else Vector3(1.08, 0.97, 1.0)
	var tween = create_tween()
	tween.tween_property(model, "scale", model_base_scale * escala, 0.05)
	tween.tween_property(model, "scale", model_base_scale, 0.1)

func recibir_dano(cantidad: float) -> void:
	if is_invulnerable:
		return
	RhythmManager.perder_energia(cantidad)

	# Parpadeo de transparencia para feedback 3D
	var tween = create_tween()
	tween.tween_method(_set_model_alpha, 0.3, 1.0, 0.2)
