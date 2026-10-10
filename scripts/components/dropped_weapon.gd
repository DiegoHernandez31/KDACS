
class_name DroppedWeapon
extends RigidBody3D

const THROW_DAMAGE := 5.0
const MIN_DAMAGE_SPEED := 3.0

var weapon: Node3D
var thrower: Node3D
var thrown := false
var thrown_time := 0.0

func _ready() -> void:
	lock_rotation = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func setup(w: Node3D, from: Node3D) -> void:
	thrower = from
	weapon = w
	add_to_group("dropped_weapons")

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)

	add_child(weapon)
	weapon.transform = Transform3D.IDENTITY

	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	if is_instance_valid(thrower):
		add_collision_exception_with(thrower)
		get_tree().create_timer(0.4).timeout.connect(_restore_collision)

func _restore_collision() -> void:
	if is_instance_valid(thrower):
		remove_collision_exception_with(thrower)

func launch(direction: Vector3, speed: float) -> void:
	thrown = true
	thrown_time = 0.0
	gravity_scale = 0.25
	lock_rotation = true
	angular_velocity = Vector3.ZERO
	linear_velocity = direction.normalized() * speed

func _physics_process(delta: float) -> void:
	if not thrown:
		return

	thrown_time += delta

	if thrown_time > 0.8 or linear_velocity.length() < MIN_DAMAGE_SPEED:
		_end_throw()

func _on_body_entered(body: Node) -> void:
	if not thrown or body == thrower:
		return

	if body.has_method("take_damage"):
		body.take_damage(THROW_DAMAGE)

	_end_throw()

func _end_throw() -> void:
	thrown = false
	gravity_scale = 1.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = true
