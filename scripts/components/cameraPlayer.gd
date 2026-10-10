extends Camera3D

@export var target: Node3D
@export var follow_speed: float = 5.0
@export var offset: Vector3 = Vector3(0, 3, 5) # X (lados), Y (altura), Z (distancia)

func _physics_process(delta):
	if target:
		# Calcula la posición ideal sumando el offset a la posición del jugador
		var target_position = target.global_position + offset
		
		# Mueve suavemente la cámara actual hacia la posición ideal
		global_position = global_position.lerp(target_position, follow_speed * delta)
