extends Node3D
class_name ArmJelly

## Deformação tipo jelly no antebraço.
## A simulação roda aqui; o shader aplica os offsets nos vértices do antebraço.

const SEGMENTS := 6
const JELLY_SHADER := preload("res://resources/jelly_arm.gdshader")

@export_group("Simulation")
@export var stiffness := 70.0
@export var damping := 8.0
@export var coupling := 25.0
@export var inertia_gain := 0.8
@export var max_offset := 0.55
@export var max_accel := 60.0
@export_range(1, 6) var substeps := 6

@export_group("Look")
@export var bend_amount := 1.25
@export var squash_amount := 0.1
@export var albedo_color := Color(0.8, 0.061, 0.036, 1.0)
@export var roughness_value := 0.45

var _mesh: MeshInstance3D
var _material: ShaderMaterial

var _offsets := PackedVector3Array()
var _velocities := PackedVector3Array()
var _accel := Vector3.ZERO
var _stretch := 0.0

var _prev_world_position := Vector3.ZERO
var _prev_world_velocity := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	var parent := get_parent()
	if parent == null:
		push_warning("ArmJelly: sem parent.")
		set_process(false)
		return

	_mesh = parent.get_node_or_null("Model/Armature/Skeleton3D/Cube") as MeshInstance3D

	if _mesh == null:
		push_warning("ArmJelly: MeshInstance3D 'Cube' não encontrado.")
		set_process(false)
		return

	_material = ShaderMaterial.new()
	_material.shader = JELLY_SHADER

	const JELLY_START_Y := 0.90
	var aabb := _mesh.get_aabb()
	var arm_length := maxf(JELLY_START_Y - aabb.position.y, 0.1)

	_material.set_shader_parameter("wrist_y", JELLY_START_Y)
	_material.set_shader_parameter("arm_length", arm_length)
	_material.set_shader_parameter("bend_amount", bend_amount)
	_material.set_shader_parameter("squash_amount", 1.0)
	_material.set_shader_parameter("stretch", 0.0)
	_material.set_shader_parameter("albedo_color", albedo_color)
	_material.set_shader_parameter("roughness_value", roughness_value)

	_offsets.resize(SEGMENTS)
	_velocities.resize(SEGMENTS)
	for i in SEGMENTS:
		_offsets[i] = Vector3.ZERO
		_velocities[i] = Vector3.ZERO

	_mesh.material_override = _material

	_prev_world_position = _mesh.global_position
	_prev_world_velocity = Vector3.ZERO
	_initialized = true


func _process(delta: float) -> void:
	if not _initialized or _mesh == null or _material == null:
		return

	var dt := maxf(delta, 0.0001)
	var world_position := _mesh.global_position
	var world_velocity := (world_position - _prev_world_position) / dt
	var world_accel := (world_velocity - _prev_world_velocity) / dt

	_prev_world_position = world_position
	_prev_world_velocity = world_velocity

	# Converte a aceleração do mundo para o espaço local da malha.
	var local_accel := _mesh.global_transform.basis.inverse() * world_accel
	local_accel = local_accel.limit_length(max_accel)
	_accel = _accel.lerp(local_accel, 1.0 - exp(-14.0 * delta))

	var target_stretch := clampf(
		-_accel.y / maxf(max_accel, 0.001),
		-1.0,
		1.0
	) * squash_amount
	_stretch = lerp(_stretch, target_stretch, 1.0 - exp(-12.0 * delta))

	var step := delta / float(maxi(substeps, 1))
	for _i in maxi(substeps, 1):
		_simulate_step(step)

	_material.set_shader_parameter("jelly_offsets", _offsets)
	_material.set_shader_parameter("stretch", _stretch)
	_material.set_shader_parameter("bend_amount", bend_amount)


func _simulate_step(step: float) -> void:
	var lateral := Vector3(_accel.x, 0.0, _accel.z)

	for i in range(1, SEGMENTS):
		var offset := _offsets[i]
		var velocity := _velocities[i]

		var force := -stiffness * offset
		force -= damping * velocity
		force += coupling * (_offsets[i - 1] - offset)
		force -= lateral * inertia_gain * (float(i) / float(SEGMENTS - 1))

		velocity += force * step
		offset += velocity * step

		if offset.length() > max_offset:
			offset = offset.normalized() * max_offset
			velocity *= 0.5

		_offsets[i] = offset
		_velocities[i] = velocity

	_offsets[0] = Vector3.ZERO
	_velocities[0] = Vector3.ZERO
