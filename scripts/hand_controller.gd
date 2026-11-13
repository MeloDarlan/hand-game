extends Node3D
class_name HandController

## Mão gigante no visual/comportamento original, adaptada ao tabuleiro iso.
## - A mão vive num plano paralelo à câmera, na frente do tabuleiro.
## - O dorso fica para a câmera e o antebraço desce para fora da tela,
##   exatamente como no hand-game original.
## - O alvo do TD é obtido por raio da câmera até o plano do tabuleiro.
## - DOIS modos: FOLLOW_MOUSE (padrão) e FIXED_ARM.

signal grab_started(body: Grabbable)
signal grab_released(body: Grabbable, velocity: Vector3)
signal movement_mode_changed(mode: MovementMode)

enum MovementMode { FOLLOW_MOUSE, FIXED_ARM }

@export_group("Board")
## Caminho para o Board. Preenchido na main.tscn.
@export var board_path: NodePath
## Folga além das bordas do tabuleiro que o alvo ainda alcança.
@export var board_margin := 0.8
## Se true, a mão segue o cursor por toda a tela, sem limitar a posição ao
## tabuleiro. Se false, usa board_margin para prender a mão ao redor da grade.
@export var free_movement := true
## Distância, em unidades, do plano da mão à frente do centro do tabuleiro.
@export var hand_plane_distance := 8.0
## Escala aplicada ao PalmPivot (mão maior = braço mais longo e corte oculto).
@export_range(0.5, 3.0, 0.05) var hand_scale := 1.7:
	set(value):
		hand_scale = value
		if is_node_ready() and palm_pivot != null:
			palm_pivot.scale = Vector3.ONE * value
			apply_pose()

@export_group("Pose")
## Posição local da pinça (HoldPoint): X lateral, Y na direção dos dedos,
## Z para fora da palma. A peça continua caindo no tile sob o cursor.
@export var pinch_offset := Vector3(0.0, 0.2, 0.55):
	set(value):
		pinch_offset = value
		if is_node_ready() and hold_point != null:
			hold_point.position = value
			if grab_area != null:
				grab_area.position = value
			apply_pose()

## Palma para a câmera com 3/4 mais isométrico.
@export_range(-45.0, 45.0) var depth_yaw_degrees := 28.0:
	set(value):
		depth_yaw_degrees = value
		if is_node_ready():
			apply_pose()

@export_range(-45.0, 45.0) var screen_roll_degrees := 34.0:
	set(value):
		screen_roll_degrees = value
		if is_node_ready():
			apply_pose()

@export_range(-30.0, 30.0) var depth_pitch_degrees := 12.0:
	set(value):
		depth_pitch_degrees = value
		if is_node_ready():
			apply_pose()

## Giro da peça em torno do próprio eixo vertical enquanto está na palma.
@export_range(-180.0, 180.0) var held_yaw_degrees := 0.0
## Recuo da mão (para baixo na tela) após encaixar, para revelar a torre.
@export var placement_retract_distance := 3.0

@export_group("Movement")
## FOLLOW_MOUSE: a mão segue o cursor 1:1. FIXED_ARM: o braço aponta para
## uma base fixa na parte inferior da tela.
@export var movement_mode: MovementMode = MovementMode.FOLLOW_MOUSE:
	set(value):
		if movement_mode == value:
			return
		movement_mode = value
		if is_node_ready():
			_apply_movement_mode()

## Quanto maior, menos atraso a mão tem atrás do cursor.
@export var follow_speed := 12.0
@export var hide_cursor := true
@export_range(0.0, 20.0) var tilt_degrees := 4.0
@export var tilt_smoothing := 10.0

@export_group("Fixed Arm")
## Ângulo máximo do braço em relação à vertical da tela.
@export_range(0.0, 89.0) var max_aim_degrees := 70.0
@export var aim_smoothing := 12.0
## Base fixa em fração da tela. y > 1 = abaixo da tela.
@export var fixed_base_screen := Vector2(0.5, 1.18)

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

## Consultada em _on_release. Se retornar false, a mão continua segurando.
var release_guard := Callable()
## Se definido, escolhe o corpo a pegar (usado pelo TD para pegar torres no
## tabuleiro, que está atrás do plano da mão). Recebe: nenhum argumento.
## Retorna: Grabbable ou null.
var grab_selector := Callable()

@onready var palm_pivot: Node3D = $PalmPivot
@onready var hold_point: Marker3D = $PalmPivot/HoldPoint
@onready var grab_area: Area3D = $PalmPivot/GrabArea
@onready var grab_shape: CollisionShape3D = $PalmPivot/GrabArea/CollisionShape3D

var _model: Node3D
var _anim: AnimationPlayer
var _camera: Camera3D
var _board: Board

var _camera_forward := Vector3.FORWARD
var _camera_up := Vector3.UP
var _camera_back := Vector3.BACK
var _base_hand_basis := Basis.IDENTITY
var _current_basis := Basis.IDENTITY
var _hand_plane := Plane()
var _hand_plane_point := Vector3.ZERO

var _mouse_pos := Vector2.ZERO
var _retracted := false
var _catching := false
var _catch_length := 0.75
var _catch_tween: Tween
var _rewind_tween: Tween
var _held: Grabbable
var _hold_velocity := Vector3.ZERO
var _prev_hold_pos := Vector3.ZERO


func _ready() -> void:
	_model = $PalmPivot/Model
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_camera = get_viewport().get_camera_3d()
	_board = get_node_or_null(board_path) as Board

	if _camera == null:
		push_warning("HandController: nenhuma Camera3D ativa encontrada.")
	if _board == null:
		push_warning("HandController: board_path não aponta para um Board.")

	_setup_camera_pose()
	palm_pivot.scale = Vector3.ONE * hand_scale
	hold_point.position = pinch_offset
	grab_area.position = pinch_offset

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

	_mouse_pos = get_viewport().get_mouse_position()
	_current_basis = _base_hand_basis
	global_transform.basis = _current_basis
	global_position = _desired_hand_position()
	_update_hold_point_basis()
	_prev_hold_pos = hold_point.global_position

	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CONFINED


func _setup_camera_pose() -> void:
	if _camera == null:
		return

	var camera_basis := _camera.global_transform.basis
	_camera_forward = -camera_basis.z.normalized()
	_camera_up = camera_basis.y.normalized()
	_camera_back = camera_basis.z.normalized()
	var camera_right := camera_basis.x.normalized()

	# Palma para a câmera (a peça fica na palma) + 3/4 para dar profundidade.
	var basis := Basis(camera_right, _camera_up, _camera_back)
	basis = Basis(_camera_up, deg_to_rad(depth_yaw_degrees)) * basis
	basis = Basis(_camera_back, deg_to_rad(screen_roll_degrees)) * basis
	basis = Basis(camera_right, deg_to_rad(depth_pitch_degrees)) * basis
	_base_hand_basis = basis

	var center := Vector3.ZERO
	if _board != null:
		center = _board.to_global(Vector3.ZERO)
	_hand_plane_point = center - _camera_forward * hand_plane_distance
	_hand_plane = Plane(_camera_forward, _hand_plane_point.dot(_camera_forward))


## Reaplica pose/escala/pinça com os valores atuais dos exports. Usado pelos
## setters de tuning para atualizar na hora, sem reiniciar a cena.
func apply_pose() -> void:
	if not is_node_ready():
		return
	if _camera == null:
		return

	_setup_camera_pose()
	_current_basis = _base_hand_basis
	global_transform.basis = _current_basis
	global_position = _desired_hand_position()
	_update_hold_point_basis()


func _process(delta: float) -> void:
	_process_follow(delta)
	_update_hold_point_basis()

	# Atualiza o objeto segurado no mesmo frame em que a mão se moveu.
	if is_instance_valid(_held):
		_held.sync_to_hold_point()
	elif _held != null:
		_held = null


func _process_follow(delta: float) -> void:
	var target_basis := _desired_hand_basis(delta)
	_current_basis = target_basis
	global_transform.basis = _current_basis

	var target := _desired_hand_position()
	var weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(target, weight)
	_update_tilt(delta)


func _desired_hand_basis(delta: float) -> Basis:
	if movement_mode == MovementMode.FOLLOW_MOUSE:
		return _base_hand_basis

	if _camera == null:
		return _base_hand_basis

	var viewport_size := get_viewport().get_visible_rect().size
	var base_screen := Vector2(
		viewport_size.x * fixed_base_screen.x,
		viewport_size.y * fixed_base_screen.y
	)
	var base := _screen_to_hand_plane(base_screen)

	var direction := base - global_position
	direction -= _camera_forward * direction.dot(_camera_forward)
	if direction.length_squared() < 0.0001:
		return _current_basis
	direction = direction.normalized()

	var screen_normal := _camera_back
	var desired_fingers := -direction
	desired_fingers -= screen_normal * desired_fingers.dot(screen_normal)
	if desired_fingers.length_squared() < 0.0001:
		return _current_basis
	desired_fingers = desired_fingers.normalized()

	var base_fingers := (_base_hand_basis * Vector3.UP).normalized()
	base_fingers -= screen_normal * base_fingers.dot(screen_normal)
	if base_fingers.length_squared() < 0.0001:
		base_fingers = _camera_up
	base_fingers = base_fingers.normalized()

	var angle := base_fingers.signed_angle_to(desired_fingers, screen_normal)
	var limit := deg_to_rad(max_aim_degrees)
	angle = clampf(angle, -limit, limit)
	var target_basis := Basis(screen_normal, angle) * _base_hand_basis

	var weight := 1.0 - exp(-aim_smoothing * delta)
	return _current_basis.slerp(target_basis, weight)


func _desired_hand_position() -> Vector3:
	if _camera == null:
		return global_position

	var board_point := _cursor_board_point()
	var screen := _camera.unproject_position(board_point)
	var hand_point := _screen_to_hand_plane(screen)

	# O cursor/tile é o pé da peça. A mão sobe até a pinça, no topo dela.
	var grip_lift := 0.0
	if _held is TowerPiece:
		grip_lift = (_held as TowerPiece).get_grip_height()
	var grip_point := hand_point + Vector3.UP * grip_lift

	var offset := _current_basis * (hold_point.position * hand_scale)
	var hand_root := grip_point - offset

	if _retracted:
		hand_root -= _camera_up * placement_retract_distance

	return hand_root


func _update_hold_point_basis() -> void:
	# A peça fica em pé na tela; o yaw acompanha o yaw da mão/palma.
	var t := hold_point.global_transform
	t.basis = Basis(Vector3.UP, deg_to_rad(depth_yaw_degrees + held_yaw_degrees))
	hold_point.global_transform = t


func _cursor_board_point() -> Vector3:
	if _camera == null:
		return Vector3.ZERO

	var hit = _ray_to_board_plane(_mouse_pos)
	if hit == null:
		return Vector3.ZERO

	var point: Vector3 = hit
	return _project_to_board_plane(point)


## Aplica o clamp ao redor do tabuleiro apenas no modo restrito. Com a mão
## livre, o cursor pode sair da grade e o alvo vira uma célula inválida.
func _project_to_board_plane(point: Vector3) -> Vector3:
	if _board != null and not free_movement:
		point = _board.clamp_world_position(point, board_margin)
	point.y = 0.0
	return point


func _ray_to_board_plane(screen_position: Vector2):
	var plane := Plane(Vector3.UP, 0.0)
	if _camera == null:
		return null
	return plane.intersects_ray(
		_camera.project_ray_origin(screen_position),
		_camera.project_ray_normal(screen_position)
	)


func _screen_to_hand_plane(screen_position: Vector2) -> Vector3:
	if _camera == null:
		return _hand_plane_point
	var hit = _hand_plane.intersects_ray(
		_camera.project_ray_origin(screen_position),
		_camera.project_ray_normal(screen_position)
	)
	if hit == null:
		return _hand_plane_point
	return hit


## Ponto do tabuleiro sob a peça (a base, não a pinça).
## É a fonte de verdade para highlight, validação e encaixe no TD.
func get_target_position() -> Vector3:
	if _camera == null:
		return Vector3.ZERO

	var reference := hold_point.global_position
	if _held is TowerPiece:
		var piece := _held as TowerPiece
		# Base canônica: independe do swing visual da peça.
		var up := hold_point.global_transform.basis.y.normalized()
		reference -= up * piece.get_grip_height()

	var screen := _camera.unproject_position(reference)
	var hit = _ray_to_board_plane(screen)
	if hit == null:
		return Vector3.ZERO

	var point: Vector3 = hit
	return _project_to_board_plane(point)


func get_hold_position() -> Vector3:
	return hold_point.global_position


func get_held_body() -> Grabbable:
	return _held


## Ponto do board sob o centro do GrabArea (a região da mão, não o pé da peça).
func get_grab_region_position() -> Vector3:
	if _camera == null or grab_area == null:
		return get_target_position()

	var screen := _camera.unproject_position(grab_area.global_position)
	var hit = _ray_to_board_plane(screen)
	if hit == null:
		return get_target_position()

	var point: Vector3 = hit
	return _project_to_board_plane(point)


## Raio efetivo do GrabArea no mundo (a esfera é escalada pelo PalmPivot).
func get_grab_radius() -> float:
	if grab_area == null:
		return grab_radius
	var area_scale := grab_area.global_transform.basis.get_scale()
	var largest_scale := maxf(maxf(area_scale.x, area_scale.y), area_scale.z)
	return grab_radius * largest_scale


## Após encaixar, a mão recua para revelar a torre. Volta a seguir o cursor
## no próximo InputEventMouseMotion.
func retract_after_place() -> void:
	_retracted = true


func set_movement_mode(mode: MovementMode) -> void:
	movement_mode = mode


func toggle_movement_mode() -> void:
	set_movement_mode(
		MovementMode.FIXED_ARM
		if movement_mode == MovementMode.FOLLOW_MOUSE
		else MovementMode.FOLLOW_MOUSE
	)


func _apply_movement_mode() -> void:
	if movement_mode == MovementMode.FOLLOW_MOUSE:
		_current_basis = _base_hand_basis
	movement_mode_changed.emit(movement_mode)


func grab_body(body: Grabbable) -> void:
	if body == null:
		return
	if _held == body:
		return
	if _held != null:
		cancel_grab()

	_retracted = false
	_catching = true
	if _rewind_tween and _rewind_tween.is_valid():
		_rewind_tween.kill()
		_rewind_tween = null
	if _catch_tween and _catch_tween.is_valid():
		_catch_tween.kill()
		_catch_tween = null
	if _anim != null:
		_start_catch(_anim.current_animation_position)
	_grab(body)


func cancel_grab() -> void:
	if _held == null:
		release_guard = Callable()
		return

	var body := _held
	_held = null
	_hold_velocity = Vector3.ZERO
	if is_instance_valid(body):
		body.release(Vector3.ZERO)

	release_guard = Callable()

	if _catching:
		_catching = false
		if _catch_tween and _catch_tween.is_valid():
			_catch_tween.kill()
			_catch_tween = null
		_rewind_catch()


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
		_retracted = false
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
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED

			_mouse_pos = get_viewport().get_mouse_position()


func _exit_tree() -> void:
	if hide_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_grab_radius() -> void:
	if grab_shape and grab_shape.shape is SphereShape3D:
		(grab_shape.shape as SphereShape3D).radius = grab_radius


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

	# CATCH: a mão fecha em volta da peça que está na palma. O outline cobre a
	# parte da peça que encosta/fica sobre a mão.
	if _anim != null:
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

	# O BuildController pode recusar o drop (tile inválido). Nesse caso a mão
	# permanece fechada e segurando a peça.
	if release_guard.is_valid() and not bool(release_guard.call()):
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
	# Torres ficam no tabuleiro, atrás do plano da mão: o TD fornece o alvo
	# concreto via grab_selector (por célula, em espaço de tela).
	if grab_selector.is_valid():
		var selected = grab_selector.call()
		if selected is Grabbable:
			_grab(selected)
			return

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

	for hit in hits:
		var body := hit.get("collider") as Grabbable
		if body == null or body.is_held or body.grab_locked:
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
	if body == null or body.grab_locked or body.is_held:
		return
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
