extends CharacterBody3D

signal died

enum AttackMode { RANGED, MELEE }

# ============================================================
#  EXPORTS
# ============================================================
@export var attack_mode: AttackMode = AttackMode.RANGED
@export var max_health: float = 10.0
@export var move_speed: float = 3.0
@export var acceleration: float = 12.0
@export var turn_speed: float = 10.0
@export var detection_range: float = 1000.0   # 1000 = te persigue desde cualquier lado del mapa
@export var lose_range: float = 1000.0
@export var explosion_size: float = 0.7   # 1.0 = tamaño de la explosión de la papa
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0         # Segundos entre ataques
@export var separation_radius: float = 1.2    # Distancia que intentan mantener entre enemigos
@export var debug_collisions: bool = false    # Actívalo para imprimir con qué choca el enemigo

@export_group("Disparo")
@export var shoot_range: float = 7.0          # Distancia a la que se detiene y dispara
@export var bullet_speed: float = 12.0

@export_group("Armas")
@export var ranged_weapon: PackedScene = preload("res://resources/models/Bone_Revolver.glb")
@export var melee_weapon: PackedScene = preload("res://resources/models/maza_perros.glb")
@export var ranged_weapon_rotation := Vector3(-90, 0, 0)   # Ajusta según hacia dónde apunte el cañón
@export var ranged_weapon_offset := Vector3(0, 0.08, 0)
@export var melee_weapon_rotation := Vector3.ZERO
@export var melee_weapon_offset := Vector3(0, 0.08, 0)

@export_group("Modelo")
@export var model_yaw_offset: float = 0.0     # Si camina de espaldas, ponlo en 3.14159
@export var walk_cycle_speed: float = 2.2
@export var leg_swing: float = 0.7
@export var arm_swing: float = 0.5

@onready var model: Node3D = $Model

const BONE_NAMES := ["thigh.L", "thigh.R", "upper_arm.L", "upper_arm.R", "spine", "hand.R"]

# ============================================================
#  ESTADO
# ============================================================
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var current_health: float
var player: Node3D
var player_in_range: Node3D = null   # Lo actualiza el Area3D de ataque (modo MELEE)
var attack_timer: float = 0.0
var is_dead: bool = false
var is_chasing: bool = false

# Flash al recibir daño
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween

# Animación procedural
var skeleton: Skeleton3D
var bones := {}          # nombre -> índice
var bone_rest := {}      # nombre -> Quaternion de reposo
var _walk_phase := 0.0
var _arm_blend := 0.0    # 0 = brazo caminando, 1 = brazo en pose de ataque
var _arm_angle := 0.0    # Rotación del brazo en X (negativo = hacia adelante/arriba)
var _arm_yaw := 0.0      # Cierre del brazo hacia el centro
var _lean := 0.0         # Inclinación del torso
var _is_attacking := false
var _model_base_y := 0.0


# ============================================================
#  CICLO DE VIDA
# ============================================================
func _ready() -> void:
	add_to_group("enemies")
	RhythmManager.enemigos_activos += 1
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")
	_model_base_y = model.position.y
	_setup_skeleton()
	_attach_weapon()
	_setup_flash()   # Después del arma, para que ella también parpadee


func _exit_tree() -> void:
	# Aquí (y no en die()) para que el contador baje siempre, muera como muera
	if is_instance_valid(RhythmManager):
		RhythmManager.enemigos_activos -= 1


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_detection()
	attack_timer = maxf(attack_timer - delta, 0.0)

	var dir := Vector3.ZERO
	var dist := INF
	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		dir = to_player.normalized()

	# Perseguir hasta estar en condiciones de atacar (se queda quieto mientras ataca)
	var target_vel := Vector3.ZERO
	if is_chasing and not _is_attacking and not _can_attack(dist):
		target_vel = dir * move_speed

	if is_chasing and dir != Vector3.ZERO:
		# Girar el modelo hacia el jugador
		var yaw := atan2(dir.x, dir.z) + model_yaw_offset
		model.rotation.y = lerp_angle(model.rotation.y, yaw, turn_speed * delta)

		# Separarse de los otros enemigos para no amontonarse
		target_vel += _separation() * move_speed
		target_vel = target_vel.limit_length(move_speed)

	velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)

	if is_chasing and not _is_attacking and attack_timer <= 0.0 and _can_attack(dist):
		_start_attack()

	move_and_slide()

	if debug_collisions:
		_debug_collisions()


func _update_detection() -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		is_chasing = false
		return

	var dist := global_position.distance_to(player.global_position)
	if not is_chasing and dist <= detection_range:
		is_chasing = true
	elif is_chasing and dist > lose_range:
		is_chasing = false


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Node3D):
			continue
		var off: Vector3 = global_position - (other as Node3D).global_position
		off.y = 0.0
		var d := off.length()
		if d > 0.001 and d < separation_radius:
			push += off / d * (1.0 - d / separation_radius)
	return push


func _debug_collisions() -> void:
	if Engine.get_physics_frames() % 30 != 0:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		print("[", name, "] choca con: ", c.get_collider(),
			"  normal: ", c.get_normal(), "  pos: ", c.get_position())


# ============================================================
#  ESQUELETO, ARMA Y ANIMACIÓN PROCEDURAL
# ============================================================
func _setup_skeleton() -> void:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("Enemy: no encontré un Skeleton3D dentro de Model")
		return
	skeleton = found[0] as Skeleton3D
	for n: String in BONE_NAMES:
		var i := skeleton.find_bone(n)
		if i == -1:
			i = skeleton.find_bone(n.replace(".", "_"))
		if i != -1:
			bones[n] = i
			bone_rest[n] = skeleton.get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion()
		else:
			push_warning("Enemy: hueso no encontrado: " + n)


func _attach_weapon() -> void:
	if skeleton == null or not bones.has("hand.R"):
		return
	var is_ranged := attack_mode == AttackMode.RANGED
	var scene: PackedScene = ranged_weapon if is_ranged else melee_weapon
	if scene == null:
		return
	var att := BoneAttachment3D.new()
	skeleton.add_child(att)
	att.bone_name = skeleton.get_bone_name(bones["hand.R"])
	var w := scene.instantiate() as Node3D
	att.add_child(w)
	w.rotation_degrees = ranged_weapon_rotation if is_ranged else melee_weapon_rotation
	w.position = ranged_weapon_offset if is_ranged else melee_weapon_offset


func _process(delta: float) -> void:
	if is_dead or skeleton == null:
		return

	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := clampf(speed / move_speed, 0.0, 1.0)
	_walk_phase += speed * walk_cycle_speed * delta
	var s := sin(_walk_phase) * moving

	# Piernas
	_pose("thigh.L", Quaternion(Vector3.RIGHT, s * leg_swing))
	_pose("thigh.R", Quaternion(Vector3.RIGHT, -s * leg_swing))

	# Brazos: el izquierdo solo camina; el derecho mezcla caminar <-> ataque
	_pose("upper_arm.L", Quaternion(Vector3.RIGHT, -s * arm_swing))
	var arm_walk := Quaternion(Vector3.RIGHT, s * arm_swing)
	var arm_attack := Quaternion(Vector3.UP, _arm_yaw) * Quaternion(Vector3.RIGHT, _arm_angle)
	_pose("upper_arm.R", arm_walk.slerp(arm_attack, _arm_blend))

	# Torso y rebote al caminar
	_pose("spine", Quaternion(Vector3.RIGHT, _lean))
	model.position.y = _model_base_y + absf(sin(_walk_phase)) * 0.05 * moving


# Aplica una rotación en el espacio del padre sobre la pose de reposo del hueso
func _pose(bone: String, delta_q: Quaternion) -> void:
	if bones.has(bone):
		skeleton.set_bone_pose_rotation(bones[bone], delta_q * bone_rest[bone])


# ============================================================
#  ATAQUES
# ============================================================
func _can_attack(dist: float) -> bool:
	if attack_mode == AttackMode.RANGED:
		return dist <= shoot_range
	return player_in_range != null


func _start_attack() -> void:
	attack_timer = attack_speed
	_is_attacking = true
	var t := create_tween()

	if attack_mode == AttackMode.RANGED:
		# Levanta el brazo apuntando al frente -> dispara -> retroceso -> baja
		_arm_angle = deg_to_rad(-85.0)
		_arm_yaw = deg_to_rad(36.0)
		t.tween_property(self, "_arm_blend", 1.0, 0.25)
		t.tween_callback(_fire)
		t.tween_property(self, "_arm_angle", deg_to_rad(-100.0), 0.05)
		t.tween_property(self, "_arm_angle", deg_to_rad(-85.0), 0.10)
		t.tween_interval(0.15)
		t.tween_property(self, "_arm_blend", 0.0, 0.25)
	else:
		# Golpe por arriba: sube el brazo -> golpea (daño) -> recupera
		_arm_yaw = 0.0
		_arm_angle = deg_to_rad(-165.0)
		t.tween_property(self, "_arm_blend", 1.0, 0.30)
		t.tween_interval(0.05)
		t.tween_property(self, "_arm_angle", deg_to_rad(-20.0), 0.12) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		t.parallel().tween_property(self, "_lean", 0.3, 0.12)
		t.tween_callback(_melee_hit)
		t.tween_interval(0.10)
		t.tween_property(self, "_arm_blend", 0.0, 0.25)
		t.parallel().tween_property(self, "_lean", 0.0, 0.25)

	t.tween_callback(func() -> void: _is_attacking = false)


func _melee_hit() -> void:
	if is_dead:
		return
	if is_instance_valid(player_in_range) and player_in_range.has_method("recibir_dano"):
		player_in_range.recibir_dano(attack_damage)


func _fire() -> void:
	if is_dead or not is_instance_valid(player):
		return
	var origin := _hand_position()
	var dir := player.global_position - origin
	dir.y = 0.0
	dir = dir.normalized()

	var bullet := EnemyBullet.new()
	bullet.damage = attack_damage
	bullet.move_vector = dir * bullet_speed
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = origin


func _hand_position() -> Vector3:
	if skeleton and bones.has("hand.R"):
		return skeleton.to_global(skeleton.get_bone_global_pose(bones["hand.R"]).origin)
	return global_position + Vector3.UP


func _on_attack_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body


func _on_attack_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = null


# ============================================================
#  VIDA
# ============================================================
func take_damage(amount: float) -> void:
	if is_dead:
		return

	current_health -= amount
	_flash_hit()

	if current_health <= 0.0:
		die()


func die():
	if is_dead:
		return
	is_dead = true
	died.emit()
	RhythmManager.enemigos_activos -= 1
	ExplosionFX.spawn(get_tree().current_scene, global_position + Vector3(0, 0.7, 0), explosion_size)
	queue_free()


# --- FLASH AL RECIBIR DAÑO ---
# Usa un material superpuesto (material_overlay) propio de cada enemigo.
# No toca los materiales originales, así que nunca queda "pegado" en rojo.
func _setup_flash() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.0)

	for node in model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _flash_mat


func _flash_hit() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_mat.albedo_color.a = 0.6
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.15)
