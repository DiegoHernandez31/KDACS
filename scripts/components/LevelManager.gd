extends Node3D
# Gestor del nivel: la única condición de victoria es derrotar a todos los enemigos.
# El spawner llama a enemy_died() en este nodo (lo busca por el grupo "level_manager",
# que este script añade solo).

signal level_won

@export_file("*.tscn") var victory_scene_path: String = "res://scenes/ui/win.tscn"   # Tu escena de victoria
@export var victory_delay: float = 1.0                       # Pausa breve antes de cWWWambiar de escena

var _spawners: Array[Node] = []
var _won := false


func _ready() -> void:
	add_to_group("level_manager")

	# Esperamos un frame para que todos los spawners ya estén en su grupo
	await get_tree().process_frame
	for s in get_tree().get_nodes_in_group("spawner"):
		_spawners.append(s)


# La llama el spawner cada vez que muere un enemigo
func enemy_died() -> void:
	if _won or _spawners.is_empty() or _player_is_dead():
		return

	# Victoria = todos los spawners ya soltaron a sus enemigos y no queda ninguno vivo.
	# (No basta con mirar cuántos hay en pantalla: entre un spawn y otro hay 0.)
	for s in _spawners:
		if not is_instance_valid(s):
			continue
		if s.enemies_spawned < s.total_enemies_this_level or s.enemies_alive > 0:
			return

	_win()


func _win() -> void:
	_won = true
	level_won.emit()

	# Pequeña pausa para que se vea caer al último enemigo
	await get_tree().create_timer(victory_delay).timeout

	# Si el jugador murió justo en ese momento, manda la derrota
	if _player_is_dead():
		_won = false
		return

	if victory_scene_path == "":
		push_error("LevelManager: falta asignar victory_scene_path en el Inspector")
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # Por si tu escena de victoria tiene botones
	get_tree().change_scene_to_file(victory_scene_path)


func _player_is_dead() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return player != null and player.get("is_dead") == true
