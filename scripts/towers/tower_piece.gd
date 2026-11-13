extends Grabbable
class_name TowerPiece

const PROJECTILE_GROUP := "projectiles"
const INVALID_CELL := Vector2i(-999, -999)

var data: TowerData
var is_placed := false
var cell := INVALID_CELL

@export var grip_height := 0.9

@export_group("Held Motion")
@export var motion_enabled := true
@export var motion_stiffness := 90.0
@export var motion_damping := 5
@export var motion_velocity_gain := 0.03
@export_range(0.0, 45.0) var motion_max_tilt_degrees := 20.0

@export_group("Drop")
## Distância que o visual da peça é afastado da câmera ao cair, para passar por
## trás do board. A câmera é ortográfica, então isso não desloca a peça na tela.
@export var drop_depth_offset := 16.0

var _head: Node3D
var _barrel_tip: Marker3D
var _squash_pivot: Node3D
var _anticipation_tween: Tween
var _cooldown := 0.0
var _built := false

var _swing := Vector2.ZERO
var _swing_velocity := Vector2.ZERO
var _prev_anchor := Vector3.ZERO
var _motion_initialized := false

var _drop_start_position := Vector3.ZERO
var _drop_start_basis := Basis.IDENTITY
var _drop_start_scale := Vector3.ONE
var _drop_down := Vector3.DOWN
var _drop_spin_axis := Vector3.BACK
var _drop_spin := 0.0
var _drop_distance := 0.0
var _drop_away := Vector3.FORWARD

func _ready() -> void:
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


## Move somente o visual (SquashPivot) em espaço global, sem tocar no
## RigidBody3D. Usado pelo Board durante o giro; o corpo é teleportado uma única
## vez quando a animação termina.
func sync_visual_to(world_transform: Transform3D) -> void:
	if _squash_pivot == null:
		return
	_squash_pivot.global_transform = world_transform


func reset_visual_transform() -> void:
	if _squash_pivot == null:
		return
	_squash_pivot.position = Vector3.ZERO
	_squash_pivot.rotation = Vector3.ZERO


## Soltou a peça fora do tabuleiro: ela escapa da mão, cai atrás do board
## (afastando-se da câmera), gira, encolhe/apaga e é removida.
## Só o visual (SquashPivot) se move; o corpo congelado é liberado no fim.
func play_drop_off_board(duration := 0.7, fall_distance := 7.0, spin_degrees := 540.0) -> void:
	is_placed = false
	cell = INVALID_CELL
	_cancel_anticipation()
	_swing = Vector2.ZERO
	_swing_velocity = Vector2.ZERO
	_motion_initialized = false

	# Sai do pick/combate e não colide mais com nada.
	collision_layer = 0
	collision_mask = 0
	freeze = true
	sleeping = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	reset_visual_transform()
	if _squash_pivot == null:
		queue_free()
		return

	var camera := get_viewport().get_camera_3d()
	_drop_down = Vector3.DOWN
	_drop_spin_axis = Vector3.BACK
	_drop_away = Vector3.FORWARD
	if camera != null:
		_drop_down = -camera.global_transform.basis.y.normalized()
		_drop_spin_axis = camera.global_transform.basis.z.normalized()
		# Câmera olha para -Z local; afastar-se dela é seguir o -basis.z.
		_drop_away = -camera.global_transform.basis.z.normalized()

	# A câmera é ortográfica: afastar no eixo da câmera não muda a posição em
	# tela, só garante que a peça passe por trás do board.
	_drop_start_position = (
		_squash_pivot.global_position
		+ _drop_away * maxf(drop_depth_offset, 0.0)
	)
	_drop_start_basis = _squash_pivot.global_transform.basis
	_drop_start_scale = _squash_pivot.scale
	_drop_distance = maxf(fall_distance, 0.1)
	_drop_spin = deg_to_rad(spin_degrees)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_apply_drop_fall, 0.0, 1.0, duration)
	tween.tween_method(_apply_drop_scale, 0.0, 1.0, duration)
	tween.tween_method(_apply_drop_fade, 0.0, 1.0, duration * 0.55).set_delay(duration * 0.45)
	tween.chain().tween_callback(queue_free)


func _apply_drop_fall(progress: float) -> void:
	if not is_instance_valid(_squash_pivot):
		return
	# progress² dá aceleração de queda (começa devagar e despenca).
	var position := _drop_start_position + _drop_down * _drop_distance * progress * progress
	var basis := Basis(_drop_spin_axis, _drop_spin * progress) * _drop_start_basis
	_squash_pivot.global_transform = Transform3D(basis, position)


func _apply_drop_scale(progress: float) -> void:
	if not is_instance_valid(_squash_pivot):
		return
	_squash_pivot.scale = _drop_start_scale.lerp(Vector3.ONE * 0.3, progress)


func _apply_drop_fade(progress: float) -> void:
	# Fade por instância; o encolhimento é o fallback caso o renderer ignore a
	# transparência de materiais opacos.
	var value := clampf(progress, 0.0, 1.0)
	for node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry != null:
			geometry.transparency = value


func _apply_hold_pose() -> void:
	if not is_instance_valid(_hold_point):
		return

	if _anticipation_tween != null:
		_cancel_anticipation()
	reset_visual_transform()
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
	_cancel_anticipation()
	global_position = world_position
	rotation = Vector3.ZERO
	reset_visual_transform()
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
	var aligned_to_target := true

	if target != null and _head != null:
		var to := target.global_position - global_position
		# A torre herda o yaw do Board (o nó Towers fica dentro dele), então o
		# alvo é convertido para o espaço local da torre antes de girar a cabeça.
		var local_to := global_transform.basis.orthonormalized().inverse() * to
		var desired := atan2(local_to.x, local_to.z) + deg_to_rad(data.aim_yaw_offset_degrees)
		var angular_error := absf(wrapf(desired - _head.rotation.y, -PI, PI))
		_head.rotation.y = lerp_angle(_head.rotation.y, desired, minf(1.0, 10.0 * delta))
		# O laser só dispara quando a pupila já está apontada para o alvo.
		if data.attack_mode == 1:
			aligned_to_target = angular_error <= deg_to_rad(9.0)

	# Enquanto a antecipação está rolando, não inicia outro wind-up: o próximo
	# `_fire` cancelaria o tween anterior antes do callback e o tiro nunca sairia.
	if target != null and _cooldown <= 0.0 and aligned_to_target and _anticipation_tween == null:
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
	if data.anticipation_enabled and _squash_pivot != null:
		_play_anticipation(target)
		return
	_shoot(target)


func _shoot(target: Enemy) -> void:
	if not is_placed or data == null:
		return
	if target == null or not is_instance_valid(target) or not target.is_alive:
		return

	if data.attack_mode == 1:
		if has_node("/root/AudioManager"):
			AudioManager.play_sfx("laser", 0.85)
		_fire_laser(target)
		return

	var container := get_tree().get_first_node_in_group(PROJECTILE_GROUP)
	if container == null:
		container = get_tree().current_scene
	if container == null:
		return

	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("shot_pew", 0.8)
	var projectile := Projectile.new()
	container.add_child(projectile)
	var muzzle := _barrel_tip.global_position if _barrel_tip != null else global_position + Vector3(0.0, 0.85, 0.0)
	projectile.setup(muzzle, target, data)


func _play_anticipation(target: Enemy) -> void:
	_cancel_anticipation()
	var squash := maxf(data.anticipation_squash, 0.0)
	var stretch := maxf(data.anticipation_stretch, 0.0)
	var duration := maxf(data.anticipation_duration, 0.1)
	var squashed := Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash)
	var stretched := Vector3(1.0 - stretch * 0.5, 1.0 + stretch, 1.0 - stretch * 0.5)

	_anticipation_tween = create_tween()
	_anticipation_tween.tween_property(_squash_pivot, "scale", squashed, duration * 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_anticipation_tween.tween_property(_squash_pivot, "scale", stretched, duration * 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anticipation_tween.tween_callback(_shoot.bind(target))
	_anticipation_tween.tween_property(_squash_pivot, "scale", Vector3.ONE, duration * 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_anticipation_tween.finished.connect(_on_anticipation_finished)


func _on_anticipation_finished() -> void:
	_anticipation_tween = null


func _cancel_anticipation() -> void:
	if _anticipation_tween != null and _anticipation_tween.is_valid():
		_anticipation_tween.kill()
	_anticipation_tween = null
	if _squash_pivot != null:
		_squash_pivot.scale = Vector3.ONE


func _fire_laser(target: Enemy) -> void:
	if not is_instance_valid(target) or not target.is_alive:
		return

	var muzzle := _barrel_tip.global_position if _barrel_tip != null else _head.global_position
	var target_point := target.global_position
	if target.data != null:
		target_point.y += target.data.height * 0.55

	_create_laser_segment(muzzle, target_point, 0.065, Color(0.12, 1.0, 0.18, 0.38))
	_create_laser_segment(muzzle, target_point, 0.024, Color(0.72, 1.0, 0.72, 1.0))
	target.take_damage(data.damage)


func _create_laser_segment(start: Vector3, finish: Vector3, radius: float, color: Color) -> void:
	var distance := start.distance_to(finish)
	if distance <= 0.01:
		return

	var beam := MeshInstance3D.new()
	beam.name = "EyeLaserBeam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = distance
	cylinder.radial_segments = 8
	beam.mesh = cylinder

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 2.5
	beam.material_override = material

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(beam)
	var direction := (finish - start).normalized()
	beam.global_position = (start + finish) * 0.5
	beam.global_basis = Basis(Quaternion(Vector3.UP, direction))

	var timer := get_tree().create_timer(0.11)
	timer.timeout.connect(beam.queue_free)


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

	# Deformação da antecipação: o pivô envolve o modelo inteiro (base, coluna,
	# cabeça e visual). A colisão fica fora para não afetar a física.
	_squash_pivot = Node3D.new()
	_squash_pivot.name = "SquashPivot"
	add_child(_squash_pivot)

	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.34
	base_mesh.bottom_radius = 0.4
	base_mesh.height = 0.22
	base_mesh.radial_segments = 12
	base.mesh = base_mesh
	base.material_override = body_material
	base.position.y = 0.11
	_squash_pivot.add_child(base)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 0.66 if data.visual_scene != null else 0.82
	_squash_pivot.add_child(_head)

	if data.visual_scene != null:
		var visual := data.visual_scene.instantiate() as Node3D
		if visual != null:
			visual.name = "TowerVisual"
			visual.scale = Vector3.ONE * data.visual_scale
			_head.add_child(visual)

		_barrel_tip = Marker3D.new()
		_barrel_tip.name = "LaserOrigin"
		_barrel_tip.position = data.muzzle_offset
		_head.add_child(_barrel_tip)
	else:
		var column := MeshInstance3D.new()
		var column_mesh := CylinderMesh.new()
		column_mesh.top_radius = 0.17
		column_mesh.bottom_radius = 0.24
		column_mesh.height = 0.5
		column_mesh.radial_segments = 10
		column.mesh = column_mesh
		column.material_override = body_material
		column.position.y = 0.47
		_squash_pivot.add_child(column)

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
