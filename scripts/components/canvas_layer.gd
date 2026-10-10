extends CanvasLayer

@export var escala_base := 1.0
@onready var crosshair: Sprite2D = $Crosshair

func _ready():
	layer = 100
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _process(_delta):
	crosshair.position = get_viewport().get_mouse_position()

	# Opcional: la mira "late" con el beat
	var spb := RhythmManager.sec_por_beat
	var pulso := 0.0
	if spb > 0.0:
		var p := fposmod(RhythmManager.posicion_cancion, spb) / spb
		pulso = pow(1.0 - p, 4.0) * 0.25
	crosshair.scale = Vector2.ONE * escala_base * (1.0 + pulso)
