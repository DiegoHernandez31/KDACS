extends Control

@export var amplitud: float = deg_to_rad(40.0)   # Qué tanto se abre el péndulo
@export var radio_objetivo: float = 22.0         # Círculo central (zona del beat)
@export var radio_bola: float = 12.0
@export var color_riel: Color = Color(1, 1, 1, 0.25)
@export var color_bola: Color = Color.WHITE
@export var color_acierto: Color = Color(0.3, 1.0, 0.4)
@export var estelas: int = 5                     # Cuántas "sombras" deja la bola
@export var tiempo_estela: float = 0.03          # Separación en segundos entre sombras

func _process(_delta):
	queue_redraw()

# Ángulo = 0 en cada beat, alterna de lado en cada uno
func _angulo(t: float, spb: float) -> float:
	return amplitud * sin(PI * t / spb)

func _draw():
	var spb = RhythmManager.sec_por_beat
	if spb <= 0.0:
		return

	var t = RhythmManager.posicion_cancion
	var pivote = Vector2(size.x / 2.0, 0.0)
	var largo = size.y - radio_objetivo - 4.0

	# Posición de la bola para un ángulo dado (0 = abajo, centro)
	var pos = func(a: float) -> Vector2:
		return pivote + Vector2(sin(a), cos(a)) * largo

	# Qué tan cerca estamos del beat (con signo: negativo = antes, positivo = después)
	var beat_f = t / spb
	var desfase = (beat_f - round(beat_f)) * spb
	var en_beat = abs(desfase) <= RhythmManager.tolerancia
	var cercania = 1.0 - clampf(abs(desfase) / (spb * 0.5), 0.0, 1.0)

	# Riel por donde se mueve la bola
	draw_arc(pivote, largo, PI / 2.0 - amplitud, PI / 2.0 + amplitud, 32, color_riel, 2.0)

	# Círculo objetivo en el centro: pulsa al acercarse al beat
	var centro = pos.call(0.0)
	var radio_pulso = radio_objetivo * (1.0 + 0.25 * pow(cercania, 4.0))
	var color_anillo = color_acierto if en_beat else Color(1, 1, 1, 0.6)
	draw_arc(centro, radio_pulso, 0.0, TAU, 48, color_anillo, 3.0)

	# Estelas (posiciones anteriores de la bola)
	for i in range(estelas, 0, -1):
		var ti = t - i * tiempo_estela
		var alpha = 0.35 * (1.0 - float(i) / (estelas + 1))
		draw_circle(pos.call(_angulo(ti, spb)), radio_bola * 0.8, Color(color_bola, alpha))

	# Cuerda y bola
	var p_bola = pos.call(_angulo(t, spb))
	draw_line(pivote, p_bola, Color(1, 1, 1, 0.5), 2.0)
	draw_circle(pivote, 4.0, Color(1, 1, 1, 0.8))
	draw_circle(p_bola, radio_bola, color_acierto if en_beat else color_bola)
