extends RigidBody3D
class_name Grabbable

## Objeto flutuante que pode ser pego pela mão.
## Enquanto segurado, congela a física e acompanha o HoldPoint da mão.

signal grabbed(body: Grabbable)
signal released(body: Grabbable, velocity: Vector3)

@export var apply_color_override := true

@export var color: Color = Color(0.2, 0.85, 1.0):
	set(value):
		color = value
		if is_node_ready():
			_apply_color()

var is_held := false

var _hold_point: Node3D
var _spawn_transform: Transform3D
var _saved_layer := 0
var _saved_mask := 0


func _ready() -> void:
	_spawn_transform = global_transform
	gravity_scale = 0.0
	linear_damp = 2.5
	angular_damp = 3.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	_apply_color()


func sync_to_hold_point() -> void:
	if not is_held:
		return

	if not is_instance_valid(_hold_point):
		release()
		return

	# Sem interpolação: cola exatamente na mão no mesmo frame.
	global_transform = _hold_point.global_transform

func grab(point: Node3D) -> void:
	if is_held:
		return

	is_held = true
	_hold_point = point
	_saved_layer = collision_layer
	_saved_mask = collision_mask

	collision_layer = 0
	collision_mask = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# Entra já na mão, sem deslizar da posição antiga até o HoldPoint.
	global_transform = point.global_transform

	grabbed.emit(self)


func release(velocity: Vector3 = Vector3.ZERO) -> void:
	if not is_held:
		return

	is_held = false
	_hold_point = null

	collision_layer = _saved_layer
	collision_mask = _saved_mask
	freeze = false
	sleeping = false
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO

	released.emit(self, velocity)


func reset_to_spawn() -> void:
	if is_held:
		return

	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _spawn_transform

func _apply_color() -> void:
	if not apply_color_override:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	material.metallic = 0.05
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.35
	for mesh in find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
