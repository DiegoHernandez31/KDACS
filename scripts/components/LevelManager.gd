extends Node3D

var total_enemies: int = 0
var enemies_killed: int = 0
var level_completed: bool = false

func _ready():
	add_to_group("level_manager")
	await get_tree().process_frame
	var spawners = get_tree().get_nodes_in_group("spawner")
	for s in spawners:
		total_enemies += s.total_enemies_this_level
	print("Misión: Sobrevivir a ", total_enemies, " enemigos.")
	print("Muertos: ", enemies_killed, "/", total_enemies)

func enemy_died():
	if level_completed:
		return

	enemies_killed += 1
	var remaining = total_enemies - enemies_killed
	print("Enemigo destruido. Quedan por eliminar: ", remaining)

	if enemies_killed >= total_enemies:
		level_completed = true
		print("¡NIVEL COMPLETADO! Has sobrevivido a las oleadas.")
