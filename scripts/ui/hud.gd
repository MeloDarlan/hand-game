extends CanvasLayer
class_name GameHUD

## HUD/toolbar. Não conhece regras: só emite intenções e recebe valores.

signal tower_selected(index: int)
signal start_wave_pressed
signal restart_pressed

@onready var _credits_label: Label = $Root/Margin/Layout/TopBar/CreditsLabel
@onready var _lives_label: Label = $Root/Margin/Layout/TopBar/LivesLabel
@onready var _wave_label: Label = $Root/Margin/Layout/TopBar/WaveLabel
@onready var _start_button: Button = $Root/Margin/Layout/TopBar/StartButton
@onready var _toolbar: HBoxContainer = $Root/Margin/Layout/Toolbar
@onready var _game_over: CenterContainer = $Root/GameOver
@onready var _game_over_title: Label = $Root/GameOver/Panel/Layout/Title
@onready var _game_over_message: Label = $Root/GameOver/Panel/Layout/Message
@onready var _restart_button: Button = $Root/GameOver/Panel/Layout/RestartButton

var _tower_defs: Array = []
var _buttons: Array[Button] = []
var _credits := 0


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_game_over.visible = false


func setup_towers(tower_defs: Array) -> void:
	_tower_defs = tower_defs
	for button in _buttons:
		button.queue_free()
	_buttons.clear()

	for i in _tower_defs.size():
		var tower := _tower_defs[i] as TowerData
		if tower == null:
			continue

		var button := Button.new()
		button.text = "%d · %s — %d" % [i + 1, tower.display_name, tower.cost]
		button.tooltip_text = tower.description
		button.custom_minimum_size = Vector2(185.0, 54.0)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 17)
		button.toggled.connect(_on_tower_button_toggled.bind(i))
		_toolbar.add_child(button)
		_buttons.append(button)

	set_selected(-1)
	set_credits(_credits)


func set_selected(index: int) -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == index)


func set_credits(value: int) -> void:
	_credits = value
	_credits_label.text = "Créditos: %d" % value
	for i in _buttons.size():
		var tower := _tower_defs[i] as TowerData
		if tower != null:
			_buttons[i].disabled = tower.cost > value


func set_lives(value: int) -> void:
	_lives_label.text = "Vidas: %d" % value


func set_wave(current: int, total: int) -> void:
	if current <= 0:
		_wave_label.text = "Onda: —/%d" % total
	else:
		_wave_label.text = "Onda: %d/%d" % [current, total]


func set_start_enabled(enabled: bool) -> void:
	_start_button.disabled = not enabled


func show_game_over(victory: bool) -> void:
	_game_over_title.text = "Você defendeu o núcleo!" if victory else "O núcleo caiu"
	_game_over_message.text = (
		"Todas as ondas foram eliminadas."
		if victory
		else "Os inimigos chegaram ao núcleo. Tente outra vez."
	)
	_game_over.visible = true


func _on_tower_button_toggled(_pressed: bool, index: int) -> void:
	# Emite nos dois estados: desmarcar o botão selecionado cancela a colocação.
	tower_selected.emit(index)


func _on_start_pressed() -> void:
	start_wave_pressed.emit()


func _on_restart_pressed() -> void:
	restart_pressed.emit()
