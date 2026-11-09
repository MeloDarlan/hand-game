extends Node3D

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		for child in get_children():
			if child.has_method("reset_to_spawn"):
				child.reset_to_spawn()
		get_viewport().set_input_as_handled()
