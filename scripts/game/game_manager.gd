extends Node
class_name GameManager

## Estado do jogo e economia. Fonte única de verdade de créditos/vidas/onda.

enum State { BUILD, WAVE, GAME_OVER }

const STARTING_CREDITS := 100
const STARTING_LIVES := 10
const DEBUG_CREDIT_GRANT := 100

var state: State = State.BUILD
var credits := STARTING_CREDITS
var lives := STARTING_LIVES

@onready var _hud: GameHUD = %HUD
@onready var _waves: WaveManager = %WaveManager
@onready var _board: Board = %Board


func _ready() -> void:
	_hud.start_wave_pressed.connect(_try_start_wave)
	_hud.restart_pressed.connect(_restart)
	_waves.wave_started.connect(_on_wave_started)
	_waves.wave_cleared.connect(_on_wave_cleared)
	_waves.all_waves_cleared.connect(_on_all_waves_cleared)
	_waves.enemy_killed.connect(_on_enemy_killed)
	_waves.enemy_leaked.connect(_on_enemy_leaked)
	_refresh()


func can_afford(cost: int) -> bool:
	return credits >= cost


func spend(cost: int) -> bool:
	if credits < cost:
		return false
	credits -= cost
	_refresh()
	return true


func add_credits(amount: int) -> void:
	credits += amount
	_refresh()


func _refresh() -> void:
	_board.rotation_enabled = state == State.BUILD
	_hud.set_credits(credits)
	_hud.set_lives(lives)
	_hud.set_wave(_waves.get_current_wave_number(), _waves.get_wave_count())
	_hud.set_start_enabled(state == State.BUILD and _waves.has_next_wave())


func _try_start_wave() -> void:
	if state != State.BUILD or not _waves.has_next_wave():
		return
	_waves.start_next_wave()


func _on_wave_started(_index: int) -> void:
	state = State.WAVE
	_refresh()


func _on_wave_cleared(_index: int, bonus: int) -> void:
	if state == State.GAME_OVER:
		return
	add_credits(bonus)
	state = State.BUILD
	_refresh()


func _on_all_waves_cleared() -> void:
	if state == State.GAME_OVER:
		return
	state = State.GAME_OVER
	_refresh()
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("level_complete", 0.9)
	_hud.show_game_over(true)


func _on_enemy_killed(reward: int) -> void:
	if state == State.GAME_OVER:
		return
	add_credits(reward)


func _on_enemy_leaked(base_damage: int) -> void:
	if state == State.GAME_OVER:
		return

	lives = maxi(lives - base_damage, 0)
	_refresh()

	if lives <= 0:
		state = State.GAME_OVER
		_waves.stop()
		_refresh()
		_hud.show_game_over(false)


func _restart() -> void:
	get_tree().reload_current_scene()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Reinicia a fase em qualquer estado (BUILD, WAVE ou GAME_OVER). Compara
	# também physical_keycode para layouts/IME que não preenchem keycode.
	if event.keycode == KEY_R or event.physical_keycode == KEY_R:
		# Marca o input antes do reload: a cena pode ser liberada no restart e
		# get_viewport() ficaria nulo depois.
		get_viewport().set_input_as_handled()
		_restart()
		return

	match event.keycode:
		KEY_SPACE:
			_try_start_wave()
			get_viewport().set_input_as_handled()
		KEY_F2:
			if OS.is_debug_build():
				add_credits(DEBUG_CREDIT_GRANT)
				get_viewport().set_input_as_handled()
