extends Control

const MENU_SCENE := "res://scenes/ui/menu.tscn"  # <- ajusta a la ruta real de tu menú

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	$goToMenu.pressed.connect(_on_menu)
	$retry.pressed.connect(_on_retry)

func _on_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_retry() -> void:
	get_tree().change_scene_to_file(RhythmManager.ultimo_nivel)
