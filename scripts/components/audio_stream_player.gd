extends AudioStreamPlayer

func _ready():
	# Usamos 'self' porque este mismo nodo ES el reproductor de audio
	RhythmManager.configurar_musica(self)
