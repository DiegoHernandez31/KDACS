extends CharacterBody3D

signal died

@onready var model: Node3D = $Model

@export var max_health: float = 10.0
@export var move_speed: float = 3.0
@export var acceleration: float = 12.0
@export var detection_range: float = 8.0
@export var lose_range: float = 12.0
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0

var current_health: float
var player: Node3D
var player_in_range: Node3D = null
var attack_timer: float = 0.0
var is_dead: bool = false
var is_chasing: bool = false

var gravity: float = ProjectSettings.get_setting(
    "physics/3d/default_gravity"
)

func _ready() -> void:
	add_to_group("enemies")
	RhythmManager.enemigos_activos += 1
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")

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

	velocity.x = move_toward(
		velocity.x, target_vel.x, acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z, target_vel.z, acceleration * delta
	)

	move_and_slide()

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
	RhythmManager.enemigos_activos -= 1
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

func _flash_hit() -> void:
	# Buscar las mallas del modelo 3D.
	var meshes := model.find_children(
		"*", "MeshInstance3D", true, false
	)

	for node in meshes:
		var mesh_instance := node as MeshInstance3D

		if mesh_instance.mesh == null:
			continue

		for i in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(i)

			if material is StandardMaterial3D:
				# Duplicar el material para no cambiar otros enemigos.
				var material_copy := material.duplicate() as StandardMaterial3D
				mesh_instance.set_surface_override_material(i, material_copy)

				var original_color: Color = material_copy.albedo_color
				material_copy.albedo_color = Color(1.0, 0.3, 0.3)

				var tween := create_tween()
				tween.tween_property(
					material_copy,
					"albedo_color",
					original_color,
					0.15
				)
