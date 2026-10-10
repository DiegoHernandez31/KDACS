extends Node3D

@export var enemy_scene: PackedScene # Aquí arrastrarás tu Enemy.tscn
@export var total_enemies_this_level: int = 10
@export var spawn_interval: float = 2.0
@export var spawn_y_offset: float = 0.05 # Pequeño margen para que no nazcan clavados en el piso

var enemies_spawned: int = 0
var enemies_alive: int = 0
var spawn_points: Array[Node3D] = []

@onready var spawn_timer: Timer = $SpawnTimer


func _ready() -> void:
	add_to_group("spawner")

	# Recolectamos todos los Marker3D para usarlos como puntos de spawn
	for child in get_children():
		if child is Marker3D:
			spawn_points.append(child)

	if spawn_points.is_empty():
		print("¡ADVERTENCIA: No hay Marker3D en el Spawner para posicionar enemigos!")
		return

	if enemy_scene == null:
		print("¡ADVERTENCIA: Falta asignar enemy_scene en el Spawner!")
		return

	# Conectamos el timer por código si no estaba conectado desde el editor
	if not spawn_timer.timeout.is_connected(_on_spawn_timer_timeout):
		spawn_timer.timeout.connect(_on_spawn_timer_timeout)

	spawn_timer.wait_time = spawn_interval
	spawn_timer.start()


func _on_spawn_timer_timeout() -> void:
	if enemies_spawned < total_enemies_this_level:
		spawn_enemy()
	else:
		spawn_timer.stop() # Ya salieron todos, detenemos el reloj


func spawn_enemy() -> void:
	if enemy_scene == null or spawn_points.is_empty():
		return

	var new_enemy := enemy_scene.instantiate() as Node3D

	if new_enemy == null or not new_enemy.has_signal("died"):
		push_error("enemy_scene debe ser un Node3D con la señal 'died'")
		if new_enemy:
			new_enemy.queue_free()
		return

	# Conectar la señal ANTES de añadirlo
	new_enemy.connect("died", _on_enemy_died)

	var point: Node3D = spawn_points.pick_random()

	# Primero add_child, después la posición
	get_parent().add_child(new_enemy)
	new_enemy.global_position = point.global_position + Vector3.UP * spawn_y_offset

	enemies_spawned += 1
	enemies_alive += 1
	print(name, " spawneó. Le quedan por salir: ", total_enemies_this_level - enemies_spawned)


func _on_enemy_died() -> void:
	enemies_alive -= 1

	var manager = get_tree().get_first_node_in_group("level_manager")
	if manager:
		manager.enemy_died()
