extends CharacterBody3D

signal died

@onready var model: Node3D = $Model

@export var max_health: float = 10.0
@export var move_speed: float = 3.0
@export var acceleration: float = 12.0
@export var detection_range: float = 1000.0
@export var lose_range: float = 1000.0
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0
@export var separation_radius: float = 1.2   # Distancia que intentan mantener entre enemigos
@export var debug_collisions: bool = false   # Actívalo para imprimir con qué choca el enemigo

var current_health: float
var player: Node3D
var player_in_range: Node3D = null
var attack_timer: float = 0.0
var is_dead: bool = false
var is_chasing: bool = false

var _flash_mat: StandardMaterial3D
var _flash_tween: Tween

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	add_to_group("enemies")
	RhythmManager.enemigos_activos += 1
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")
	_setup_flash()


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

	if attack_timer > 0.0:
		attack_timer -= delta

	if player_in_range != null and attack_timer <= 0.0:
		_attack()

	var target_vel := Vector3.ZERO

	if is_chasing and player_in_range == null and is_instance_valid(player):
		var dir := player.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()

		target_vel = dir * move_speed

		# Girar el modelo hacia la dirección del movimiento.
		# Se asume que el frente del pug apunta hacia +Z.
		if dir.length_squared() > 0.001:
			model.rotation.y = atan2(dir.x, dir.z)

		# Separarse de los otros enemigos para no amontonarse
		target_vel += _separation() * move_speed
		target_vel = target_vel.limit_length(move_speed)

	velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)

	move_and_slide()

	if debug_collisions:
		_debug_collisions()


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


func take_damage(amount: float) -> void:
	if is_dead:
		return

	current_health -= amount
	_flash_hit()

	if current_health <= 0.0:
		die()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	died.emit()
	queue_free()


func _on_attack_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = body


func _on_attack_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_range = null


func _attack() -> void:
	attack_timer = attack_speed

	if (
		is_instance_valid(player_in_range)
		and player_in_range.has_method("recibir_dano")
	):
		player_in_range.recibir_dano(attack_damage)


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
