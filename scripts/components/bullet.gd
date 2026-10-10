extends Area3D

@export var speed: float = 20.0
@export var lifetime: float = 2.0

func _ready():
	# Destruye la bala después de 'lifetime' segundos para no saturar la memoria
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	
	# Conectamos la señal de colisión (asegúrate de que en el nodo la señal 'body_entered' esté conectada a esta función)
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	# La bala avanza hacia adelante en base a su propia rotación (-Z local)
	global_position += -global_transform.basis.z * speed * delta

func _on_body_entered(_body):
	# Aquí a futuro pondremos: if body.has_method("take_damage")...
	queue_free() # Destruye la bala al chocar
