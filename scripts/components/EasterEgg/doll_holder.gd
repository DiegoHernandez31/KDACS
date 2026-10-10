extends Node

const DOLL_PATH := "res://resources/models/Papsune_Miku.glb"
const SOUND_PATH := "res://ruta/a/Mikudayo.wav"    # pon la ruta real de tu audio

@export var doll_scene: PackedScene
@export var sound: AudioStream
@export var hand_bone_name: String = "hand.L"      # la mano contraria al arma
@export var held_offset := Vector3(0, 0.1, 0)
@export var held_rotation := Vector3(0, 90, 180)
@export var held_scale: float = 0.6
@export var action_name: String = "squeak_doll"
@export var default_key: Key = KEY_M

var has_doll := false
var _doll: Node3D
var _audio: AudioStreamPlayer


func _ready() -> void:
	add_to_group("doll_holder")
	if doll_scene == null and ResourceLoader.exists(DOLL_PATH):
		doll_scene = load(DOLL_PATH)
	if sound == null and ResourceLoader.exists(SOUND_PATH):
		sound = load(SOUND_PATH)
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		var ev := InputEventKey.new()
		ev.physical_keycode = default_key
		InputMap.action_add_event(action_name, ev)


# Devuelve true si el muñeco quedó equipado
func equip() -> bool:
	if has_doll or doll_scene == null:
		return false

	var found := get_parent().find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_warning("DollHolder: no encontré un Skeleton3D en el jugador")
		return false
	var skeleton := found[0] as Skeleton3D

	var idx := skeleton.find_bone(hand_bone_name)
	if idx == -1:
		idx = skeleton.find_bone(hand_bone_name.replace(".", "_"))
	if idx == -1:
		var names := []
		for i in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(i))
		push_warning("DollHolder: no encontré el hueso '%s'. Huesos disponibles: %s" % [hand_bone_name, names])
		return false

	var att := BoneAttachment3D.new()
	skeleton.add_child(att)
	att.bone_name = skeleton.get_bone_name(idx)

	_doll = doll_scene.instantiate() as Node3D
	att.add_child(_doll)
	_doll.position = held_offset
	_doll.rotation_degrees = held_rotation
	_doll.scale = Vector3.ONE * held_scale

	_audio = AudioStreamPlayer.new()
	_audio.stream = sound
	_audio.max_polyphony = 1                        # el audio no se encima
	add_child(_audio)

	has_doll = true
	return true


func _unhandled_input(event: InputEvent) -> void:
	if has_doll and event.is_action_pressed(action_name):
		_squeak()


func _squeak() -> void:
	if _audio and _audio.stream:
		_audio.play()
	var s := Vector3.ONE * held_scale
	var t := create_tween()
	t.tween_property(_doll, "scale", s * Vector3(1.25, 0.75, 1.25), 0.06)
	t.tween_property(_doll, "scale", s, 0.12).set_trans(Tween.TRANS_BACK)
