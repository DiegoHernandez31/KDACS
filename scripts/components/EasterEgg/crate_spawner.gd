extends Node3D

@export var crate_scene: PackedScene       # arrastra aquí tu crate.tscn
@export var spawn_y_offset: float = 0.0    # ajusta si la caja queda enterrada o flotando

func _init() -> void:
	print("[CrateSpawner] _init: el nodo existe")

func _ready() -> void:
	print("[CrateSpawner] _ready ejecutado")

	# Esperamos un frame: el padre aún está armando el nivel y no deja añadir hijos todavía
	await get_tree().process_frame

	if crate_scene == null:
		print("[CrateSpawner] ¡ADVERTENCIA: falta asignar crate_scene!")
		return

	# Si ya existe una caja única en el mapa, no creamos otra
	if not get_tree().get_nodes_in_group("unique_crate").is_empty():
		print("[CrateSpawner] Ya existe una caja única en el mapa")
		return

	var points: Array[Node3D] = []
	for child in get_children():
		if child is Marker3D:
			points.append(child as Node3D)

	if points.is_empty():
		print("[CrateSpawner] ¡ADVERTENCIA: no hay Marker3D hijos del CrateSpawner!")
		return

	var point: Node3D = points.pick_random()
	var crate := crate_scene.instantiate() as Node3D
	if crate == null:
		print("[CrateSpawner] ¡ERROR: la raíz de crate.tscn no es un Node3D!")
		return

	get_parent().add_child(crate)
	crate.global_position = point.global_position + Vector3.UP * spawn_y_offset
	print("[CrateSpawner] caja creada en ", crate.global_position)
