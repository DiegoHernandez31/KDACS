extends Area3D

const DOLL_PATH := "res://resources/models/Papsune_Miku.glb"

@export var model_scene: PackedScene
@export var spin_speed: float = 1.5
@export var bob_height: float = 0.08
# Vacío = se recoge al tocarlo. Si pones una acción (ej. "interact"), hay que presionarla cerca.
@export var pick_up_action: String = ""

var _model: Node3D
var _t := 0.0
var _player_inside: Node3D = null


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0xFFFFFFFF

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	col.shape = shape
	col.position.y = 0.3
	add_child(col)

	if model_scene == null and ResourceLoader.exists(DOLL_PATH):
		model_scene = load(DOLL_PATH)
	if model_scene:
		_model = model_scene.instantiate() as Node3D
		add_child(_model)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _model == null:
		return
	_t += delta
	_model.rotation.y += spin_speed * delta
	_model.position.y = 0.15 + sin(_t * 3.0) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if pick_up_action == "":
		_try_pick(body)
	else:
		_player_inside = body


func _on_body_exited(body: Node3D) -> void:
	if body == _player_inside:
		_player_inside = null


func _unhandled_input(event: InputEvent) -> void:
	if _player_inside and pick_up_action != "" and InputMap.has_action(pick_up_action) \
			and event.is_action_pressed(pick_up_action):
		_try_pick(_player_inside)


func _try_pick(body: Node3D) -> void:
	for h in get_tree().get_nodes_in_group("doll_holder"):
		if body.is_ancestor_of(h) and h.has_method("equip") and h.equip():
			queue_free()
			return
