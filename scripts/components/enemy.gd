extends CharacterBody3D
signal died

@onready var sprite = $Sprite3D

@export var max_health: float = 10.0
@export var move_speed: float = 3.0
@export var acceleration: float = 12.0
@export var detection_range: float = 8.0   # Distancia a la que nota al jugador
@export var lose_range: float = 12.0       # Distancia a la que lo pierde (mayor que la de detección)
@export var attack_damage: float = 10.0
@export var attack_speed: float = 1.0

var current_health: float
var player: Node3D
var player_in_range: Node3D = null   # Jugador dentro del área de ataque
var attack_timer: float = 0.0
var is_dead: bool = false
var is_chasing: bool = false

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	add_to_group("enemies")
	RhythmManager.enemigos_activos += 1
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	if is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_detection()
	if attack_timer > 0.0:
		attack_timer -= delta
	if player_in_range != null and attack_timer <= 0.0:
		_attack()

	# Velocidad objetivo: perseguir si lo detectó y aún no está en rango de ataque
	var target_vel := Vector3.ZERO
	if is_chasing and player_in_range == null:
		var dir := player.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		target_vel = dir * move_speed
		sprite.flip_h = dir.x < 0.0   # Si tu arte mira al lado contrario, invierte la comparación

	velocity.x = move_toward(velocity.x, target_vel.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, acceleration * delta)

	move_and_slide()

func _update_detection() -> void:
	# Por si el jugador aún no existía cuando nació el enemigo
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		is_chasing = false
		return

	var dist := global_position.distance_to(player.global_position)
	if not is_chasing and dist <= detection_range:
		is_chasing = true
	elif is_chasing and dist > lose_range:
		is_chasing = false

func take_damage(amount: float):
	if is_dead:
		return
	current_health -= amount
	_flash_hit()
	if current_health <= 0:
		die()

func die():
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
	if is_instance_valid(player_in_range) and player_in_range.has_method("recibir_dano"):
		player_in_range.recibir_dano(attack_damage)

func _flash_hit() -> void:
	sprite.modulate = Color(1.8, 0.5, 0.5)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)
