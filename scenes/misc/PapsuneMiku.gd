class_name DollPickup
extends Area3D

const DOLL_PATH := "res://resources/models/Papsune_Miku.glb"

@export var model_scene: PackedScene
@export var spin_speed: float = 1.5
@export var bob_height: float = 0.08

var _model: Node3D
var _t := 0.0


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


func _process(delta: float) -> void:
	if _model == null:
		return
	_t += delta
	_model.rotation.y += spin_speed * delta
	_model.position.y = 0.15 + sin(_t * 3.0) * bob_height


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	for h in get_tree().get_nodes_in_group("doll_holder"):
		if body.is_ancestor_of(h) and h.has_method("equip") and h.equip():
			queue_free()
			return
