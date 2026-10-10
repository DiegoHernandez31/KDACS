extends TextureProgressBar

func _process(_delta):
	max_value = RhythmManager.energia_maxima
	value = RhythmManager.energia_actual
