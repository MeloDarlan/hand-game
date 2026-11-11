extends Node3D
class_name Projectile

## Projétil simples: persegue o alvo por referência e acerta por distância.
## Parametrizado por TowerData, então existe uma cena/lógica só.

var _target: Enemy
var _target_position := Vector3.ZERO
var _damage := 10.0
var _speed := 12.0
var _slow_factor := 0.0
var _slow_duration := 0.0
var _life := 4.0
var _ready_to_fly := false


func setup(start_position: Vector3, target: Enemy, tower_data: TowerData) -> void:
	global_position = start_position
	_target = target
	_target_position = _chest_position()
	_damage = tower_data.damage
	_speed = maxf(tower_data.projectile_speed, 0.1)
	_slow_factor = tower_data.slow_factor
	_slow_duration = tower_data.slow_duration
	_build(tower_data.color)
	_ready_to_fly = true


func _build(color: Color) -> void:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh_instance.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _process(delta: float) -> void:
	if not _ready_to_fly:
		return

	_life -= delta
	if _life <= 0.0:
		queue_free()
		return

	if is_instance_valid(_target) and _target.is_alive:
		_target_position = _chest_position()

	var to := _target_position - global_position
	var step := _speed * delta
	if to.length() <= maxf(step, 0.2):
		_hit()
		return

	global_position += to.normalized() * step


func _chest_position() -> Vector3:
	if not is_instance_valid(_target) or _target.data == null:
		return _target_position
	return _target.global_position + Vector3(0.0, _target.data.height * 0.5, 0.0)


func _hit() -> void:
	if is_instance_valid(_target) and _target.is_alive:
		_target.take_damage(_damage)
		if _slow_factor > 0.0 and _slow_duration > 0.0:
			_target.apply_slow(_slow_factor, _slow_duration)
	queue_free()
