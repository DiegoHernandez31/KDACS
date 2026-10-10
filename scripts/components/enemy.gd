extends CharacterBody3D

@onready var sprite = $Sprite3D

const SPEED = 5.0
var health: int = 7 # Cuántos tiros aguanta el enemigo

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# 1. Agregamos al enemigo al grupo por código (así la bala lo reconoce)
	add_to_group("enemies") 
	
	RhythmManager.enemigos_activos += 1

func _physics_process(delta):
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	move_and_slide()

# 2. Creamos la función que la Bala intentará llamar al chocar
func take_damage(damage):
	health -= damage
	
	# Aquí a futuro podrías reproducir un sonido o poner el sprite en rojo
	
	if health <= 0:
		die()

func die():
	RhythmManager.enemigos_activos -= 1
	queue_free() # Destruye al enemigo
