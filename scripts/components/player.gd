extends CharacterBody3D

@onready var camera = get_viewport().get_camera_3d()
@onready var sprite = $Sprite3D
@onready var aim_pivot = $AimPivot

const SPEED = 5.0

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

func _ready() -> void:
	add_to_group("player")

func _physics_process(delta):
	# Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

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
	move_and_slide()

func _aim_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	var floor_plane = Plane(Vector3.UP, global_position.y)
	var intersection = floor_plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection != null:
		# Usamos aim_pivot.global_position.y en lugar de global_position.y para el target
		# Esto asegura que el pivot siempre mire en un plano perfectamente horizontal (solo rota en el eje Y)
		var look_target = Vector3(intersection.x, aim_pivot.global_position.y, intersection.z)
		
		# Validamos respecto a la posición del pivot, no del root
		if not aim_pivot.global_position.is_equal_approx(look_target):
			aim_pivot.look_at(look_target, Vector3.UP)
			sprite.look_at(look_target, Vector3.UP)
			
			# NOTA: Eliminamos sprite.look_at(). Si usas Billboard, esto causa "backflips".
			# El código flip_h a continuación es suficiente para que el personaje "mire" izquierda/derecha.
			if intersection.x < global_position.x:
				sprite.flip_h = true  # Mira a la izquierda
			else:
				sprite.flip_h = false # Mira a la derecha
# --- ROLL ---

func can_roll() -> bool:
	return not is_rolling and roll_cooldown_timer <= 0.0 and is_on_floor()

func _start_roll():
	# Dirección: la del input; si no hay input, hacia donde apunta el mouse
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

	# Bonus de energía si se hizo en beat
	if RhythmManager.es_en_beat():
		RhythmManager.ganar_energia(ROLL_ENERGY_BONUS)

	# Feedback visual: sprite semitransparente y "aplastado" mientras rueda
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 0.5, 0.05)
	tween.tween_property(sprite, "scale", Vector3(1.2, 0.7, 1.0), 0.05)

func _end_roll():
	is_rolling = false
	is_invulnerable = false
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	tween.tween_property(sprite, "scale", Vector3.ONE, 0.1)
	
func _unhandled_input(_event):
	if Input.is_action_just_pressed("shoot"):
		if aim_pivot.has_node("Weapon"):
			var weapon = aim_pivot.get_node("Weapon")
			
			# --- INTEGRACIÓN DEL RITMO AQUÍ ---
			# Evaluamos el ritmo antes de ejecutar el disparo
			if not RhythmManager.es_en_beat():
				RhythmManager.registrar_fallo() 
			
			weapon.shoot()
		else:
			_melee_attack()

# --- SOLTAR / LANZAR / RECOGER ---

func _get_weapon() -> Node3D:
	return aim_pivot.get_node_or_null("Weapon") as Node3D

func _handle_weapon_input(delta: float) -> void:
	if Input.is_action_just_pressed("drop_weapon"):
		var nearby := _find_nearby_weapon()
		if nearby:
			# Recoger (y si ya tienes arma, se intercambia al instante)
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

# Saca el arma de la mano y la deja en el mundo (suelta o lanzada)
func _detach_weapon(throw: bool) -> void:
	var w := _get_weapon()
	if w == null:
		return

	w.set_meta("hold_transform", w.transform)  # Para devolverla igual al recogerla
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
	# Si ya tienes arma, la suelta primero (intercambio inmediato)
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

	# El ritmo se evalúa UNA vez, en el instante del clic
	var en_beat := RhythmManager.es_en_beat()
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
				RhythmManager.registrar_exito()  # Acierto: recupera energía, como la bala

	# Feedback visual: el golpe en beat se ve más fuerte
	var escala := Vector3(1.25, 0.9, 1.0) if en_beat else Vector3(1.08, 0.97, 1.0)
	var tween = create_tween()
	tween.tween_property(sprite, "scale", escala, 0.05)
	tween.tween_property(sprite, "scale", Vector3.ONE, 0.1)

func recibir_dano(cantidad: float) -> void:
	if is_invulnerable:
		return
	RhythmManager.perder_energia(cantidad)

	# Feedback: flash rojo
	sprite.modulate = Color(1.6, 0.4, 0.4)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)
