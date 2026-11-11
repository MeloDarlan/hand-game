extends Control

## Menu de protótipo: título e duas ações, sem música ou elementos adicionais.

const GAME_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_interface()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("25352f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(250.0, 0.0)
	layout.add_theme_constant_override("separation", 14)
	center.add_child(layout)

	var title := Label.new()
	title.text = "HAND DEFENSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("edf2df"))
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var play_button := _make_button("JOGAR", true)
	play_button.pressed.connect(_on_play_pressed)
	layout.add_child(play_button)

	var quit_button := _make_button("SAIR", false)
	quit_button.pressed.connect(_on_quit_pressed)
	layout.add_child(quit_button)


func _make_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(250.0, 44.0)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("477b50") if primary else Color("35463f")
	normal.set_corner_radius_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("5b925f") if primary else Color("46594f")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_color_override("font_color", Color("ffffff"))
	return button


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
