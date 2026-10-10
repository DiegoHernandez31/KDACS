extends Node3D
## Tutorial guiado de Project Dancin' Potato.
## Se adjunta al nodo raíz de tutorial.tscn. Crea toda su interfaz por código.
## Requiere los parches en RhythmManager.gd (modo_tutorial) y player.gd (locked_actions).

# --- Escenas ---
@export_file("*.tscn") var level_1_scene: String = ""
@export_file("*.tscn") var main_menu_scene: String = "res://scenes/ui/menu.tscn"
@export var enemy_scene: PackedScene

# --- Ajustes de los pasos ---
@export var spawn_radius: float = 7.0       # Distancia a la que aparecen los enemigos
@export var key_hold_time: float = 0.25     # Segundos que hay que mantener cada tecla (WASD)
@export var mouse_goal: float = 900.0       # Píxeles de movimiento del mouse para el paso de apuntar
@export var beat_streak_goal: int = 3       # Disparos / golpes seguidos en ritmo
@export var roll_beat_goal: int = 2         # Rolls en ritmo necesarios

const DEFAULT_ENEMY_SCENE := "res://scenes/characters/enemy.tscn"
const ALL_ACTIONS := ["shoot", "drop", "roll", "jump"]
const LOCK_ALL: Array = ["shoot", "drop", "roll", "jump"]
const LOCK_ONLY_DROP: Array = ["shoot", "roll", "jump"]    # Solo soltar / lanzar / recoger
const LOCK_ONLY_SHOOT: Array = ["drop", "roll", "jump"]    # Solo disparar
const LOCK_ONLY_JUMP: Array = ["shoot", "drop", "roll"]    # Solo saltar
const LOCK_ONLY_ROLL: Array = ["shoot", "drop", "jump"]    # Solo rodar
const LOCK_SHOOT_DROP: Array = ["roll", "jump"]            # Soltar el arma y golpear
const LOCK_NONE: Array = []

const MELEE_HINT_DROP := "Primero suelta tu arma: clic derecho, un toque rápido."
const KEY_NAME_ES := {"Space": "Espacio"}

const COLOR_OK := Color(0.4, 1.0, 0.5)
const COLOR_HINT := Color(1.0, 0.9, 0.3)
const COLOR_CHIP_OFF := Color(0.25, 0.27, 0.33)

var beat_timer: Control
var energy_bar: Control

var _player = null            # Sin tipo a propósito: usamos propiedades de player.gd
var _aim_pivot: Node3D

var _steps: Array = []
var _idx := -1
var _step_time := 0.0
var _advancing := false
var _finished := false
var _default_hint := ""
var _enter_pressed := false
var _step_marker := false
var _force_marker := false
var _highlight_target: Control = null

# Estado por paso
var _dir_time := {"ui_up": 0.0, "ui_left": 0.0, "ui_down": 0.0, "ui_right": 0.0}
var _mouse_travel := 0.0
var _drop_invalid := false
var _beat_streak := 0
var _roll_beat_count := 0
var _melee_armed := true
var _cam_seen := {"camera1": false, "camera2": false, "camera3": false}
var _kills := 0
var _kills_goal := 0
var _energy_notices := 0

# Interfaz
var _ui: CanvasLayer
var _top: PanelContainer
var _title: Label
var _text: Label
var _hint: Label
var _chips: HBoxContainer
var _cam_chips: HBoxContainer
var _chip_styles := {}
var _banner: PanelContainer
var _banner_label: Label
var _banner_tween: Tween
var _highlight: Panel
var _menu_layer: CanvasLayer
var _menu_msg: Label
var _marker: MeshInstance3D


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_error("Tutorial: no se encontró al jugador (grupo 'player').")
		set_process(false)
		set_process_input(false)
		return

	_aim_pivot = _player.get_node_or_null("AimPivot")
	beat_timer = get_node_or_null("BeatTimer")
	energy_bar = get_node_or_null("ProgressBar")
	if enemy_scene == null:
		enemy_scene = load(DEFAULT_ENEMY_SCENE)

	RhythmManager.modo_tutorial = true
	RhythmManager.energia_actual = RhythmManager.energia_maxima
	RhythmManager.enemigos_activos = 0
	RhythmManager.energia_agotada.connect(_on_energia_agotada)

	_build_ui()
	_build_steps()
	_set_camera_locked(true)   # Las teclas de cámara se desbloquean en su paso
	_go_to(0)


func _exit_tree() -> void:
	RhythmManager.modo_tutorial = false
	if RhythmManager.energia_agotada.is_connected(_on_energia_agotada):
		RhythmManager.energia_agotada.disconnect(_on_energia_agotada)


func _process(delta: float) -> void:
	_update_marker(delta)
	_update_highlight()
	if _finished or _advancing or _idx < 0 or _idx >= _steps.size():
		return
	_step_time += delta
	var check: Callable = _steps[_idx]["check"]
	if check.call(delta):
		_complete_step()


func _input(event: InputEvent) -> void:
	if _finished:
		return

	if event is InputEventMouseMotion and _current_id() == "aim":
		_mouse_travel += event.relative.length()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_enter_pressed = true

	if event.is_action_pressed("shoot"):
		var id := _current_id()
		if id == "beat" and _has_weapon():
			_register_beat_shot()
		elif id == "melee" and not _has_weapon():
			# Mismas condiciones que usa el jugador para dar el golpe
			if _player.melee_cooldown_timer <= 0.0 and not _player.is_rolling:
				_register_punch()

	if event.is_action_pressed("roll") and _current_id() == "roll_beat":
		if _player.can_roll():
			_register_roll()

	if _current_id() == "camera":
		for action in _cam_seen:
			if event.is_action_pressed(action):
				_cam_seen[action] = true


# =====================================================================
#  PASOS
# =====================================================================

func _build_steps() -> void:
	var jump_key := _key_name("jump")
	var roll_key := _key_name("roll")
	var cam1_key := _key_name("camera1")
	var cam2_key := _key_name("camera2")
	var cam3_key := _key_name("camera3")
	_steps = [
		{
			"id": "move",
			"text": "Muévete con W, A, S y D",
			"hint": "Mantén cada tecla un momento: se iluminan al cumplirse.",
			"locks": LOCK_ALL,
			"chips": true,
			"enter": _enter_move,
			"check": _check_move,
		},
		{
			"id": "jump",
			"text": "Salta con %s" % jump_key,
			"hint": "Úsalo para moverte por el escenario.",
			"locks": LOCK_ONLY_JUMP,
			"check": _check_jump,
		},
		{
			"id": "aim",
			"text": "Mueve el mouse para apuntar",
			"hint": "Tu personaje siempre mira hacia la mira. Muévela alrededor de él.",
			"locks": LOCK_ALL,
			"enter": _enter_aim,
			"check": _check_aim,
		},
		{
			"id": "camera",
			"text": "Cambia de cámara con las teclas %s, %s y %s" % [cam1_key, cam2_key, cam3_key],
			"hint": "Prueba las tres vistas. En la vista 3 el mouse queda fijo en el centro y con él mueves la cámara; Esc vuelve a la vista 1.",
			"locks": LOCK_ALL,
			"cam_chips": true,
			"enter": _enter_camera,
			"check": _check_camera,
		},
		{
			"id": "drop",
			"text": "Haz clic derecho, un solo toque sin mantener, para soltar tu arma",
			"hint": "Toque rápido: si mantienes el botón, la lanzarás.",
			"locks": LOCK_ONLY_DROP,
			"enter": _enter_drop,
			"check": _check_drop,
		},
		{
			"id": "pickup1",
			"text": "Tranquilo, puedes tomar tu arma dando clic derecho nuevamente estando cerca de ella",
			"hint": "Acércate a la flecha amarilla y haz clic derecho.",
			"locks": LOCK_ONLY_DROP,
			"marker": true,
			"check": _check_pickup,
		},
		{
			"id": "throw",
			"text": "Ahora mantén el clic derecho y suéltalo para lanzar tu arma hacia la mira",
			"hint": "Mantén el botón un instante y suéltalo. ¡El arma lanzada hace daño!",
			"locks": LOCK_ONLY_DROP,
			"check": _check_throw,
		},
		{
			"id": "pickup2",
			"text": "Recoge tu arma otra vez",
			"hint": "Acércate a la flecha amarilla y haz clic derecho.",
			"locks": LOCK_ONLY_DROP,
			"marker": true,
			"check": _check_pickup,
		},
		{
			"id": "pendulum",
			"text": "Este es el péndulo: cada vez que la bola cruza el centro del círculo es un beat",
			"hint": "Disparar, golpear y rodar solo cuentan si los haces justo en ese momento.\nPulsa ENTER para continuar.",
			"locks": LOCK_ALL,
			"highlight": "beat",
			"check": _check_manual,
		},
		{
			"id": "bar",
			"text": "Esta es tu barra de energía",
			"hint": "Acertar en el beat la recupera, fallar la baja, y con enemigos cerca se va drenando sola. Si llega a 0, pierdes.\nPulsa ENTER para continuar.",
			"locks": LOCK_ALL,
			"highlight": "bar",
			"check": _check_manual,
		},
		{
			"id": "beat",
			"text": "Muévete al ritmo: dispara con clic izquierdo justo cuando la bola cruce el centro",
			"hint": "",
			"locks": LOCK_ONLY_SHOOT,
			"highlight": "beat",
			"enter": _enter_beat,
			"check": _check_beat,
		},
		{
			"id": "roll",
			"text": "Rueda con %s para esquivar" % roll_key,
			"hint": "Mientras ruedas eres invulnerable: úsalo para escapar de los golpes. Muévete en una dirección y pulsa la tecla.",
			"locks": LOCK_ONLY_ROLL,
			"check": _check_roll,
		},
		{
			"id": "roll_beat",
			"text": "Ahora rueda en ritmo: pulsa %s justo cuando la bola cruce el centro" % roll_key,
			"hint": "",
			"locks": LOCK_ONLY_ROLL,
			"highlight": "beat",
			"enter": _enter_roll_beat,
			"check": _check_roll_beat,
		},
		{
			"id": "melee",
			"text": "Sin arma también puedes pelear cuerpo a cuerpo, pero haces menos daño que con las balas",
			"hint": "",
			"locks": LOCK_SHOOT_DROP,
			"highlight": "beat",
			"enter": _enter_melee,
			"check": _check_melee,
		},
		{
			"id": "pickup3",
			"text": "Recoge tu arma de nuevo para el combate",
			"hint": "Acércate a la flecha amarilla y haz clic derecho.",
			"locks": LOCK_ONLY_DROP,
			"marker": true,
			"check": _check_pickup,
		},
		{
			"id": "enemy1",
			"text": "Derrota a tu primer enemigo",
			"hint": "Dispara o golpea en el beat. ¡Cuidado con su ataque!",
			"locks": LOCK_NONE,
			"enter": _enter_enemy1,
			"check": _check_kills,
		},
		{
			"id": "wave",
			"text": "¡Muy bien! Ahora derrota a 3 enemigos más",
			"hint": "",
			"locks": LOCK_NONE,
			"enter": _enter_wave,
			"check": _check_kills,
		},
	]


func _go_to(i: int) -> void:
	_idx = i
	_advancing = false
	_step_time = 0.0
	_enter_pressed = false
	_force_marker = false
	_step_marker = false
	_highlight_target = null
	_hint.add_theme_color_override("font_color", COLOR_HINT)

	if i >= _steps.size():
		_show_final_menu()
		return

	var s: Dictionary = _steps[i]
	_set_locks(s["locks"])
	_title.text = "TUTORIAL"
	_text.text = s["text"]
	_default_hint = s.get("hint", "")
	_hint.text = _default_hint
	_chips.visible = s.get("chips", false)
	_cam_chips.visible = s.get("cam_chips", false)
	_step_marker = s.get("marker", false)
	match s.get("highlight", ""):
		"beat":
			_highlight_target = beat_timer
		"bar":
			_highlight_target = energy_bar

	var enter: Callable = s.get("enter", Callable())
	if enter.is_valid():
		enter.call()


func _complete_step() -> void:
	_advancing = true
	_force_marker = false
	_hint.text = "¡Bien hecho!"
	_hint.add_theme_color_override("font_color", COLOR_OK)
	if _current_id() == "camera":
		_hint.text = "¡Bien hecho! Volvemos a la vista 1."
		_return_to_default_view()
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(_go_to.bind(_idx + 1))


func _current_id() -> String:
	if _idx >= 0 and _idx < _steps.size():
		return _steps[_idx]["id"]
	return ""


# --- Paso: moverse con WASD ---------------------------------------------

func _enter_move() -> void:
	for k in _dir_time:
		_dir_time[k] = 0.0


func _check_move(delta: float) -> bool:
	var all_done := true
	for action in _dir_time:
		if Input.is_action_pressed(action):
			_dir_time[action] += delta
		var done: bool = _dir_time[action] >= key_hold_time
		var style: StyleBoxFlat = _chip_styles[action]
		if done:
			style.bg_color = COLOR_OK
		elif Input.is_action_pressed(action):
			style.bg_color = COLOR_HINT
		else:
			style.bg_color = COLOR_CHIP_OFF
		all_done = all_done and done
	return all_done


# --- Paso: apuntar con el mouse -----------------------------------------

func _enter_aim() -> void:
	_mouse_travel = 0.0


func _check_aim(_delta: float) -> bool:
	_hint.text = "Progreso: %d%%" % int(clampf(_mouse_travel / mouse_goal, 0.0, 1.0) * 100.0)
	return _mouse_travel >= mouse_goal


# --- Paso: cambiar de cámara (teclas 1, 2 y 3) --------------------------

func _enter_camera() -> void:
	for action in _cam_seen:
		_cam_seen[action] = false
	_set_camera_locked(false)   # Desde aquí el jugador puede cambiar de vista


func _check_camera(_delta: float) -> bool:
	var all_seen := true
	for action in _cam_seen:
		var style: StyleBoxFlat = _chip_styles[action]
		style.bg_color = COLOR_OK if _cam_seen[action] else COLOR_CHIP_OFF
		all_seen = all_seen and _cam_seen[action]
	return all_seen


# --- Paso: soltar el arma (toque rápido) --------------------------------

func _enter_drop() -> void:
	_drop_invalid = false


func _check_drop(_delta: float) -> bool:
	if _has_weapon():
		if _drop_invalid:
			_drop_invalid = false
			_force_marker = false
			_hint.text = _default_hint
		return false
	var dw := _find_dropped_weapon()
	if dw == null:
		return false
	if dw.thrown:
		# Mantuvo el botón: fue un lanzamiento, no un toque
		_drop_invalid = true
		_force_marker = true
		_hint.text = "Eso fue un lanzamiento. Recoge tu arma y suéltala con un solo toque, sin mantener."
		return false
	if _drop_invalid:
		_force_marker = true
		return false
	return true


# --- Pasos: recoger el arma ---------------------------------------------

func _check_pickup(_delta: float) -> bool:
	return _has_weapon()


# --- Paso: lanzar el arma (mantener clic derecho) -----------------------

func _check_throw(_delta: float) -> bool:
	if _has_weapon():
		if _force_marker:
			_force_marker = false
			_hint.text = _default_hint
		return false
	var dw := _find_dropped_weapon()
	if dw == null:
		return false
	if dw.thrown:
		return true
	# La soltó con un toque: debe recogerla y mantener el botón
	_force_marker = true
	_hint.text = "Eso fue un toque rápido. Recoge tu arma y esta vez MANTÉN el clic derecho antes de soltarlo."
	return false


# --- Paso: saltar --------------------------------------------------------

func _check_jump(_delta: float) -> bool:
	return not _player.is_on_floor() and _player.velocity.y > 1.0


# --- Pasos: rodar (esquivar y rodar en ritmo) ---------------------------

func _check_roll(_delta: float) -> bool:
	return _player.is_rolling


func _enter_roll_beat() -> void:
	_roll_beat_count = 0
	_hint.text = "Un roll en el beat te devuelve energía. Rolls en ritmo: 0/%d" % roll_beat_goal


func _register_roll() -> void:
	if RhythmManager.es_en_beat():
		_roll_beat_count += 1
		_hint.text = "¡En ritmo! Rolls en ritmo: %d/%d" % [_roll_beat_count, roll_beat_goal]
	else:
		_hint.text = "Fuera de ritmo. Espera a que la bola cruce el centro y vuelve a intentarlo."


func _check_roll_beat(_delta: float) -> bool:
	return _roll_beat_count >= roll_beat_goal


# --- Paso: pelear sin arma (golpe cuerpo a cuerpo) ----------------------

func _enter_melee() -> void:
	_beat_streak = 0
	_melee_armed = true
	_hint.text = MELEE_HINT_DROP


func _check_melee(_delta: float) -> bool:
	var armed := _has_weapon()
	if armed != _melee_armed:
		_melee_armed = armed
		_beat_streak = 0
		if armed:
			_hint.text = MELEE_HINT_DROP
		else:
			_hint.text = "Ahora golpea con clic izquierdo, en ritmo. Racha: 0/%d" % beat_streak_goal
	return not armed and _beat_streak >= beat_streak_goal


func _register_punch() -> void:
	if RhythmManager.es_en_beat():
		_beat_streak += 1
		_hint.text = "¡Golpe en ritmo! Racha: %d/%d" % [_beat_streak, beat_streak_goal]
	else:
		_beat_streak = 0
		_hint.text = "Fuera de ritmo, la racha vuelve a 0. Golpea cuando la bola cruce el centro."


# --- Pasos informativos (péndulo y barra) -------------------------------

func _check_manual(_delta: float) -> bool:
	return _enter_pressed and _step_time >= 1.0


# --- Paso: disparar en ritmo --------------------------------------------

func _enter_beat() -> void:
	_beat_streak = 0
	_hint.text = "Racha: 0/%d" % beat_streak_goal


func _register_beat_shot() -> void:
	if RhythmManager.es_en_beat():
		_beat_streak += 1
		_hint.text = "¡En ritmo! Racha: %d/%d" % [_beat_streak, beat_streak_goal]
	else:
		_beat_streak = 0
		_hint.text = "Fuera de ritmo, la racha vuelve a 0. Espera a que la bola cruce el centro."


func _check_beat(_delta: float) -> bool:
	return _beat_streak >= beat_streak_goal


# --- Pasos: enemigos ----------------------------------------------------

func _enter_enemy1() -> void:
	_kills = 0
	_kills_goal = 1
	_hint.text = "Derrotados: 0/1"
	_spawn_enemies(1)


func _enter_wave() -> void:
	_kills = 0
	_kills_goal = 3
	_hint.text = "Derrotados: 0/3"
	_spawn_enemies(3)


func _check_kills(_delta: float) -> bool:
	return _kills >= _kills_goal


func _spawn_enemies(count: int) -> void:
	if enemy_scene == null:
		push_error("Tutorial: no se pudo cargar la escena del enemigo.")
		return
	var base := randf() * TAU
	for i in count:
		var enemy: Node3D = enemy_scene.instantiate()
		add_child(enemy)
		var angle := base + TAU * i / count
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		enemy.global_position = _player.global_position + dir * spawn_radius + Vector3(0.0, 0.5, 0.0)
		if enemy.has_signal("died"):
			enemy.connect("died", _on_enemy_died, CONNECT_ONE_SHOT)
		else:
			enemy.tree_exited.connect(_on_enemy_died, CONNECT_ONE_SHOT)


func _on_enemy_died() -> void:
	_kills += 1
	_hint.text = "Derrotados: %d/%d" % [_kills, _kills_goal]


# =====================================================================
#  UTILIDADES DEL JUGADOR
# =====================================================================

func _set_locks(locked: Array) -> void:
	var d := {}
	for a in ALL_ACTIONS:
		d[a] = locked.has(a)
	_player.locked_actions = d


# Nombre de la tecla asignada a una acción en el Mapa de Entrada
func _key_name(action: String) -> String:
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var code: Key = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
				var key_name := OS.get_keycode_string(code)
				return KEY_NAME_ES.get(key_name, key_name)
	return action.to_upper()


# Bloquea / desbloquea las teclas de cambio de vista (propiedad views_locked de cameraPlayer.gd)
func _set_camera_locked(locked: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.set("views_locked", locked)


func _return_to_default_view() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("_set_mode"):
		cam.call("_set_mode", 1)


func _has_weapon() -> bool:
	return _aim_pivot != null and _aim_pivot.get_node_or_null("Weapon") != null


func _find_dropped_weapon() -> DroppedWeapon:
	for n in get_tree().get_nodes_in_group("dropped_weapons"):
		if n is DroppedWeapon:
			return n
	return null


# =====================================================================
#  ENERGÍA A 0: en el tutorial no hay GameOver
# =====================================================================

func _on_energia_agotada() -> void:
	_energy_notices += 1
	if _energy_notices == 1:
		_show_banner("Tu energía llegó a 0. En una partida normal habrías muerto (GAME OVER), pero esto es un tutorial: aquí lo importante es aprender. Te la recargamos.", 7.0)
	else:
		_show_banner("Energía en 0 otra vez: en el juego real sería GAME OVER. Recargada porque es un tutorial.", 5.0)


func _show_banner(msg: String, seconds: float) -> void:
	_banner_label.text = msg
	_banner.visible = true
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(seconds)
	_banner_tween.tween_callback(func(): _banner.visible = false)


# =====================================================================
#  MENÚ FINAL
# =====================================================================

func _show_final_menu() -> void:
	_finished = true
	_top.visible = false
	_banner.visible = false
	_marker.visible = false
	_highlight.visible = false
	_set_locks(LOCK_ALL)

	# Oculta la mira propia de la cámara (el árbol se pausa, así que no se vuelve a mostrar)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var crosshair = cam.get("crosshair")
		if crosshair is CanvasItem:
			crosshair.visible = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_msg.text = ""
	_menu_layer.visible = true
	get_tree().paused = true


func _leave_to(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Tutorial: escena no válida: '%s'" % path)
		_menu_msg.text = "No se encontró esa escena. Asígnala en el Inspector del nodo Tutorial."
		return
	get_tree().paused = false
	RhythmManager.enemigos_activos = 0
	RhythmManager.energia_actual = RhythmManager.energia_maxima
	get_tree().change_scene_to_file(path)


# =====================================================================
#  AYUDAS VISUALES (flecha sobre el arma y marco sobre la UI)
# =====================================================================

func _update_marker(delta: float) -> void:
	var dw: DroppedWeapon = null
	if (_step_marker or _force_marker) and not _finished:
		dw = _find_dropped_weapon()
	if dw == null:
		_marker.visible = false
		return
	_marker.visible = true
	var bob := sin(Time.get_ticks_msec() / 1000.0 * 5.0) * 0.12
	_marker.global_position = dw.global_position + Vector3(0.0, 1.2 + bob, 0.0)
	_marker.rotate_y(delta * 3.0)


func _update_highlight() -> void:
	if _finished or _highlight_target == null or not is_instance_valid(_highlight_target):
		_highlight.visible = false
		return
	var xf := _highlight_target.get_global_transform()
	var r: Rect2 = (xf * Rect2(Vector2.ZERO, _highlight_target.size)).grow(10.0)
	_highlight.position = r.position
	_highlight.size = r.size
	_highlight.visible = true
	_highlight.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)


# =====================================================================
#  CONSTRUCCIÓN DE LA INTERFAZ (todo por código)
# =====================================================================

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)

	# --- Panel de instrucciones (arriba al centro) ---
	_top = _make_panel(Vector2(760, 0))
	_top.anchor_left = 0.5
	_top.anchor_right = 0.5
	_top.offset_top = 16
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ui.add_child(_top)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	_top.add_child(box)

	_title = _make_label(16, Color(0.7, 0.7, 0.75))
	box.add_child(_title)
	_text = _make_label(30, Color.WHITE)
	box.add_child(_text)
	_hint = _make_label(20, COLOR_HINT)
	box.add_child(_hint)

	_chips = HBoxContainer.new()
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.add_theme_constant_override("separation", 10)
	box.add_child(_chips)
	_chips.add_child(_make_chip("W", "ui_up"))
	_chips.add_child(_make_chip("A", "ui_left"))
	_chips.add_child(_make_chip("S", "ui_down"))
	_chips.add_child(_make_chip("D", "ui_right"))

	_cam_chips = HBoxContainer.new()
	_cam_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_cam_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cam_chips.add_theme_constant_override("separation", 10)
	box.add_child(_cam_chips)
	_cam_chips.add_child(_make_chip("%s\nIsométrica" % _key_name("camera1"), "camera1", Vector2(160, 84), 22))
	_cam_chips.add_child(_make_chip("%s\nShooter fija" % _key_name("camera2"), "camera2", Vector2(160, 84), 22))
	_cam_chips.add_child(_make_chip("%s\nShooter libre" % _key_name("camera3"), "camera3", Vector2(160, 84), 22))

	# --- Aviso inferior (energía en 0) ---
	_banner = _make_panel(Vector2(760, 0))
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 1.0
	_banner.anchor_bottom = 1.0
	_banner.offset_top = -28
	_banner.offset_bottom = -28
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.visible = false
	_ui.add_child(_banner)
	_banner_label = _make_label(22, Color(1.0, 0.75, 0.5))
	_banner.add_child(_banner_label)

	# --- Marco de resaltado para péndulo y barra ---
	_highlight = Panel.new()
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hl := StyleBoxFlat.new()
	hl.draw_center = false
	hl.border_color = COLOR_HINT
	hl.set_border_width_all(4)
	hl.set_corner_radius_all(12)
	_highlight.add_theme_stylebox_override("panel", hl)
	_highlight.visible = false
	_ui.add_child(_highlight)

	# --- Flecha 3D sobre el arma en el suelo ---
	var cone := CylinderMesh.new()
	cone.top_radius = 0.28
	cone.bottom_radius = 0.0
	cone.height = 0.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.no_depth_test = true
	cone.material = mat
	_marker = MeshInstance3D.new()
	_marker.mesh = cone
	_marker.visible = false
	add_child(_marker)

	# --- Menú final ---
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 100
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_layer.visible = false
	add_child(_menu_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(dim)

	var menu := _make_panel(Vector2(620, 0))
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 0.5
	menu.anchor_bottom = 0.5
	menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu_layer.add_child(menu)

	var mbox := VBoxContainer.new()
	mbox.add_theme_constant_override("separation", 16)
	menu.add_child(mbox)

	mbox.add_child(_make_label(36, Color.WHITE, "¡Tutorial completado!"))
	mbox.add_child(_make_label(22, Color(0.85, 0.85, 0.9), "Ya sabes moverte, apuntar, soltar y lanzar tu arma, y actuar al ritmo de la música. ¿Qué quieres hacer ahora?"))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	mbox.add_child(buttons)

	var btn_level := Button.new()
	btn_level.text = "Continuar al Nivel 1"
	btn_level.custom_minimum_size = Vector2(270, 56)
	btn_level.add_theme_font_size_override("font_size", 22)
	btn_level.pressed.connect(func(): _leave_to(level_1_scene))
	buttons.add_child(btn_level)

	var btn_menu := Button.new()
	btn_menu.text = "Volver al menú inicial"
	btn_menu.custom_minimum_size = Vector2(270, 56)
	btn_menu.add_theme_font_size_override("font_size", 22)
	btn_menu.pressed.connect(func(): _leave_to(main_menu_scene))
	buttons.add_child(btn_menu)

	_menu_msg = _make_label(18, Color(1.0, 0.5, 0.5))
	mbox.add_child(_menu_msg)


func _make_panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.85)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_label(font_size: int, color: Color, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_chip(letter: String, action: String, min_size := Vector2(64, 64), font_size := 32) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_CHIP_OFF
	sb.set_corner_radius_all(10)
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = letter
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	chip.add_child(lbl)
	_chip_styles[action] = sb
	return chip
