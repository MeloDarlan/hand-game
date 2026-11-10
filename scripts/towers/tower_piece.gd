extends Grabbable
class_name TowerPiece

## Peça de torre: é um Grabbable físico, então a mão pode carregar, reposicionar
## e "soltar" usando exatamente as mecânicas já existentes.
## Visual construído com primitivas a partir de TowerData (tema provisório).

const PROJECTILE_GROUP := "projectiles"
const INVALID_CELL := Vector2i(-999, -999)

var data: TowerData
var is_placed := false
var cell := INVALID_CELL

## Distância da base da peça até o ponto onde a mão pinça o topo.
## Copiado de TowerData no setup; o export permite tuning no Remote.
@export var grip_height := 0.9

@export_group("Held Motion")
@export var motion_enabled := true
@export var motion_stiffness := 90.0
@export var motion_damping := 5
## Radianos de inclinação por unidade/s de velocidade da mão.
@export var motion_velocity_gain := 0.03
@export_range(0.0, 45.0) var motion_max_tilt_degrees := 20.0

var _head: Node3D
var _barrel_tip: Marker3D
var _cooldown := 0.0
var _built := false

var _swing := Vector2.ZERO
var _swing_velocity := Vector2.ZERO
var _prev_anchor := Vector3.ZERO
var _motion_initialized := false


func _ready() -> void:
	# A torre fica na layer grabbable para a mão poder pegá-la de volta.
	collision_layer = 2
	collision_mask = 0
	apply_color_override = false
	super()
	if data != null:
		_build()


func setup(tower_data: TowerData) -> void:
	data = tower_data
	if tower_data != null:
		grip_height = tower_data.grip_height
	if is_node_ready() and not _built:
		_build()


func get_grip_height() -> float:
	return grip_height


func _apply_hold_pose() -> void:
	if not is_instance_valid(_hold_point):
		return

	# A mão pinça o TOPO da peça. A base canônica pende abaixo do HoldPoint,
	# mas o visual pode balançar em torno dele (lag/inércia do mouse).
	var anchor := _hold_point.global_transform
	if not _motion_initialized:
		_prev_anchor = anchor.origin
		_swing = Vector2.ZERO
		_swing_velocity = Vector2.ZERO
		_motion_initialized = true

	_update_swing(anchor.origin)

	var visual_basis := anchor.basis
	if motion_enabled and _swing.length_squared() > 0.000001:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			var camera_right := camera.global_transform.basis.x.normalized()
			var camera_back := camera.global_transform.basis.z.normalized()
			var swing_basis := Basis(camera_right, _swing.y) * Basis(camera_back, _swing.x)
			visual_basis = swing_basis * visual_basis

	var visual_base := anchor.origin + visual_basis * Vector3(0.0, -get_grip_height(), 0.0)
	global_transform = Transform3D(visual_basis, visual_base)


func _update_swing(anchor_origin: Vector3) -> void:
	var delta := maxf(get_process_delta_time(), 0.0001)
	var velocity := (anchor_origin - _prev_anchor) / delta
	_prev_anchor = anchor_origin

	if not motion_enabled:
		_swing = Vector2.ZERO
		_swing_velocity = Vector2.ZERO
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var camera_right := camera.global_transform.basis.x.normalized()
	var camera_up := camera.global_transform.basis.y.normalized()
	var screen_velocity := Vector2(velocity.dot(camera_right), velocity.dot(camera_up))

	var max_tilt := deg_to_rad(motion_max_tilt_degrees)
	var target := (-screen_velocity * motion_velocity_gain).limit_length(max_tilt)

	# Mola/amortecimento: inclina ao mover e volta ao upright ao parar.
	var acceleration := (target - _swing) * motion_stiffness - _swing_velocity * motion_damping
	_swing_velocity += acceleration * delta
	_swing += _swing_velocity * delta
	_swing = _swing.limit_length(max_tilt)


func place(target_cell: Vector2i, world_position: Vector3) -> void:
	is_placed = true
	cell = target_cell
	# Teleporta com o corpo ativo e força o estado no physics server; congelar
	# antes fazia o corpo voltar para o transform antigo no tick seguinte.
	freeze = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_motion_initialized = false
	_swing = Vector2.ZERO
	_swing_velocity = Vector2.ZERO
	global_position = world_position
	rotation = Vector3.ZERO
	PhysicsServer3D.body_set_state(
		get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM,
		global_transform
	)
	freeze = true
	_cooldown = 0.0


func _process(delta: float) -> void:
	if not is_placed or data == null:
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	var target := _find_target()

	if target != null and _head != null:
		var to := target.global_position - global_position
		var desired := atan2(to.x, to.z)
		_head.rotation.y = lerp_angle(_head.rotation.y, desired, minf(1.0, 10.0 * delta))

	if target != null and _cooldown <= 0.0:
		_fire(target)
		_cooldown = maxf(data.fire_interval, 0.05)


func _find_target() -> Enemy:
	var best: Enemy = null
	var best_distance := data.attack_range

	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or not enemy.is_alive:
			continue
		var distance := Vector2(
			enemy.global_position.x - global_position.x,
			enemy.global_position.z - global_position.z
		).length()
		if distance <= best_distance:
			best = enemy
			best_distance = distance

	return best


func _fire(target: Enemy) -> void:
	var container := get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	var projectile := Projectile.new()
	container.add_child(projectile)
	var muzzle := _barrel_tip.global_position if _barrel_tip != null else global_position + Vector3(0.0, 0.85, 0.0)
	projectile.setup(muzzle, target, data)


func _build() -> void:
	if _built or data == null:
		return
	_built = true

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = data.color
	body_material.roughness = 0.5
	body_material.metallic = 0.15
	body_material.emission_enabled = true
	body_material.emission = data.color
	body_material.emission_energy_multiplier = 0.18

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.4
	base_mesh.height = 0.22
	base_mesh.radial_segments = 12
	base.mesh = base_mesh
	base.material_override = body_material
	base.position.y = 0.11
	add_child(base)

	var column := MeshInstance3D.new()
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.17
	column_mesh.bottom_radius = 0.24
	column_mesh.height = 0.5
	column_mesh.radial_segments = 10
	column.mesh = column_mesh
	column.material_override = body_material
	column.position.y = 0.47
	add_child(column)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 0.82
	add_child(_head)

	var head_mesh := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(0.34, 0.26, 0.34)
	head_mesh.mesh = head_box
	head_mesh.material_override = body_material
	_head.add_child(head_mesh)

	var barrel := MeshInstance3D.new()
	var barrel_box := BoxMesh.new()
	barrel_box.size = Vector3(0.12, 0.12, 0.42)
	barrel.mesh = barrel_box
	barrel.material_override = body_material
	barrel.position = Vector3(0.0, 0.0, 0.3)
	_head.add_child(barrel)

	_barrel_tip = Marker3D.new()
	_barrel_tip.position = Vector3(0.0, 0.0, 0.52)
	_head.add_child(_barrel_tip)

	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	collision.shape = shape
	collision.position.y = 0.45
	add_child(collision)
