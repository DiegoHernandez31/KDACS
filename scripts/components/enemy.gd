extends CharacterBody3D

signal died

@export var max_health: int = 100
@export var move_speed: float = 3.0 
@export var attack_damage: int = 10
@export var attack_speed: float = 1.0 # Tiempo entre cada golpe (segundos)

var current_health: int
var player: Node3D 
var player_in_range: Node3D = null # Almacena al jugador si está a rango de ataque
var attack_timer: float = 0.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	current_health = max_health
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta):
	# 1. Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Lógica de Persecución y Ataque
	if player != null:
		if player_in_range != null:
			# El jugador ESTÁ en el área de ataque. Nos detenemos.
			velocity.x = 0
			velocity.z = 0
			
			# Lógica de daño periódico
			attack_timer -= delta
			if attack_timer <= 0.0:
				if player_in_range.has_method("take_damage"):
					player_in_range.take_damage(attack_damage)
				attack_timer = attack_speed # Reiniciamos el temporizador
		else:
			# El jugador NO ESTÁ a rango. Lo perseguimos.
			var direction = (player.global_position - global_position)
			direction.y = 0 
			direction = direction.normalized()
			
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			
			# Preparamos el ataque para golpear de inmediato al alcanzarlo
			attack_timer = 0.0
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	# 3. Mover
	move_and_slide()

# --- SEÑALES DEL ATTACK AREA ---
func _on_attack_area_body_entered(body):
	if body.is_in_group("player"):
		print("¡Jugador detectado por el área! Deteniendo enemigo.")
		player_in_range = body 

func _on_attack_area_body_exited(body):
	if body.is_in_group("player"):
		print("Jugador salió del área. Reanudando persecución.")
		player_in_range = null

# --- SISTEMA DE SALUD DEL ENEMIGO ---
# enemy.gd (solo emite, NO llama al LevelManager)
var is_dead: bool = false

func die():
	if is_dead:
		return
	is_dead = true
	died.emit()
	queue_free()
func take_damage(amount: int):
	if is_dead:
		return
	current_health -= amount
	if current_health <= 0:
		die()
