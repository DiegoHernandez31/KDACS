class_name ExplosionFX
extends RefCounted
## Efecto de explosión reutilizable (sin escenas ni texturas, todo se crea por código).
##
## Uso desde cualquier script:
##   ExplosionFX.spawn(get_tree().current_scene, global_position + Vector3(0, 0.5, 0), 0.7)
##
## Parámetros:
##   parent     -> dónde se añade el efecto (usa la escena actual, NO el enemigo,
##                 porque el enemigo se borra y se llevaría el efecto con él)
##   pos        -> posición en el mundo
##   size       -> tamaño relativo (1.0 = el de la papa, 0.7 = más chico)
##   style      -> Style.ENEMY (polvo y pelo) o Style.PLAYER (fuego y trozos de papa)
##   with_light -> destello de luz (déjalo en false para enemigos si mueren muchos a la vez)

enum Style { PLAYER, ENEMY }

static func spawn(parent: Node, pos: Vector3, size: float = 1.0,
		style: Style = Style.ENEMY, with_light: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return

	# Colores según el estilo
	var fire_a := Color(1.0, 0.95, 0.5)
	var fire_b := Color(1.0, 0.35, 0.05)
	var chunk_a := Color(0.55, 0.32, 0.12)      # Trozos de papa
	var chunk_b := Color(0.45, 0.25, 0.1)
	var smoke_a := Color(0.3, 0.3, 0.3, 0.8)
	var smoke_b := Color(0.12, 0.12, 0.12, 0.6)
	var extra_bits := false
	if style == Style.ENEMY:
		chunk_a = Color(0.85, 0.65, 0.35)       # Pedazos de pelo/pelusa
		chunk_b = Color(0.7, 0.5, 0.28)
		smoke_a = Color(0.88, 0.82, 0.7, 0.8)   # Nube de polvo
		smoke_b = Color(0.7, 0.65, 0.55, 0.5)
		extra_bits = true

	# 1) Destello de luz (opcional)
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.2)
		light.light_energy = 10.0 * size
		light.omni_range = 7.0 * size
		parent.add_child(light)
		light.global_position = pos
		var lt := light.create_tween()
		lt.tween_property(light, "light_energy", 0.0, 0.4)
		lt.tween_callback(light.queue_free)

	# 2) Onda expansiva
	var wave := MeshInstance3D.new()
	var wave_mesh := SphereMesh.new()
	wave_mesh.radius = 0.5
	wave_mesh.height = 1.0
	var wave_mat := StandardMaterial3D.new()
	wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_mat.albedo_color = Color(1.0, 0.8, 0.4, 0.7)
	wave_mesh.material = wave_mat
	wave.mesh = wave_mesh
	parent.add_child(wave)
	wave.global_position = pos
	wave.scale = Vector3.ONE * 0.3 * size
	var wt := wave.create_tween().set_parallel(true)
	wt.tween_property(wave, "scale", Vector3.ONE * 5.0 * size, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	wt.tween_property(wave_mat, "albedo_color:a", 0.0, 0.35)
	wt.chain().tween_callback(wave.queue_free)

	# 3) Partículas: bola de fuego, trozos, humo/polvo y (enemigos) pedacitos claros
	var n_fire := maxi(6, roundi(45.0 * size))
	var n_chunk := maxi(4, roundi(16.0 * size))
	var n_smoke := maxi(4, roundi(18.0 * size))
	_burst(parent, pos, fire_a, fire_b, n_fire, 0.18 * size, 3.0 * size, 8.0 * size, 0.7, -2.0)
	_burst(parent, pos, chunk_a, chunk_b, n_chunk, 0.14 * size, 4.0 * size, 9.0 * size, 1.3, -18.0)
	_burst(parent, pos, smoke_a, smoke_b, n_smoke, 0.25 * size, 1.0 * size, 3.0 * size, 1.0, 1.0)
	if extra_bits:
		_burst(parent, pos, Color(0.97, 0.95, 0.88), Color(0.9, 0.88, 0.8),
			maxi(3, roundi(7.0 * size)), 0.09 * size, 4.0 * size, 9.0 * size, 1.2, -18.0)

static func _burst(parent: Node, pos: Vector3, color_a: Color, color_b: Color, amount: int,
		radius: float, speed_min: float, speed_max: float, life: float, grav_y: float) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0.0, grav_y, 0.0)
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4

	# Degradado de color: inicio -> medio -> transparente
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, color_a)
	g.set_offset(1, 1.0)
	g.set_color(1, Color(color_b, 0.0))
	g.add_point(0.4, color_b)
	p.color_ramp = g

	# Se encogen al final
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = c

	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	parent.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
