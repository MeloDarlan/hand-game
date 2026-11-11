extends Node3D
class_name Enemy

## Inimigo simples que segue os waypoints do tabuleiro.
## Não usa física: projéteis acertam por referência/distância.

signal died(enemy: Enemy)
signal leaked(enemy: Enemy)

const HEALTH_BAR_WIDTH := 0.8
const HEALTH_BAR_HEIGHT := 0.09

var data: EnemyData
var is_alive := true

var _health := 0.0
var _max_health := 1.0
var _waypoints := PackedVector3Array()
var _index := 0
var _slow_time := 0.0
var _speed_multiplier := 1.0

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _bar: MeshInstance3D
var _bar_material: StandardMaterial3D
var _built := false


func setup(enemy_data: EnemyData, waypoints: PackedVector3Array) -> void:
	data = enemy_data
	_waypoints = waypoints
	_max_health = maxf(data.max_health, 1.0)
	_health = _max_health
	_build()

	if _waypoints.size() > 0:
		global_position = _waypoints[0]
		_index = 1

	add_to_group("enemies")
	_update_bar()


func _build() -> void:
	if _built or data == null:
		return
	_built = true

	_material = StandardMaterial3D.new()
	_material.albedo_color = data.color
	_material.roughness = 0.55
	_material.emission_enabled = true
	_material.emission = data.color
	_material.emission_energy_multiplier = 0.25

	_mesh = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = data.radius
	capsule.height = maxf(data.height, data.radius * 2.05)
	_mesh.mesh = capsule
	_mesh.material_override = _material
	_mesh.position.y = data.height * 0.5
	add_child(_mesh)

	_bar_material = StandardMaterial3D.new()
	_bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bar_material.albedo_color = Color(0.35, 1.0, 0.45)

	var quad := QuadMesh.new()
	quad.size = Vector2(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
	_bar = MeshInstance3D.new()
	_bar.mesh = quad
	_bar.material_override = _bar_material
	_bar.position.y = data.height + 0.32
	add_child(_bar)


func _process(delta: float) -> void:
	if not is_alive:
		return
	_tick_slow(delta)
	_follow_path(delta)


func _tick_slow(delta: float) -> void:
	if _slow_time <= 0.0:
		return
	_slow_time = maxf(_slow_time - delta, 0.0)
	if _slow_time <= 0.0:
		_speed_multiplier = 1.0


func _follow_path(delta: float) -> void:
	if data == null or _index >= _waypoints.size():
		_leak()
		return

	var remaining := data.speed * _speed_multiplier * delta
	var last_direction := Vector3.ZERO
	while remaining > 0.0 and _index < _waypoints.size():
		var target := _waypoints[_index]
		var to := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
		var distance := to.length()
		if distance <= 0.0001:
			global_position = target
			_index += 1
			continue

		last_direction = to / distance
		if distance <= remaining:
			global_position = target
			remaining -= distance
			_index += 1
		else:
			global_position += last_direction * remaining
			remaining = 0.0

	if last_direction.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(last_direction.x, last_direction.z), minf(1.0, 12.0 * delta))

	if _index >= _waypoints.size():
		_leak()


func take_damage(amount: float) -> void:
	if not is_alive:
		return
	_health -= amount
	_update_bar()
	_flash()
	if _health <= 0.0:
		_die()


func apply_slow(factor: float, duration: float) -> void:
	if not is_alive or factor <= 0.0 or duration <= 0.0:
		return
	_speed_multiplier = clampf(1.0 - factor, 0.1, 1.0)
	_slow_time = maxf(_slow_time, duration)


func _update_bar() -> void:
	if _bar == null:
		return
	var ratio := clampf(_health / _max_health, 0.0, 1.0)
	_bar.scale.x = ratio
	_bar_material.albedo_color = Color(0.9, 0.2, 0.2).lerp(Color(0.35, 1.0, 0.45), ratio)


func _flash() -> void:
	if _material == null:
		return
	_material.emission_energy_multiplier = 1.2
	var tween := create_tween()
	tween.tween_property(_material, "emission_energy_multiplier", 0.25, 0.12)


func _die() -> void:
	if not is_alive:
		return
	is_alive = false
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("enemy_down", 0.75)
	died.emit(self)
	queue_free()


func _leak() -> void:
	if not is_alive:
		return
	is_alive = false
	leaked.emit(self)
	queue_free()
