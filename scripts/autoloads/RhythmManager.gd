extends Node

const GAME_OVER_SCENE := "res://scenes/ui/game_over.tscn"  # <- pon la ruta real de tu game_over.tscn

var ultimo_nivel: String = ""
var _game_over_activo := false
signal energia_agotada
var modo_tutorial := false

# --- CONFIGURACIÓN DE RITMO ---
var bpm: float = 140.0
var sec_por_beat: float
var posicion_cancion: float = 0.0
var tolerancia: float = 0.155 # Ventana de tiempo (en segundos) para acertar el beat

# --- CONFIGURACIÓN DE ENERGÍA ---
var energia_maxima: float = 100.0
var energia_actual: float = 100.0
var tasa_drenado: float = 7.0 # Cuánta energía se pierde por segundo
var enemigos_activos: int = 0  # Contador de enemigos en escena
var offset_cancion: float = 0.0

# --- REFERENCIAS ---
var audio_player: AudioStreamPlayer

func _ready():
	sec_por_beat = 60.0 / bpm
	energia_actual = energia_maxima

func configurar_musica(player: AudioStreamPlayer):
	audio_player = player
	energia_actual = energia_maxima
	enemigos_activos = 0
	_game_over_activo = false
	
	# Verificar si el stream tiene metadatos de BPM configurados
	if audio_player.stream and "bpm" in audio_player.stream:
		var stream_bpm = audio_player.stream.bpm
		if stream_bpm > 0:
			bpm = stream_bpm
			sec_por_beat = 60.0 / bpm
			print("RhythmManager: BPM automático detectado del audio -> ", bpm)
		else:
			print("RhythmManager (ADVERTENCIA): El audio tiene 0 BPM en sus metadatos. Usando fallback de -> ", bpm)
	else:
		print("RhythmManager (ADVERTENCIA): Formato de audio sin propiedad BPM. Usando fallback de -> ", bpm)
		
	audio_player.play()

func _process(delta):
	if not audio_player or not audio_player.playing:
		return
		
	# Ahora restamos también el offset de la canción para alinear el primer golpe
	posicion_cancion = audio_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency() - offset_cancion
	
	if enemigos_activos > 0:
		energia_actual -= tasa_drenado * delta
		if energia_actual <= 0:
			_game_over()

# --- LÓGICA DE VALIDACIÓN ---

# Se llama cuando la bala choca con el enemigo
func registrar_exito():
	# Eliminamos el chequeo de es_en_beat() aquí adentro. 
	# El ritmo ya se evaluó en el momento exacto en que el jugador hizo CLIC para disparar.
	# Si la bala llegó hasta aquí y golpeó, es un acierto puro.
	energia_actual = min(energia_actual + 15.0, energia_maxima) 
	print("¡EXCELENTE! Diste en el blanco.")
	
func ganar_energia(rollEnergyBonus):
	# Eliminamos el chequeo de es_en_beat() aquí adentro. 
	# El ritmo ya se evaluó en el momento exacto en que el jugador hizo CLIC para disparar.
	# Si la bala llegó hasta aquí y golpeó, es un acierto puro.
	energia_actual = min(energia_actual + rollEnergyBonus, energia_maxima) 
	print("¡EXCELENTE! Diste en el blanco.")

func perder_energia(cantidad: float):
	energia_actual -= cantidad
	if energia_actual <= 0:
		_game_over()

# Se llama cuando el jugador dispara fuera de ritmo o golpea una pared
func registrar_fallo(motivo: String = "desconocido"):
	energia_actual -= 8.0
	print("¡FALLASTE! motivo: ", motivo)
	if energia_actual <= 0:
		_game_over()

# --- LÓGICA DE VALIDACIÓN ---

func get_posicion_cancion() -> float:
	if not audio_player or not audio_player.playing:
		return 0.0
	return audio_player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		- offset_cancion

func es_en_beat() -> bool:
	var pos = get_posicion_cancion()
	var beat_f = pos / sec_por_beat
	var desfase = (beat_f - round(beat_f)) * sec_por_beat  # negativo = temprano, positivo = tarde
	print("t=%.2f | desfase=%+.3f s | tol=%.3f" % [pos, desfase, tolerancia])
	return abs(desfase) <= tolerancia

func _game_over() -> void:
	if modo_tutorial:
		energia_actual = energia_maxima
		energia_agotada.emit()
		return
	if _game_over_activo:
		return   # evita que se dispare varias veces (por eso salía 4 veces el mensaje)
	_game_over_activo = true
	enemigos_activos = 0
	audio_player = null   # el reproductor se destruye con el nivel
	ultimo_nivel = get_tree().current_scene.scene_file_path
	print("GAME OVER - Te quedaste sin energía")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file.call_deferred(GAME_OVER_SCENE)
