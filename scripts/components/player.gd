extends CharacterBody3D

@onready var camera = get_viewport().get_camera_3d()
@onready var sprite = $Sprite3D # Asegúrate de que el nombre coincida con tu nodo
@onready var aim_pivot = $AimPivot

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

# Obtiene la gravedad global del proyecto
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta):
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Saltar
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Obtener dirección del input y normalizar a 3D (Z es adelante/atrás)
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
	# Llamamos a la función de apuntado
	_aim_at_mouse()
	
	move_and_slide()

func _aim_at_mouse():
	# 1. Obtener la posición 2D del mouse en la pantalla
	var mouse_pos = get_viewport().get_mouse_position()
	
	# 2. Proyectar un rayo 3D desde la cámara
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	# 3. Crear un plano imaginario a la altura exacta del jugador (Eje Y)
	var floor_plane = Plane(Vector3.UP, global_position.y)
	
	# 4. Encontrar el punto 3D exacto donde el rayo choca con el plano
	var intersection = floor_plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection != null:
		var look_target = Vector3(intersection.x, global_position.y, intersection.z)
		
		# Evitar errores si el mouse está exactamente encima del centro del jugador
		if not global_position.is_equal_approx(look_target):
			# Rotar el CharacterBody3D para que mire al target
			aim_pivot.look_at(look_target, Vector3.UP)
			sprite.look_at(look_target, Vector3.UP)
			
			# EXTRA: Como estás usando un Sprite3D con Billboard, el sprite siempre mirará 
			# a la cámara. Para dar feedback visual, podemos voltear el sprite (flip_h) 
			# si el mouse está a la izquierda o derecha.
			if intersection.x < global_position.x:
				sprite.flip_h = true  # Mira a la izquierda
			else:
				sprite.flip_h = false # Mira a la derecha

# (Añade esto dentro de tu script del CharacterBody3D, por ejemplo, debajo de _aim_at_mouse())

func _unhandled_input(_event):
	# Si presionamos el clic izquierdo...
	if Input.is_action_just_pressed("shoot"):
		# Verificamos si el AimPivot tiene el arma equipada (por ahora sí)
		if aim_pivot.has_node("Weapon"):
			var weapon = aim_pivot.get_node("Weapon")
			weapon.shoot()
