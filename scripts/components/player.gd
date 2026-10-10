extends CharacterBody3D

@onready var camera = get_viewport().get_camera_3d()
@onready var sprite = $Sprite3D
@onready var aim_pivot = $AimPivot

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _physics_process(delta):
	# Aplicar gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Saltar
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Obtener dirección del input y normalizar a 3D
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Llamamos a la función de apuntado antes de mover
	_aim_at_mouse()
	
	# Llamar move_and_slide() solo una vez al final
	move_and_slide()

func _aim_at_mouse():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_direction = camera.project_ray_normal(mouse_pos)
	
	var floor_plane = Plane(Vector3.UP, global_position.y)
	var intersection = floor_plane.intersects_ray(ray_origin, ray_direction)
	
	if intersection != null:
		# Usamos aim_pivot.global_position.y en lugar de global_position.y para el target
		# Esto asegura que el pivot siempre mire en un plano perfectamente horizontal (solo rota en el eje Y)
		var look_target = Vector3(intersection.x, aim_pivot.global_position.y, intersection.z)
		
		# Validamos respecto a la posición del pivot, no del root
		if not aim_pivot.global_position.is_equal_approx(look_target):
			aim_pivot.look_at(look_target, Vector3.UP)
			sprite.look_at(look_target, Vector3.UP)
			
			# NOTA: Eliminamos sprite.look_at(). Si usas Billboard, esto causa "backflips".
			# El código flip_h a continuación es suficiente para que el personaje "mire" izquierda/derecha.
			if intersection.x < global_position.x:
				sprite.flip_h = true  # Mira a la izquierda
			else:
				sprite.flip_h = false # Mira a la derecha

func _unhandled_input(_event):
	if Input.is_action_just_pressed("shoot"):
		if aim_pivot.has_node("Weapon"):
			var weapon = aim_pivot.get_node("Weapon")
			weapon.shoot()
			
