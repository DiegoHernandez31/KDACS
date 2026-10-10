extends Node3D

@export var bullet_scene: PackedScene
@onready var muzzle = $Muzzle

func shoot():
	if bullet_scene != null:
		var bullet = bullet_scene.instantiate()
		
		# MUY IMPORTANTE: Añadimos la bala al nivel general, NO como hija del arma.
		# Si fuera hija del arma, se movería junto con el jugador después de disparar.
		get_tree().current_scene.add_child(bullet)
		
		# Le pasamos a la bala la posición y rotación exacta del Muzzle
		bullet.global_transform = muzzle.global_transform
