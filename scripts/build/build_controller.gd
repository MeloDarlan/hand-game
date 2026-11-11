extends Node
class_name BuildController

## Media a toolbar, a mão e o tabuleiro.
## Fluxo: escolher torre -> peça nasce na mão (CATCH) -> soltar em tile válido
## -> encaixa e cobra. Pegar uma torre colocada com CATCH permite reposicionar.
## A mão não conhece torres: ela só consulta release_guard antes de soltar.

const DEFAULT_TOWER_PATHS := [
	"res://resources/towers/cannon.tres",
	"res://resources/towers/rapid.tres",
	"res://resources/towers/frost.tres",
]
const INVALID_CELL := Vector2i(-999, -999)

@export var tower_types: Array = []

var selected_index := -1

var _held: TowerPiece
var _origin_cell := INVALID_CELL
var _hover_cell := INVALID_CELL
var _hover_valid := false
var _release_cell := INVALID_CELL
var _placement_ring: MeshInstance3D
var _placement_material: StandardMaterial3D

@onready var _board: Board = %Board
@onready var _hand: HandController = %HandPlayer
@onready var _towers: Node3D = %Towers
@onready var _hud: GameHUD = %HUD
@onready var _game: GameManager = %GameManager


func _ready() -> void:
	if tower_types.is_empty():
		for path in DEFAULT_TOWER_PATHS:
			var tower := load(path)
			if tower != null:
				tower_types.append(tower)

	_hud.setup_towers(tower_types)
	_hud.tower_selected.connect(_on_tower_selected)
	_hand.grab_started.connect(_on_grab_started)
	_hand.grab_released.connect(_on_grab_released)
	_hand.grab_selector = _pick_tower_at_hand
	_create_placement_ring()


func _process(_delta: float) -> void:
	_update_hand_preview()

	if _held == null:
		return

	# O grip pode ser ajustado no listener (TowerPiece.grip_height); o anel
	# acompanha o pé da peça mesmo sem mudar de célula.
	if _placement_ring != null and _placement_ring.visible:
		_placement_ring.position = Vector3(0.0, -_held.get_grip_height(), 0.0)

	var cell := _board.world_to_cell(_hand.get_target_position())
	var valid := _board.is_buildable(cell)
	if cell == _hover_cell and valid == _hover_valid:
		return

	_hover_cell = cell
	_hover_valid = valid

	if not _board.is_in_bounds(cell):
		_board.hide_preview()
		_set_ring_state(false)
		return

	_board.show_highlight(cell, valid)
	var tower_range := _held.data.attack_range if _held.data != null else 3.0
	_board.show_range(_board.cell_to_world(cell), tower_range)
	_set_ring_state(valid)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_selection(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	match event.keycode:
		KEY_1:
			select_tower(0)
			get_viewport().set_input_as_handled()
		KEY_2:
			select_tower(1)
			get_viewport().set_input_as_handled()
		KEY_3:
			select_tower(2)
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()


func select_tower(index: int) -> void:
	if _game.state == GameManager.State.GAME_OVER:
		return
	if index < 0 or index >= tower_types.size():
		return

	if index == selected_index and _held != null:
		cancel_placement()
		return

	_cancel_current()
	selected_index = index
	_hud.set_selected(index)
	_spawn_piece()


func cancel_placement() -> void:
	_cancel_current()
	selected_index = -1
	_hud.set_selected(-1)


func _on_tower_selected(index: int) -> void:
	select_tower(index)


func _cycle_selection(step: int) -> void:
	var count := tower_types.size()
	if count == 0:
		return

	var next: int
	if selected_index < 0:
		next = 0 if step > 0 else count - 1
	else:
		next = posmod(selected_index + step, count)
	select_tower(next)


func _spawn_piece() -> void:
	var tower := tower_types[selected_index] as TowerData
	if tower == null or not _game.can_afford(tower.cost):
		selected_index = -1
		_hud.set_selected(-1)
		return

	var piece := TowerPiece.new()
	piece.setup(tower)
	_towers.add_child(piece)

	_held = piece
	_origin_cell = INVALID_CELL
	_hand.release_guard = _can_release_held
	_hand.grab_body(piece)


func _can_release_held() -> bool:
	if _held == null:
		return true
	# Chamada ANTES do release, quando o HandController ainda tem a peça.
	# Guardamos a célula porque no release o _held da mão já foi limpo e o
	# HoldPoint passa a ser a pinça no topo, não a base.
	var cell := _board.world_to_cell(_hand.get_target_position())
	_release_cell = cell
	return _board.is_buildable(cell)


func _pick_tower_at_hand() -> Grabbable:
	var center := _hand.get_grab_region_position()
	var radius := _hand.get_grab_radius()

	var center_cell := _board.world_to_cell(center)
	var center_tower := _board.get_tower(center_cell) as TowerPiece
	if center_tower != null and not center_tower.is_held:
		return center_tower

	# Fallback: a torre mais próxima dentro do anel do GrabArea.
	var best: TowerPiece = null
	var best_distance := radius
	for child in _towers.get_children():
		var tower := child as TowerPiece
		if tower == null or not tower.is_placed or tower.is_held:
			continue
		var distance := Vector2(
			tower.global_position.x - center.x,
			tower.global_position.z - center.z
		).length()
		if distance <= best_distance:
			best = tower
			best_distance = distance
	return best


func _update_hand_preview() -> void:
	if _board == null or _hand == null:
		return
	# Com peça na mão o único indicador é o placement verde/vermelho no pé.
	# O ciano fica reservado para a mão vazia (região do GrabArea/pick).
	if _held != null:
		_board.hide_hand_preview()
		return
	var center := _hand.get_grab_region_position()
	var cell := _board.world_to_cell(center)
	if not _board.is_in_bounds(cell):
		_board.hide_hand_preview()
		return
	_board.show_hand_preview(cell, _hand.get_grab_radius())


func _on_grab_started(body: Grabbable) -> void:
	var piece := body as TowerPiece
	if piece == null or not piece.is_placed:
		return

	# Pegou uma torre já colocada: libera a célula e entra em modo de mudança.
	if _held != null:
		_cancel_current()

	_held = piece
	_origin_cell = piece.cell
	_board.unregister_tower(piece.cell)
	piece.is_placed = false
	_hover_cell = INVALID_CELL
	_hand.release_guard = _can_release_held
	selected_index = -1
	_hud.set_selected(-1)


func _on_grab_released(body: Grabbable, _velocity: Vector3) -> void:
	if _held == null or body != _held:
		return

	# Célula guardada pelo release_guard (antes do HandController limpar _held).
	var cell := _release_cell
	_release_cell = INVALID_CELL
	if not _board.is_buildable(cell):
		_return_held()
		return

	_place_held(cell)


func _place_held(cell: Vector2i) -> void:
	var piece := _held
	if piece == null:
		return

	var is_move := _origin_cell != INVALID_CELL
	if not is_move and not _game.spend(piece.data.cost):
		_return_held()
		return

	piece.place(cell, _board.cell_to_world(cell))
	_board.register_tower(cell, piece)

	_held = null
	_origin_cell = INVALID_CELL
	_hand.release_guard = Callable()
	_stop_preview()

	selected_index = -1
	_hud.set_selected(-1)
	_hand.retract_after_place()


func _return_held() -> void:
	if _held == null:
		return

	var piece := _held
	_held = null

	if _origin_cell != INVALID_CELL:
		piece.place(_origin_cell, _board.cell_to_world(_origin_cell))
		_board.register_tower(_origin_cell, piece)
	else:
		piece.queue_free()

	_origin_cell = INVALID_CELL
	_hand.release_guard = Callable()
	_stop_preview()


func _cancel_current() -> void:
	if _held == null:
		_hand.release_guard = Callable()
		return

	var piece := _held
	_held = null
	_hand.cancel_grab()

	if _origin_cell != INVALID_CELL:
		piece.place(_origin_cell, _board.cell_to_world(_origin_cell))
		_board.register_tower(_origin_cell, piece)
	else:
		piece.queue_free()

	_origin_cell = INVALID_CELL
	_hand.release_guard = Callable()
	_stop_preview()


func _stop_preview() -> void:
	_hover_cell = INVALID_CELL
	_hover_valid = false
	_board.hide_preview()
	if _placement_ring != null:
		_placement_ring.visible = false


func _create_placement_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.56
	torus.rings = 48
	torus.ring_segments = 8

	_placement_material = StandardMaterial3D.new()
	_placement_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_placement_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_placement_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_placement_material.no_depth_test = true
	_placement_material.albedo_color = Color(0.35, 1.0, 0.65, 0.85)

	_placement_ring = MeshInstance3D.new()
	_placement_ring.name = "PlacementRing"
	_placement_ring.mesh = torus
	_placement_ring.material_override = _placement_material
	_placement_ring.visible = false
	_hand.hold_point.add_child(_placement_ring)


func _set_ring_state(valid: bool) -> void:
	if _placement_ring == null:
		return
	_placement_ring.visible = _held != null
	if _held == null:
		return
	# O anel fica no pé da peça (footprint do tile), não na pinça.
	_placement_ring.position = Vector3(0.0, -_held.get_grip_height(), 0.0)
	_placement_material.albedo_color = (
		Color(0.35, 1.0, 0.65, 0.85)
		if valid
		else Color(1.0, 0.35, 0.35, 0.85)
	)
