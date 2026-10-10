extends Area3D

@export var speed: float = 20.0
@export var lifetime: float = 2.0

func _ready():
	# Destruye la bala después de 'lifetime' segundos para no saturar la memoria
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta):
	# La bala avanza hacia adelante en base a su propia rotación (-Z local)
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(collider):
	# Ejemplo dentro de tu lógica de disparo o proyectil:
	if collider.has_method("take_damage"):
		RhythmManager.registrar_exito()
		collider.take_damage(1)
	else:
		RhythmManager.registrar_fallo()
	queue_free() # Destruye la bala al chocar
