class_name EnemyBullet
extends Area3D

var move_vector := Vector3.ZERO
var damage := 10.0
var lifetime := 3.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0xFFFFFFFF   # ajusta a las capas del jugador y las paredes si quieres

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.15
	col.shape = shape
	add_child(col)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.2)
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	sphere.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	add_child(mesh)

	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	global_position += move_vector * delta


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("enemies"):
		return
	if body.is_in_group("player") and body.has_method("recibir_dano"):
		body.recibir_dano(damage)
	queue_free()
