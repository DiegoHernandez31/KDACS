extends Node3D

@export var bullet_scene: PackedScene
@onready var muzzle = $Muzzle

func shoot(direction: Vector3 = Vector3.ZERO):
	if bullet_scene == null:
		return
	var bullet = bullet_scene.instantiate()

	# La bala va al nivel general, NO como hija del arma
	get_tree().current_scene.add_child(bullet)

	# Sale desde el Muzzle, pero con la dirección de apuntado (no la inclinación del arma)
	var bullet_basis = muzzle.global_transform.basis
	if direction != Vector3.ZERO:
		bullet_basis = Basis.looking_at(direction, Vector3.UP)
	bullet.global_transform = Transform3D(bullet_basis, muzzle.global_position)
	bullet.reset_physics_interpolation()   # Evita un parpadeo en el primer frame de la bala
