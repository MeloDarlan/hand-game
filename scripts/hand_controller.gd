extends Node3D
class_name HandController

## Mão gigante controlada pelo mouse.
## - A palma segue o cursor num plano paralelo à câmera.
## - Clique esquerdo toca CATCH; soltar rebobina o CATCH e volta para IDLE.
## - Durante o clique, objetos pegáveis são levados até o HoldPoint e
##   acompanham a mão (drag & drop). Ao soltar, recebem a velocidade da mão.

enum MovementMode { FOLLOW_MOUSE, FIXED_ARM }

signal grab_started(body: Grabbable)
signal grab_released(body: Grabbable, velocity: Vector3)
signal movement_mode_changed(mode: MovementMode)

@export_group("Movement")
## FOLLOW_MOUSE: a palma segue o cursor. FIXED_ARM: a base do antebraço fica
## fixa e o braço inteiro pivota para apontar ao mouse.
@export var movement_mode: MovementMode = MovementMode.FOLLOW_MOUSE:
	set(value):
		if movement_mode == value:
			return
		movement_mode = value
		if is_node_ready():
			_apply_movement_mode()

## Raio máximo, em unidades, que a palma pode se afastar da âncora no modo livre.
@export var max_reach := 5.8
## Âncora do raio em coordenadas normalizadas da tela. (0.5, 1.0) = centro inferior.
@export var reach_anchor_screen := Vector2(0.5, 1.0)

@export_group("Fixed Arm")
## Ângulo máximo do braço em relação à vertical.
@export_range(0.0, 89.0) var max_aim_degrees := 50.0
@export var aim_smoothing := 12.0
## Quanto a base do antebraço pode subir, em unidades, a partir da pose inicial.
## Mantenha <= 2.6 para o corte do antebraço não aparecer com a câmera atual.
@export_range(0.0, 3.5, 0.01) var max_base_rise := 2.4
@export var vertical_smoothing := 12.0

@export_group("Mouse")
## Quanto maior, menos atraso a mão tem atrás do cursor.
@export var follow_speed := 10
@export var hide_cursor := true
@export_range(0.0, 20.0) var tilt_degrees := 6.0
@export var tilt_smoothing := 10.0

@export_group("Catch")
## Tempo (em segundos) para a mão fechar completamente.
@export_range(0.1, 1.0, 0.01) var catch_duration := 0.34
@export var rewind_speed := 2.0

@export_group("Grab")
@export var grabbable_mask := 2
@export var grab_radius := 0.95
@export var hold_velocity_smoothing := 15.0
@export var throw_scale := 1.1
@export var max_throw_speed := 18.0
@export var min_throw_speed := 1.5

@onready var palm_pivot: Node3D = $PalmPivot
@onready var hold_point: Marker3D = $PalmPivot/HoldPoint
@onready var grab_shape: CollisionShape3D = $PalmPivot/GrabArea/CollisionShape3D
@onready var arm_end: Marker3D = $PalmPivot/ArmEnd

var _model: Node3D
var _anim: AnimationPlayer
var _camera: Camera3D

var _mouse_pos := Vector2.ZERO
var _target := Vector3.ZERO
var _catching := false
var _catch_length := 0.75
var _catch_tween: Tween
var _rewind_tween: Tween
var _held: Grabbable
var _hold_velocity := Vector3.ZERO
var _prev_hold_pos := Vector3.ZERO

var _initial_hand_position := Vector3.ZERO
var _initial_rotation := Vector3.ZERO
var _base_anchor := Vector3.ZERO
var _base_y := 0.0
var _arm_length := 6.1
var _aim_angle := 0.0


func _ready() -> void:
	_model = $PalmPivot/Model
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_camera = get_viewport().get_camera_3d()

	if _camera == null:
		push_warning("HandController: nenhuma Camera3D ativa encontrada.")
	if _anim == null:
		push_warning("HandController: AnimationPlayer não encontrado dentro do modelo.")
	else:
		var catch_anim := _anim.get_animation("CATCH")
		if catch_anim:
			catch_anim.loop_mode = Animation.LOOP_NONE
			_catch_length = maxf(catch_anim.length, 0.001)

		var idle_anim := _anim.get_animation("IDLE")
		if idle_anim:
			idle_anim.loop_mode = Animation.LOOP_NONE

		_apply_idle()

	_setup_grab_radius()

	# Guarda a pose inicial: referência do centro e da base do antebraço.
	_initial_hand_position = global_position
	_initial_rotation = rotation
	if arm_end:
		_base_anchor = arm_end.global_position
		_arm_length = _initial_hand_position.distance_to(_base_anchor)
	else:
		_base_anchor = _initial_hand_position + Vector3(0.0, -6.1, 0.0)
	_base_y = _base_anchor.y

	# Começa já na posição do cursor, sem animação de entrada.
	_mouse_pos = get_viewport().get_mouse_position()
	_target = _mouse_target()
	global_position = _target
	_apply_movement_mode()
	_prev_hold_pos = hold_point.global_position

	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN


func _process(delta: float) -> void:
	if movement_mode == MovementMode.FIXED_ARM:
		_process_fixed_arm(delta)
	else:
		_process_follow_mouse(delta)

	# Atualiza o objeto segurado no mesmo frame em que a mão se moveu.
	if is_instance_valid(_held):
		_held.sync_to_hold_point()
	elif _held != null:
		_held = null


func _process_follow_mouse(delta: float) -> void:
	_target = _mouse_target()
	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_target, weight)
	rotation = rotation.lerp(_initial_rotation, weight)
	_update_tilt(delta)


func _process_fixed_arm(delta: float) -> void:
	var vertical_weight := 1.0 - exp(-vertical_smoothing * delta)
	_base_y = lerp(_base_y, _desired_base_y(), vertical_weight)

	var desired := _desired_aim_angle()
	var weight := 1.0 - exp(-aim_smoothing * delta)
	_aim_angle = lerp_angle(_aim_angle, desired, weight)
	_apply_fixed_arm_pose()
	palm_pivot.rotation = Vector3.ZERO


func _desired_base_y() -> float:
	var mouse_world := _screen_to_world(_mouse_pos)
	var desired := _base_anchor.y + (mouse_world.y - _initial_hand_position.y)
	return minf(desired, _base_anchor.y + max_base_rise)


func _desired_aim_angle() -> float:
	var mouse_world := _screen_to_world(_mouse_pos)
	var base := Vector3(_base_anchor.x, _base_y, _base_anchor.z)
	var to_mouse := mouse_world - base

	if absf(to_mouse.x) < 0.0001 and absf(to_mouse.y) < 0.0001:
		return 0.0

	var angle := atan2(-to_mouse.x, to_mouse.y)
	var limit := deg_to_rad(max_aim_degrees)
	return clampf(angle, -limit, limit)


func _apply_fixed_arm_pose() -> void:
	var base := Vector3(_base_anchor.x, _base_y, _base_anchor.z)
	var direction := Vector3(-sin(_aim_angle), cos(_aim_angle), 0.0)
	global_position = base + direction * _arm_length
	rotation = Vector3(0.0, 0.0, _aim_angle)


func _apply_movement_mode() -> void:
	if movement_mode == MovementMode.FIXED_ARM:
		_base_y = _desired_base_y()
		_aim_angle = _desired_aim_angle()
		_apply_fixed_arm_pose()
		palm_pivot.rotation = Vector3.ZERO
	else:
		# A raiz volta à rotação neutra para o antebraço não aparecer.
		rotation = _initial_rotation
		_target = _mouse_target()

	movement_mode_changed.emit(movement_mode)


func set_movement_mode(mode: MovementMode) -> void:
	movement_mode = mode


func toggle_movement_mode() -> void:
	set_movement_mode(
		MovementMode.FIXED_ARM
		if movement_mode == MovementMode.FOLLOW_MOUSE
		else MovementMode.FOLLOW_MOUSE
	)


func _physics_process(delta: float) -> void:
	if _held == null:
		_prev_hold_pos = hold_point.global_position
		_hold_velocity = Vector3.ZERO
		return

	if not is_instance_valid(_held):
		_held = null
		_prev_hold_pos = hold_point.global_position
		_hold_velocity = Vector3.ZERO
		return

	var current := hold_point.global_position
	var instantaneous := (current - _prev_hold_pos) / maxf(delta, 0.0001)
	_hold_velocity = _hold_velocity.lerp(
		instantaneous,
		1.0 - exp(-hold_velocity_smoothing * delta)
	)
	_prev_hold_pos = current


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_pos = event.position
			_on_press()
		else:
			_on_release()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle_movement_mode()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _catching:
				_on_release()
			elif _held != null:
				_release_held()

			if hide_cursor:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		NOTIFICATION_APPLICATION_FOCUS_IN:
			if hide_cursor:
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN

			_mouse_pos = get_viewport().get_mouse_position()


func _exit_tree() -> void:
	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_grab_radius() -> void:
	if grab_shape and grab_shape.shape is SphereShape3D:
		(grab_shape.shape as SphereShape3D).radius = grab_radius


func _screen_to_world(screen_position: Vector2) -> Vector3:
	if _camera == null:
		return global_position

	# Plano paralelo à tela, passando pela palma.
	var normal := -_camera.global_transform.basis.z
	var plane := Plane(normal, global_position.dot(normal))
	var from := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var hit = plane.intersects_ray(from, direction)

	if hit == null:
		return global_position
	return hit


func _mouse_target() -> Vector3:
	return _clamp_reach(_screen_to_world(_mouse_pos))


func _clamp_reach(target: Vector3) -> Vector3:
	if max_reach <= 0.0 or _camera == null:
		return target

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return target

	var anchor := _screen_to_world(Vector2(
		viewport_size.x * reach_anchor_screen.x,
		viewport_size.y * reach_anchor_screen.y
	))
	var offset := target - anchor
	var flat := Vector2(offset.x, offset.y)
	if flat.length() > max_reach:
		flat = flat.normalized() * max_reach
		target.x = anchor.x + flat.x
		target.y = anchor.y + flat.y
	return target


func _update_tilt(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var normalized := Vector2.ZERO

	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		normalized = (_mouse_pos / viewport_size) * 2.0 - Vector2.ONE
		normalized.x = clampf(normalized.x, -1.0, 1.0)
		normalized.y = clampf(normalized.y, -1.0, 1.0)

	var target_rotation := Vector3(
		deg_to_rad(-normalized.y * tilt_degrees),
		deg_to_rad(normalized.x * tilt_degrees * 0.6),
		deg_to_rad(-normalized.x * tilt_degrees)
	)
	var weight := 1.0 - exp(-tilt_smoothing * delta)
	palm_pivot.rotation = palm_pivot.rotation.lerp(target_rotation, weight)


func _on_press() -> void:
	if _catching:
		return

	_catching = true

	if _rewind_tween and _rewind_tween.is_valid():
		_rewind_tween.kill()
		_rewind_tween = null
	if _catch_tween and _catch_tween.is_valid():
		_catch_tween.kill()
		_catch_tween = null

	if _anim:
		_start_catch(_anim.current_animation_position)

	_try_grab()


func _start_catch(from_position: float) -> void:
	var start := clampf(from_position, 0.0, _catch_length)
	var remaining := _catch_length - start

	_anim.speed_scale = 0.0
	_anim.play("CATCH")
	_anim.seek(start, true)

	if remaining <= 0.001:
		return

	# Ease-out: reage na hora e desacelera no fim, em vez de fechar linearmente.
	var duration := catch_duration * (remaining / _catch_length)
	if _catch_tween and _catch_tween.is_valid():
		_catch_tween.kill()

	_catch_tween = create_tween()
	_catch_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_catch_tween.tween_method(
		func(time: float) -> void: _anim.seek(time, true),
		start,
		_catch_length,
		duration
	)


func _on_release() -> void:
	if not _catching:
		return

	_catching = false
	if _catch_tween and _catch_tween.is_valid():
		_catch_tween.kill()
		_catch_tween = null
	_release_held()
	_rewind_catch()


func _rewind_catch() -> void:
	if _anim == null:
		return

	var position := clampf(
		_anim.current_animation_position,
		0.0,
		maxf(_catch_length, 0.0)
	)

	if position <= 0.001:
		_apply_idle()
		return

	# O CATCH pode ter chegado ao fim e liberado o current_animation.
	# Reafirma a animação no ponto atual antes de rebobinar.
	_anim.speed_scale = 1.0
	_anim.play("CATCH", 0.0, 1.0)
	_anim.seek(position, true)
	_anim.speed_scale = 0.0

	if _rewind_tween and _rewind_tween.is_valid():
		_rewind_tween.kill()

	var duration := position / maxf(rewind_speed, 0.01)
	_rewind_tween = create_tween()
	_rewind_tween.tween_method(
		func(time: float) -> void: _anim.seek(time, true),
		position,
		0.0,
		duration
	)
	_rewind_tween.finished.connect(_apply_idle)


func _apply_idle() -> void:
	_rewind_tween = null
	if _anim == null:
		return

	# IDLE é uma pose estática (um único keyframe): aplica o frame 0 e congela.
	_anim.speed_scale = 1.0
	_anim.play("IDLE")
	_anim.seek(0.0, true)
	_anim.speed_scale = 0.0


func _try_grab() -> void:
	if grab_shape == null or grab_shape.shape == null:
		return

	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = grab_shape.shape
	params.transform = grab_shape.global_transform
	params.collision_mask = grabbable_mask
	params.collide_with_areas = false
	params.collide_with_bodies = true

	var hits := space.intersect_shape(params, 32)
	var best: Grabbable = null
	var best_screen_distance := INF
	var best_world_distance := INF

	var reference_screen := _mouse_pos
	if movement_mode == MovementMode.FIXED_ARM and _camera:
		reference_screen = _camera.unproject_position(grab_shape.global_position)

	for hit in hits:
		var body := hit.get("collider") as Grabbable
		if body == null or body.is_held:
			continue

		var screen_position := Vector2.ZERO
		if _camera:
			screen_position = _camera.unproject_position(body.global_position)

		var screen_distance := screen_position.distance_to(reference_screen)
		var world_distance := body.global_position.distance_to(grab_shape.global_position)

		if (
			screen_distance < best_screen_distance
			or (
				is_equal_approx(screen_distance, best_screen_distance)
				and world_distance < best_world_distance
			)
		):
			best = body
			best_screen_distance = screen_distance
			best_world_distance = world_distance

	if best:
		_grab(best)


func _grab(body: Grabbable) -> void:
	_held = body
	_prev_hold_pos = hold_point.global_position
	_hold_velocity = Vector3.ZERO
	body.grab(hold_point)
	grab_started.emit(body)


func _release_held() -> void:
	if _held == null:
		return

	if not is_instance_valid(_held):
		_held = null
		return

	var velocity := _hold_velocity
	if velocity.length() < min_throw_speed:
		velocity = Vector3.ZERO
	else:
		velocity *= throw_scale
		if velocity.length() > max_throw_speed:
			velocity = velocity.normalized() * max_throw_speed

	var body := _held
	_held = null
	_hold_velocity = Vector3.ZERO
	body.release(velocity)
	grab_released.emit(body, velocity)
