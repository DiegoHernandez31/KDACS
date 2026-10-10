extends CharacterBody3D

# ============================================================
#  NODOS Y EXPORTS
# ============================================================
@onready var camera = get_viewport().get_camera_3d()
@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var skeleton: Skeleton3D = model.find_child("Skeleton3D", true, false) as Skeleton3D
@onready var aim_pivot: Node3D = $AimPivot
@onready var game_over_ui = $CanvasLayer/game_over
@onready var head: Node3D = get_node_or_null("Head")   # Opcional: solo se usa con body_mouse_look

@export var health: int = 100   # Sin uso aquí: la vida real es RhythmManager.energia_actual


# ============================================================
#  CONSTANTES
# ============================================================
const SPEED := 5.0
const JUMP_VELOCITY := 6.0

# --- ROLL ---
const ROLL_SPEED := 11.0
const ROLL_DURATION := 0.35      # Cuánto dura el roll (y la invulnerabilidad)
const ROLL_COOLDOWN := 0.8       # Espera entre rolls
const ROLL_ENERGY_BONUS := 9.0   # Energía ganada si lo haces en beat

# --- ARMAS ---
const PICKUP_RANGE := 1.8
const THROW_HOLD_TIME := 0.25    # Segundos de mantener la tecla para que sea lanzamiento
const THROW_SPEED := 16.0

# --- MELEE ---
const MELEE_RANGE := 1.4         # A qué distancia del jugador está el centro del golpe
const MELEE_RADIUS := 0.9        # Tamaño del área de golpe
const MELEE_DAMAGE := 1.0
const MELEE_COOLDOWN := 0.15
const MELEE_OFFBEAT_MULT := 0.0  # Multiplicador de daño fuera de ritmo (0 = no hace daño)

# --- ANIMACIÓN: CAMINATA (radianes) ---
const WALK_THIGH := 0.5          # Balanceo de cadera (pasos)
const WALK_KNEE := 0.9           # Flexión de rodilla al levantar el pie
const WALK_ARM := 0.3            # Balanceo de brazos
const WALK_HAND_COUNTER := 0.6   # 0..1: cuánto se contrarresta el giro del brazo en la mano

# --- ANIMACIÓN: BRAZO AL DISPARAR ---
const SHOOT_ARM_RAISE := -1.4    # Cuánto sube el brazo derecho (negativo = adelante/arriba)
const SHOOT_ARM_HOLD := 0.45     # Segundos que se queda arriba después del último disparo
const SHOOT_ARM_SPEED := 14.0    # Qué tan rápido sube/baja (mayor = más brusco)
const SHOOT_RECOIL := 0.2        # "Latigazo" extra hacia arriba en cada disparo
const SHOOT_RECOIL_DECAY := 2.5  # Qué tan rápido se disipa el retroceso

# --- ARMA EN LA MANO ---
const GRIP_OFFSET := Vector3(0.0, 0.2, 0.1)
const WEAPON_GRIP_NUDGE := Vector3.ZERO
const WEAPON_LOWERED_PITCH := 70.0

# ============================================================
#  ESTADO
# ============================================================
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_dead := false

# Roll
var is_rolling := false
var is_invulnerable := false
var roll_timer := 0.0
var roll_cooldown_timer := 0.0
var roll_direction := Vector3.ZERO

# Armas
var weapon_hold_time := 0.0
var weapon_hold_active := false

# Melee
var melee_cooldown_timer := 0.0

# Modelo y animación
var model_base_scale := Vector3.ONE
var model_base_pos := Vector3.ZERO
var walk_time := 0.0
var walk_blend := 0.0
var shoot_arm_timer := 0.0
var shoot_arm_blend := 0.0
var shoot_recoil := 0.0
var _arm_r_angle := 0.0   # Ángulo actual del brazo derecho (lo escribe _animate_model)
var _hand_idx := -1
var _meshes: Array[MeshInstance3D] = []
var _swing_axis := {}
var _alpha_tween: Tween
var _scale_tween: Tween

# Tutorial: acciones bloqueadas (el tutorial las desbloquea de a poco)
var locked_actions := {}


# ============================================================
#  CICLO DE VIDA E INPUT
# ============================================================
func _ready() -> void:
	add_to_group("player")
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
	model_base_scale = model.scale
	model_base_pos = model.position
	for n in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n as MeshInstance3D)
	_setup_skeleton()
	game_over_ui.visible = false


func _process(_delta: float) -> void:
	if is_dead:
		return

func _unhandled_input(_event):
	if Input.is_action_just_pressed("shoot") and not is_action_locked("shoot"):
		if aim_pivot.has_node("Weapon"):
			var weapon = aim_pivot.get_node("Weapon")

			if not RhythmManager.es_en_beat():
				RhythmManager.registrar_fallo()
				_on_shoot_pose()
				return

			_on_shoot_pose()                       # 1) Brazo arriba al instante
			weapon.shoot(_get_aim_direction())     # 2) La bala sale hacia donde apuntas
		else:
			_melee_attack()

func _try_shoot() -> void:
	var weapon = _get_weapon()
	if weapon == null:
		_melee_attack()
		return

	if not RhythmManager.es_en_beat():
		RhythmManager.registrar_fallo()
		_on_shoot_pose()
		return

	_on_shoot_pose()   # 1) Brazo arriba al instante
	if weapon.has_method("shoot"):
		weapon.shoot(_get_aim_direction())   # 2) La bala sale hacia donde apuntas


func is_action_locked(action: String) -> bool:
	return locked_actions.get(action, false)


# ============================================================
#  MOVIMIENTO
# ============================================================
func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_action_locked("jump"):
		velocity.y = JUMP_VELOCITY

	roll_cooldown_timer = maxf(0.0, roll_cooldown_timer - delta)
	melee_cooldown_timer = maxf(0.0, melee_cooldown_timer - delta)

	if Input.is_action_just_pressed("roll") and can_roll() and not is_action_locked("roll"):
		_start_roll()

	if is_rolling:
		# Durante el roll el movimiento es fijo en la dirección elegida
		roll_timer -= delta
		velocity.x = roll_direction.x * ROLL_SPEED
		velocity.z = roll_direction.z * ROLL_SPEED
		if roll_timer <= 0.0:
			_end_roll()
	else:
		var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		var direction := (_move_basis() * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

		if direction != Vector3.ZERO:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0.0, SPEED)
			velocity.z = move_toward(velocity.z, 0.0, SPEED)

	if not is_action_locked("drop"):
		_handle_weapon_input(delta)
	_aim_at_mouse()
	_animate_model(delta)
	move_and_slide()
	_update_weapon_to_hand()   # Después de mover al personaje, para que no vaya un frame atrás


func _cam() -> Camera3D:
	return get_viewport().get_camera_3d()


func _is_free_look() -> bool:
	var cam := _cam()
	return cam != null and cam.get("free_look") == true


# En la vista 3, "adelante" es hacia donde mira la cámara; en las otras, ejes del mundo
func _move_basis() -> Basis:
	var cam := _cam()
	if cam != null and _is_free_look():
		return Basis(Vector3.UP, cam.global_rotation.y)
	return Basis.IDENTITY


# ============================================================
#  APUNTADO
# ============================================================
func _aim_at_mouse() -> void:
	var cam := _cam()
	if cam == null:
		return

	var free_look := _is_free_look()
	var mouse_pos: Vector2
	if free_look:
		mouse_pos = get_viewport().get_visible_rect().size / 2.0   # La mira está fija en el centro
	else:
		mouse_pos = get_viewport().get_mouse_position()

	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_direction := cam.project_ray_normal(mouse_pos)

	# Plano a la altura del arma, que es la altura a la que viaja la bala
	var aim_plane := Plane(Vector3.UP, aim_pivot.global_position.y)
	var intersection = aim_plane.intersects_ray(ray_origin, ray_direction)

	if intersection == null:
		# Rayo por encima del horizonte: usamos solo su dirección horizontal
		var flat := Vector3(ray_direction.x, 0.0, ray_direction.z)
		if flat.length_squared() < 0.0001:
			return
		intersection = global_position + flat.normalized() * 20.0

	var look_target := Vector3(intersection.x, aim_pivot.global_position.y, intersection.z)

	if free_look:
		# El personaje mira hacia donde mira la cámara: siempre le ves la espalda
		var cam_fwd: Vector3 = -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		visual.global_rotation.y = atan2(cam_fwd.x, cam_fwd.z)
		# Si el punto de la mira cae pegado al jugador, apuntamos al frente de la cámara
		if aim_pivot.global_position.distance_to(look_target) < 2.5:
			look_target = aim_pivot.global_position + cam_fwd * 5.0
	else:
		var dir: Vector3 = intersection - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			visual.global_rotation.y = atan2(dir.x, dir.z)

	if not aim_pivot.global_position.is_equal_approx(look_target):
		aim_pivot.look_at(look_target, Vector3.UP)


# Dirección horizontal hacia donde apunta el jugador (no depende de la animación)
func _get_aim_direction() -> Vector3:
	var dir := -aim_pivot.global_transform.basis.z
	dir.y = 0.0
	return dir.normalized()


# ============================================================
#  ANIMACIÓN PROCEDURAL
# ============================================================
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
	var arm_r_walk := s * WALK_ARM * walk_blend

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


func _on_shoot_pose() -> void:
	shoot_arm_timer = SHOOT_ARM_HOLD
	shoot_recoil = SHOOT_RECOIL
	shoot_arm_blend = 1.0     # Brazo arriba ya, así el arma nunca está a medio subir al disparar
	_animate_model(0.0)       # Aplica la pose a los huesos en este mismo instante
	_update_weapon_to_hand()


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


# ============================================================
#  EFECTOS VISUALES (un solo tween por propiedad, para que no se pisen)
# ============================================================
func _set_model_alpha(a: float) -> void:
	for m in _meshes:
		m.transparency = 1.0 - a


func _tween_alpha(from: float, to: float, time: float) -> void:
	if _alpha_tween:
		_alpha_tween.kill()
	_alpha_tween = create_tween()
	_alpha_tween.tween_method(_set_model_alpha, from, to, time)


func _tween_scale(target: Vector3, time: float, then_back := false) -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(model, "scale", target, time)
	if then_back:
		_scale_tween.tween_property(model, "scale", model_base_scale, 0.1)


# ============================================================
#  ROLL
# ============================================================
func can_roll() -> bool:
	return not is_rolling and roll_cooldown_timer <= 0.0 and is_on_floor()


func _start_roll() -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var dir := (_move_basis() * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if dir == Vector3.ZERO:
		dir = _get_aim_direction()
	roll_direction = dir

	is_rolling = true
	is_invulnerable = true
	roll_timer = ROLL_DURATION
	roll_cooldown_timer = ROLL_COOLDOWN

	if RhythmManager.es_en_beat():
		RhythmManager.ganar_energia(ROLL_ENERGY_BONUS)

	model.position = model_base_pos
	model.rotation.z = 0.0
	_tween_alpha(1.0, 0.5, 0.05)
	_tween_scale(model_base_scale * Vector3(1.2, 0.7, 1.0), 0.05)


func _end_roll() -> void:
	is_rolling = false
	is_invulnerable = false
	_tween_alpha(0.5, 1.0, 0.1)
	_tween_scale(model_base_scale, 0.1)


# ============================================================
#  SOLTAR / LANZAR / RECOGER ARMAS
# ============================================================
func _get_weapon() -> Node3D:
	return aim_pivot.get_node_or_null("Weapon") as Node3D


func _handle_weapon_input(delta: float) -> void:
	if Input.is_action_just_pressed("drop_weapon"):
		var nearby := _find_nearby_weapon()
		if nearby:
			_pickup(nearby)   # Si ya tienes arma, se intercambia al instante
			weapon_hold_active = false
		elif _get_weapon():
			weapon_hold_active = true
			weapon_hold_time = 0.0

	if weapon_hold_active:
		if Input.is_action_pressed("drop_weapon"):
			weapon_hold_time += delta
		if Input.is_action_just_released("drop_weapon"):
			_detach_weapon(weapon_hold_time >= THROW_HOLD_TIME)
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


# Saca el arma de la mano y la deja en el mundo (suelta o lanzada)
func _detach_weapon(throw: bool) -> void:
	var w := _get_weapon()
	if w == null:
		return

	if w.has_meta("hold_basis"):
		w.basis = w.get_meta("hold_basis")
	w.set_meta("hold_transform", w.transform)   # Para devolverla igual al recogerla
	aim_pivot.remove_child(w)

	var dir := _get_aim_direction()

	var dropped := DroppedWeapon.new()
	get_tree().current_scene.add_child(dropped)
	dropped.global_position = aim_pivot.global_position + dir * 0.8
	dropped.setup(w, self)

	if throw:
		dropped.launch(dir, THROW_SPEED)
	else:
		dropped.linear_velocity = dir * 1.0 + Vector3.UP * 1.5


func _pickup(dw: DroppedWeapon) -> void:
	# Si ya tienes arma, la suelta primero (intercambio inmediato)
	if _get_weapon():
		_detach_weapon(false)

	var w: Node3D = dw.weapon
	dw.remove_child(w)
	dw.queue_free()

	aim_pivot.add_child(w)
	w.name = "Weapon"
	w.transform = w.get_meta("hold_transform", Transform3D.IDENTITY)


# ============================================================
#  MELEE
# ============================================================
func _melee_attack() -> void:
	if is_rolling or melee_cooldown_timer > 0.0:
		return
	melee_cooldown_timer = MELEE_COOLDOWN

	# El ritmo se evalúa UNA vez, en el instante del clic
	var en_beat: bool = RhythmManager.es_en_beat()
	if not en_beat:
		RhythmManager.registrar_fallo("melee fuera de ritmo")

	var center := aim_pivot.global_position + _get_aim_direction() * MELEE_RANGE

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
			if body != null and body.has_method("take_damage"):
				body.take_damage(damage)
				RhythmManager.registrar_exito()   # Acierto: recupera energía, como la bala

	# Feedback visual: el golpe en beat se ve más fuerte
	var escala := Vector3(1.25, 0.9, 1.0) if en_beat else Vector3(1.08, 0.97, 1.0)
	_tween_scale(model_base_scale * escala, 0.05, true)


# ============================================================
#  DAÑO Y MUERTE
# ============================================================
func recibir_dano(cantidad: float) -> void:
	if is_dead or is_invulnerable:
		return
	RhythmManager.perder_energia(cantidad)
	if RhythmManager.energia_actual <= 0:
		die()
		return

	# Parpadeo de transparencia como feedback
	_tween_alpha(0.3, 1.0, 0.2)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_rolling = false
	velocity = Vector3.ZERO

	# Desactivar la colisión para que los enemigos te ignoren
	# (is_dead detiene la física, así el cuerpo no cae por el piso)
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)

	game_over_ui.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # Para poder hacer clic en los botones


# Los nombres de estas dos funciones corresponden a los nodos de tus botones
func _on_go_to_menu_2_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")   # Verifica que esta ruta exista


func _on_retry_2_pressed() -> void:
	get_tree().reload_current_scene()
