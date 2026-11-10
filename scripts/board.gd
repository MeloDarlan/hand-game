extends Node3D
class_name Board

## Tabuleiro isométrico do tower defense.
## Gera os tiles e o caminho por código e é a fonte de verdade da grade:
## conversão célula <-> mundo, ocupação e validação de construção.

const TILE_HEIGHT := 0.14
const INVALID_CELL := Vector2i(-999, -999)

@export var grid_size := Vector2i(9, 9)
@export var tile_size := 1.0
@export var buildable_color_a := Color(0.17, 0.21, 0.28)
@export var buildable_color_b := Color(0.14, 0.18, 0.24)
@export var path_color := Color(0.5, 0.37, 0.26)
@export var highlight_valid_color := Color(0.35, 1.0, 0.65, 0.5)
@export var highlight_invalid_color := Color(1.0, 0.3, 0.3, 0.5)
@export var range_color := Color(0.45, 0.9, 1.0, 0.35)
## Indicador ciano da região da mão/GrabArea.
@export var hand_preview_color := Color(0.35, 0.85, 1.0, 0.42)
@export var hand_ring_color := Color(0.35, 0.85, 1.0, 0.32)

## Caminho em células. Vazio = serpentina automática.
var path_cells: Array = []

var _path_lookup := {}
var _occupancy := {}
var _highlight: MeshInstance3D
var _highlight_material: StandardMaterial3D
var _range_ring: MeshInstance3D
var _hand_highlight: MeshInstance3D
var _hand_highlight_material: StandardMaterial3D
var _hand_ring: MeshInstance3D
var _built := false


func _ready() -> void:
	if path_cells.is_empty():
		path_cells = _default_path()
	for cell in path_cells:
		_path_lookup[cell] = true
	_build()


func _default_path() -> Array:
	# Serpentina de (0, altura-1) até o canto oposto.
	var cells: Array = []
	var z := grid_size.y - 1
	var left_to_right := true
	while z >= 0:
		if left_to_right:
			for x in grid_size.x:
				cells.append(Vector2i(x, z))
		else:
			for x in range(grid_size.x - 1, -1, -1):
				cells.append(Vector2i(x, z))

		if z - 1 < 0:
			break

		var connector_x := grid_size.x - 1 if left_to_right else 0
		cells.append(Vector2i(connector_x, z - 1))
		z -= 2
		left_to_right = not left_to_right
	return cells


func _build() -> void:
	if _built:
		return
	_built = true

	var tiles_root := Node3D.new()
	tiles_root.name = "Tiles"
	add_child(tiles_root)

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(tile_size * 0.96, TILE_HEIGHT, tile_size * 0.96)

	var mat_a := _make_tile_material(buildable_color_a)
	var mat_b := _make_tile_material(buildable_color_b)
	var mat_path := _make_tile_material(path_color)

	for z in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, z)
			var tile := MeshInstance3D.new()
			tile.mesh = tile_mesh
			if _path_lookup.has(cell):
				tile.material_override = mat_path
			elif (x + z) % 2 == 0:
				tile.material_override = mat_a
			else:
				tile.material_override = mat_b
			tile.position = _cell_local(cell) + Vector3(0.0, -TILE_HEIGHT * 0.5, 0.0)
			tiles_root.add_child(tile)

	_build_markers()
	_build_preview()


func _make_tile_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.metallic = 0.05
	return material


func _build_markers() -> void:
	if path_cells.is_empty():
		return
	var markers := Node3D.new()
	markers.name = "Markers"
	add_child(markers)

	var spawn := _make_marker(Color(0.95, 0.3, 0.3), 0.55)
	spawn.position = _cell_local(path_cells[0])
	markers.add_child(spawn)

	var core := _make_marker(Color(0.3, 0.85, 1.0), 1.0)
	core.position = _cell_local(path_cells[path_cells.size() - 1])
	markers.add_child(core)


func _make_marker(color: Color, height: float) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.1
	mesh.bottom_radius = 0.26
	mesh.height = height
	mesh.radial_segments = 6
	mesh_instance.mesh = mesh
	mesh_instance.position.y = height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.2
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	return root


func _build_preview() -> void:
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_material.albedo_color = highlight_valid_color

	var plane := PlaneMesh.new()
	plane.size = Vector2(tile_size * 0.9, tile_size * 0.9)
	_highlight = MeshInstance3D.new()
	_highlight.name = "Highlight"
	_highlight.mesh = plane
	_highlight.material_override = _highlight_material
	_highlight.position.y = 0.03
	_highlight.visible = false
	add_child(_highlight)

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_material.albedo_color = range_color

	var torus := TorusMesh.new()
	torus.inner_radius = 0.985
	torus.outer_radius = 1.0
	torus.rings = 64
	torus.ring_segments = 8

	_range_ring = MeshInstance3D.new()
	_range_ring.name = "RangeRing"
	_range_ring.mesh = torus
	_range_ring.material_override = ring_material
	_range_ring.position.y = 0.04
	_range_ring.visible = false
	add_child(_range_ring)

	# Preview da mão/GrabArea: tile + anel ciano, independentes do placement.
	_hand_highlight_material = StandardMaterial3D.new()
	_hand_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hand_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hand_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hand_highlight_material.albedo_color = hand_preview_color

	var hand_plane := PlaneMesh.new()
	hand_plane.size = Vector2(tile_size * 0.9, tile_size * 0.9)
	_hand_highlight = MeshInstance3D.new()
	_hand_highlight.name = "HandHighlight"
	_hand_highlight.mesh = hand_plane
	_hand_highlight.material_override = _hand_highlight_material
	_hand_highlight.visible = false
	add_child(_hand_highlight)

	var hand_ring_material := StandardMaterial3D.new()
	hand_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hand_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hand_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hand_ring_material.albedo_color = hand_ring_color

	var hand_torus := TorusMesh.new()
	hand_torus.inner_radius = 0.985
	hand_torus.outer_radius = 1.0
	hand_torus.rings = 64
	hand_torus.ring_segments = 8

	_hand_ring = MeshInstance3D.new()
	_hand_ring.name = "HandRing"
	_hand_ring.mesh = hand_torus
	_hand_ring.material_override = hand_ring_material
	_hand_ring.visible = false
	add_child(_hand_ring)


func _cell_local(cell: Vector2i) -> Vector3:
	return Vector3(
		(cell.x - (grid_size.x - 1) * 0.5) * tile_size,
		0.0,
		(cell.y - (grid_size.y - 1) * 0.5) * tile_size
	)


func cell_to_world(cell: Vector2i) -> Vector3:
	return to_global(_cell_local(cell))


func world_to_cell(world: Vector3) -> Vector2i:
	var local := to_local(world)
	return Vector2i(
		roundi(local.x / tile_size + (grid_size.x - 1) * 0.5),
		roundi(local.z / tile_size + (grid_size.y - 1) * 0.5)
	)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_path(cell: Vector2i) -> bool:
	return _path_lookup.has(cell)


func is_occupied(cell: Vector2i) -> bool:
	return _occupancy.has(cell)


func is_buildable(cell: Vector2i) -> bool:
	return is_in_bounds(cell) and not is_path(cell) and not is_occupied(cell)


func register_tower(cell: Vector2i, tower: Node3D) -> void:
	_occupancy[cell] = tower


func unregister_tower(cell: Vector2i) -> void:
	_occupancy.erase(cell)


func get_tower(cell: Vector2i) -> Node3D:
	return _occupancy.get(cell) as Node3D


func get_path_world_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for cell in path_cells:
		points.append(cell_to_world(cell))
	return points


func clamp_world_position(world: Vector3, margin: float) -> Vector3:
	var limit_x := grid_size.x * tile_size * 0.5 + margin
	var limit_z := grid_size.y * tile_size * 0.5 + margin
	var local := to_local(world)
	local.x = clampf(local.x, -limit_x, limit_x)
	local.z = clampf(local.z, -limit_z, limit_z)
	return to_global(local)


func show_highlight(cell: Vector2i, valid: bool) -> void:
	if not is_in_bounds(cell):
		hide_highlight()
		return
	_highlight.visible = true
	_highlight.global_position = cell_to_world(cell) + Vector3(0.0, 0.03, 0.0)
	_highlight_material.albedo_color = highlight_valid_color if valid else highlight_invalid_color


func hide_highlight() -> void:
	if _highlight:
		_highlight.visible = false


func show_range(world_position: Vector3, radius: float) -> void:
	_range_ring.visible = true
	_range_ring.global_position = world_position + Vector3(0.0, 0.04, 0.0)
	_range_ring.scale = Vector3(radius, 1.0, radius)


func hide_range() -> void:
	if _range_ring:
		_range_ring.visible = false


func hide_preview() -> void:
	hide_highlight()
	hide_range()


func show_hand_preview(cell: Vector2i, radius: float) -> void:
	if not is_in_bounds(cell):
		hide_hand_preview()
		return
	_hand_highlight.visible = true
	_hand_highlight.global_position = cell_to_world(cell) + Vector3(0.0, 0.035, 0.0)
	_hand_ring.visible = true
	_hand_ring.global_position = cell_to_world(cell) + Vector3(0.0, 0.045, 0.0)
	var ring_radius := maxf(radius, 0.1)
	_hand_ring.scale = Vector3(ring_radius, 1.0, ring_radius)


func hide_hand_preview() -> void:
	if _hand_highlight:
		_hand_highlight.visible = false
	if _hand_ring:
		_hand_ring.visible = false
