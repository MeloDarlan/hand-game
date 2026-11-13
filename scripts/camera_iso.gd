extends Camera3D
class_name IsoCamera

## Câmera isométrica ortográfica.

@export var yaw_degrees := 45.0
@export var pitch_degrees := 35.264
@export var distance := 30.0
@export var target := Vector3(0.0, -0.7, 0.0)
@export var ortho_size := 11.5


func _enter_tree() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = ortho_size
	near = 0.05
	far = 120.0
	current = true

	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * distance

	global_position = target + offset
	look_at(target, Vector3.UP)
