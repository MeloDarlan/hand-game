extends Node

## Outline de oclusão da peça segurada.
##
## A ideia: a peça fica na palma, em frente à mão. Para marcar só a parte da
## peça que está "sobre" a mão (e não a parte que passa para fora, sobre o
## board), geramos duas máscaras de silhueta em SubViewports com a mesma câmera
## do jogo:
##   - mão (render layer própria)
##   - peça segurada (render layer própria)
## A interseção das duas máscaras é a parte coberta. O shader
## `occlusion_outline.gdshader` desenha o contorno só ao redor dessa interseção.
##
## O shader original é canvas_item; ele é aplicado num ColorRect restrito ao
## retângulo de tela da peça (performance) e amostra as duas máscaras em
## coordenadas de tela (SCREEN_UV).
##
## Além do outline, o mesmo mask da peça alimenta um blur de tela: a peça
## segurada fica na profundidade da mão (nítida no DOF), mas pertence ao
## tabuleiro. O raio do blur vem da profundidade da célula alvo, então a peça
## desfoca junto com o tile sob ela — e a mão continua fora do efeito.

const HAND_LAYER := 1 << 4
const PIECE_LAYER := 1 << 5
const OUTLINE_SHADER := preload("res://occlusion_outline.gdshader")
const BLUR_SHADER := preload("res://held_piece_dof.gdshader")

@export var hand_path: NodePath
@export var outline_color := Color(1.0, 0.6, 0.0, 1.0):
	set(value):
		outline_color = value
		if _outline_material != null:
			_outline_material.set_shader_parameter("outline_color", value)
@export_range(1, 5) var outline_size := 2:
	set(value):
		outline_size = value
		if _outline_material != null:
			_outline_material.set_shader_parameter("outline_size", value)
@export_range(0.25, 1.0, 0.05) var mask_resolution_scale := 1.0
@export var piece_blur_enabled := true
## Raio máximo do blur da peça em pixels a 720p (escala junto com o viewport).
@export_range(0.0, 24.0, 0.5) var piece_blur_max_pixels := 10.0

var _hand: HandController
var _camera: Camera3D
var _main_viewport: Viewport
var _hand_mask_viewport: SubViewport
var _piece_mask_viewport: SubViewport
var _hand_mask_camera: Camera3D
var _piece_mask_camera: Camera3D
var _outline_layer: CanvasLayer
var _outline_rect: ColorRect
var _outline_material: ShaderMaterial
var _blur_rect: ColorRect
var _blur_material: ShaderMaterial
var _active_piece: TowerPiece
var _saved_layers := {}


func _ready() -> void:
	_hand = get_node_or_null(hand_path) as HandController
	if _hand == null:
		push_warning("OcclusionOutline: hand_path não aponta para a HandController.")
		return

	_main_viewport = get_viewport()
	_camera = _main_viewport.get_camera_3d()
	if _camera == null:
		push_warning("OcclusionOutline: nenhuma câmera ativa.")
		return

	_setup_hand_layers()
	_setup_viewports()
	_setup_outline()


func _process(_delta: float) -> void:
	if _hand == null or _camera == null or _outline_rect == null:
		return

	_sync_cameras()

	var held := _hand.get_held_body() as TowerPiece
	if held != null:
		if held != _active_piece:
			_activate(held)
		_update_outline_rect(held)
		_update_blur_rect(held)
	elif _active_piece != null:
		_deactivate()


func _exit_tree() -> void:
	_deactivate()


func _setup_hand_layers() -> void:
	var model := _hand.get_node_or_null("PalmPivot/Model")
	if model == null:
		return
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.layers = HAND_LAYER


func _setup_viewports() -> void:
	_hand_mask_viewport = _make_mask_viewport("HandMask", HAND_LAYER)
	_piece_mask_viewport = _make_mask_viewport("PieceMask", PIECE_LAYER)
	_hand_mask_camera = _hand_mask_viewport.get_node("MaskCamera") as Camera3D
	_piece_mask_camera = _piece_mask_viewport.get_node("MaskCamera") as Camera3D
	_resize_masks()


func _make_mask_viewport(viewport_name: String, layer: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.own_world_3d = false
	viewport.world_3d = _main_viewport.world_3d
	viewport.size = _target_mask_size()
	viewport.handle_input_locally = false
	add_child(viewport)

	var camera := Camera3D.new()
	camera.name = "MaskCamera"
	camera.current = true
	camera.cull_mask = layer
	camera.environment = _make_mask_environment()
	viewport.add_child(camera)
	return viewport


func _make_mask_environment() -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return environment


func _target_mask_size() -> Vector2i:
	var size := _main_viewport.get_visible_rect().size
	var scaled := size * mask_resolution_scale
	return Vector2i(maxi(int(scaled.x), 1), maxi(int(scaled.y), 1))


func _resize_masks() -> void:
	var target := _target_mask_size()
	if _hand_mask_viewport.size != target:
		_hand_mask_viewport.size = target
		_piece_mask_viewport.size = target


func _sync_cameras() -> void:
	_resize_masks()
	_sync_camera(_hand_mask_camera, HAND_LAYER)
	_sync_camera(_piece_mask_camera, PIECE_LAYER)


func _sync_camera(mask_camera: Camera3D, layer: int) -> void:
	mask_camera.global_transform = _camera.global_transform
	mask_camera.projection = _camera.projection
	mask_camera.size = _camera.size
	mask_camera.near = _camera.near
	mask_camera.far = _camera.far
	mask_camera.fov = _camera.fov
	mask_camera.keep_aspect = _camera.keep_aspect
	mask_camera.h_offset = _camera.h_offset
	mask_camera.v_offset = _camera.v_offset
	mask_camera.cull_mask = layer


func _setup_outline() -> void:
	_outline_layer = CanvasLayer.new()
	_outline_layer.name = "OutlineLayer"
	_outline_layer.layer = 0
	add_child(_outline_layer)

	# O blur é criado antes do outline para ficar por baixo do contorno.
	_blur_rect = ColorRect.new()
	_blur_rect.name = "PieceBlurRect"
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_blur_rect.visible = false
	_outline_layer.add_child(_blur_rect)

	_blur_material = ShaderMaterial.new()
	_blur_material.shader = BLUR_SHADER
	_blur_material.set_shader_parameter("piece_mask", _piece_mask_viewport.get_texture())
	_blur_rect.material = _blur_material

	_outline_rect = ColorRect.new()
	_outline_rect.name = "OutlineRect"
	_outline_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outline_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_outline_rect.visible = false
	_outline_layer.add_child(_outline_rect)

	_outline_material = ShaderMaterial.new()
	_outline_material.shader = OUTLINE_SHADER
	_outline_material.set_shader_parameter("outline_color", outline_color)
	_outline_material.set_shader_parameter("outline_size", outline_size)
	_outline_material.set_shader_parameter("hand_mask", _hand_mask_viewport.get_texture())
	_outline_material.set_shader_parameter("piece_mask", _piece_mask_viewport.get_texture())
	_outline_rect.material = _outline_material


func _activate(piece: TowerPiece) -> void:
	if _active_piece != null:
		_deactivate()

	_active_piece = piece
	_saved_layers.clear()
	for mesh in piece.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh as MeshInstance3D
		if mesh_instance == null:
			continue
		_saved_layers[mesh_instance] = mesh_instance.layers
		mesh_instance.layers = PIECE_LAYER

	_hand_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_piece_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_outline_rect.visible = true
	_update_outline_rect(piece)
	_update_blur_rect(piece)


func _deactivate() -> void:
	for mesh in _saved_layers.keys():
		if is_instance_valid(mesh):
			mesh.layers = _saved_layers[mesh]
	_saved_layers.clear()
	_active_piece = null

	if _hand_mask_viewport != null:
		_hand_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _piece_mask_viewport != null:
		_piece_mask_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _outline_rect != null:
		_outline_rect.visible = false
	if _blur_rect != null:
		_blur_rect.visible = false


func _update_outline_rect(piece: TowerPiece) -> void:
	if _camera == null or _outline_rect == null:
		return

	var viewport_size := _main_viewport.get_visible_rect().size
	var center := piece.global_position + Vector3.UP * 0.5
	var screen_center := _camera.unproject_position(center)

	var pixels_per_unit := 70.0
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _camera.size > 0.001:
		pixels_per_unit = viewport_size.y / _camera.size

	var rect_half := 1.15 * pixels_per_unit + float(outline_size) + 8.0
	_outline_rect.position = screen_center - Vector2(rect_half, rect_half)
	_outline_rect.size = Vector2(rect_half * 2.0, rect_half * 2.0)


## Raio do blur da peça em pixels de tela. Usa a profundidade da célula alvo
## (o pé da peça) e a mesma rampa do DOF da câmera, então a peça desfoca
## exatamente quando o tile sob ela desfoca.
func _blur_radius_pixels() -> float:
	if not piece_blur_enabled or _camera == null or _hand == null or _main_viewport == null:
		return 0.0

	var attributes := _camera.attributes as CameraAttributesPractical
	if attributes == null or not attributes.dof_blur_far_enabled:
		return 0.0

	var target := _hand.get_target_position()
	var view_position := _camera.global_transform.affine_inverse() * target
	var depth := -view_position.z

	var far_distance := attributes.dof_blur_far_distance
	var transition := maxf(attributes.dof_blur_far_transition, 0.001)
	var ratio := clampf((depth - far_distance) / transition, 0.0, 1.0)
	if ratio <= 0.0:
		return 0.0

	# O amount do DOF é normalizado; calibramos o raio em pixels pela altura
	# real do render target (o stretch pode diferir do visible_rect).
	var amount_scale := attributes.dof_blur_amount / 0.1
	var render_height := float(_main_viewport.get_texture().get_size().y)
	if render_height <= 0.0:
		render_height = 720.0
	return ratio * piece_blur_max_pixels * amount_scale * (render_height / 720.0)


func _update_blur_rect(piece: TowerPiece) -> void:
	if _camera == null or _blur_rect == null or _blur_material == null:
		return

	var radius := _blur_radius_pixels()
	if radius < 0.5:
		_blur_rect.visible = false
		return

	var viewport_size := _main_viewport.get_visible_rect().size
	var center := piece.global_position + Vector3.UP * 0.5
	var screen_center := _camera.unproject_position(center)

	var pixels_per_unit := 70.0
	if _camera.projection == Camera3D.PROJECTION_ORTHOGONAL and _camera.size > 0.001:
		pixels_per_unit = viewport_size.y / _camera.size

	var margin := piece_blur_max_pixels * (viewport_size.y / 720.0) + 10.0
	var rect_half := 1.15 * pixels_per_unit + margin
	_blur_rect.position = screen_center - Vector2(rect_half, rect_half)
	_blur_rect.size = Vector2(rect_half * 2.0, rect_half * 2.0)
	_blur_material.set_shader_parameter("blur_radius_px", radius)
	_blur_rect.visible = true
