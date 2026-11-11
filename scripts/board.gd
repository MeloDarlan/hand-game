extends Node3D
class_name Board

## Tabuleiro isométrico: a malha e o caminho são visuais; a grade continua
## sendo a fonte de verdade para ocupação e posicionamento das torres.
## A estrada visual vem de um GLB simples, com cores chapadas e sem texturas de imagem.

const TILE_HEIGHT := 0.14
const INVALID_CELL := Vector2i(-999, -999)
const PROTOTYPE_MAP_PATH := "res://assets/maps/arena_prototipo.glb"

@export var grid_size := Vector2i(9, 9)
@export var tile_size := 1.0
@export var use_prototype_map := true
@export var buildable_color_a := Color(0.41, 0.59, 0.36)
@export var buildable_color_b := Color(0.37, 0.54, 0.33)
@export var path_color := Color(0.76, 0.64, 0.47)
@export var highlight_valid_color := Color(0.35, 1.0, 0.65, 0.5)
@export var highlight_invalid_color := Color(1.0, 0.3, 0.3, 0.5)
@export var range_color := Color(0.45, 0.9, 1.0, 0.35)
@export var hand_preview_color := Color(0.35, 0.85, 1.0, 0.42)
@export var hand_ring_color := Color(0.35, 0.85, 1.0, 0.32)

## Caminho em células. Vazio = rota serpentina de três faixas.
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
var _using_external_map := false


func _ready() -> void:
	if path_cells.is_empty():
		path_cells = _default_path()
	_path_lookup.clear()
	for cell in path_cells:
		_path_lookup[cell] = true
	_build()


func _default_path() -> Array:
	# Três faixas horizontais, conectadas nas bordas. A mesma sequência é
	# usada na geometria arena_prototipo.glb.
	var cells: Array = []
	var z := grid_size.y - 1
	var direction := 1
	var row_spacing := maxi(1, int((grid_size.y - 1) / 2.0))

	while true:
		if direction > 0:
			for x in grid_size.x:
				cells.append(Vector2i(x, z))
		else:
			for x in range(grid_size.x - 1, -1, -1):
				cells.append(Vector2i(x, z))

		if z == 0:
			break

		var next_z := maxi(z - row_spacing, 0)
		var connector_x := grid_size.x - 1 if direction > 0 else 0
		for connector_z in range(z - 1, next_z - 1, -1):
			cells.append(Vector2i(connector_x, connector_z))

		z = next_z
		direction *= -1
	return cells


func _build() -> void:
	if _built:
		return
	_built = true

	if use_prototype_map:
		var map_resource := load(PROTOTYPE_MAP_PATH) as PackedScene
		if map_resource != null and grid_size == Vector2i(9, 9) and is_equal_approx(tile_size, 1.0):
			var map_instance := map_resource.instantiate()
			map_instance.name = "PrototypeMap"
			add_child(map_instance)
			_using_external_map = true
			_apply_prototype_map_materials(map_instance)
		else:
			push_warning("Board: mapa de protótipo indisponível ou escala diferente; usando o tabuleiro procedural.")

	if not _using_external_map:
		_build_fallback_tiles()
		_build_markers()

	# The road is generated with native Godot meshes on top of the imported
	# board. This is a deliberate safety net: the route remains visible even
	# when a GLB importer drops material or vertex-colour information.
	_build_runtime_road_overlay()
	_build_preview()


func _apply_prototype_map_materials(root: Node) -> void:
	var palette := {
		"Prototype_Foundation": Color8(55, 65, 72),
		"Prototype_Rim_North": Color8(91, 105, 111),
		"Prototype_Rim_South": Color8(91, 105, 111),
		"Prototype_Rim_West": Color8(91, 105, 111),
		"Prototype_Rim_East": Color8(91, 105, 111),
		"Grass_Tiles_A": Color8(104, 151, 93),
		"Grass_Tiles_B": Color8(95, 140, 85),
		"Road_Edge": Color8(125, 91, 61),
		"Road_Surface": Color8(194, 164, 119),
		"Spawn_Post_Left": Color8(166, 92, 72),
		"Spawn_Post_Right": Color8(166, 92, 72),
		"Spawn_Top": Color8(166, 92, 72),
		"Core_Base": Color8(82, 104, 118),
		"Core_Ring": Color8(76, 178, 199),
		"Core_Crystal": Color8(91, 203, 224),
	}
	_apply_material_palette_recursive(root, palette)


func _apply_material_palette_recursive(node: Node, palette: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var lookup_name := String(mesh_node.name)
		if not palette.has(lookup_name) and mesh_node.mesh != null:
			lookup_name = String(mesh_node.mesh.resource_name)
		if palette.has(lookup_name):
			mesh_node.material_override = _make_flat_material(palette[lookup_name])
		# The route is redrawn below with native BoxMesh instances. Hide the
		# imported ribbon to avoid any z-fighting or stale material from the GLB.
		if lookup_name == "Road_Edge" or lookup_name == "Road_Surface":
			mesh_node.visible = false
	for child in node.get_children():
		_apply_material_palette_recursive(child, palette)


func _make_flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_runtime_road_overlay() -> void:
	var road_root := Node3D.new()
	road_root.name = "RuntimeRoadOverlay"
	add_child(road_root)
	var edge_material := _make_flat_material(Color8(125, 91, 61))
	var road_material := _make_flat_material(Color8(194, 164, 119))
	var edge_height := 0.045
	var road_height := 0.035
	var edge_y := 0.045
	var road_y := 0.082
	var border_width := tile_size * 0.98
	var surface_width := tile_size * 0.82
	var border_gap := tile_size * 0.02
	var surface_gap := tile_size * 0.18

	# Slightly inset square pads plus short connectors make a continuous
	# Manhattan road with crisp 90-degree turns and no texture dependency.
	for cell in path_cells:
		var center := _cell_local(cell)
		_add_road_box(road_root, "RoadBorderCell", center + Vector3(0.0, edge_y, 0.0), Vector3(border_width, edge_height, border_width), edge_material)
		_add_road_box(road_root, "RoadSurfaceCell", center + Vector3(0.0, road_y, 0.0), Vector3(surface_width, road_height, surface_width), road_material)

	for i in range(path_cells.size() - 1):
		var a := _cell_local(path_cells[i])
		var b := _cell_local(path_cells[i + 1])
		var midpoint := (a + b) * 0.5
		var is_horizontal := not is_equal_approx(a.x, b.x)
		var edge_size := Vector3(border_gap, edge_height, border_width) if is_horizontal else Vector3(border_width, edge_height, border_gap)
		var road_size := Vector3(surface_gap, road_height, surface_width) if is_horizontal else Vector3(surface_width, road_height, surface_gap)
		_add_road_box(road_root, "RoadBorderConnector", midpoint + Vector3(0.0, edge_y, 0.0), edge_size, edge_material)
		_add_road_box(road_root, "RoadSurfaceConnector", midpoint + Vector3(0.0, road_y, 0.0), road_size, road_material)


func _add_road_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)


func _build_fallback_tiles() -> void:
	var tiles_root := Node3D.new()
	tiles_root.name = "Tiles"
	add_child(tiles_root)

	var base := MeshInstance3D.new()
	base.name = "BoardFoundation"
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(grid_size.x * tile_size + 0.35, 0.22, grid_size.y * tile_size + 0.35)
	base.mesh = base_mesh
	var base_material := _make_tile_material(Color(0.22, 0.27, 0.30))
	base.material_override = base_material
	base.position.y = -0.17
	add_child(base)

	var grass_tile_mesh := BoxMesh.new()
	grass_tile_mesh.size = Vector3(tile_size * 0.94, TILE_HEIGHT, tile_size * 0.94)
	var grass_a := _make_tile_material(buildable_color_a)
	var grass_b := _make_tile_material(buildable_color_b)

	for z in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, z)
			var tile := MeshInstance3D.new()
			tile.mesh = grass_tile_mesh
			tile.material_override = grass_a if (x + z) % 2 == 0 else grass_b
			tile.position = _cell_local(cell) + Vector3(0.0, -TILE_HEIGHT * 0.5, 0.0)
			tiles_root.add_child(tile)


func _make_tile_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic = 0.0
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
	_highlight.position.y = 0.04
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
	_range_ring.position.y = 0.055
	_range_ring.visible = false
	add_child(_range_ring)

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
	_hand_highlight.position.y = 0.045
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
	_hand_ring.position.y = 0.06
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
		var point := cell_to_world(cell)
		# Keep enemy feet just above the top face of the runtime road overlay.
		point.y = 0.102
		points.append(point)
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
	_highlight.global_position = cell_to_world(cell) + Vector3(0.0, 0.045, 0.0)
	_highlight_material.albedo_color = highlight_valid_color if valid else highlight_invalid_color


func hide_highlight() -> void:
	if _highlight:
		_highlight.visible = false


func show_range(world_position: Vector3, radius: float) -> void:
	_range_ring.visible = true
	_range_ring.global_position = world_position + Vector3(0.0, 0.06, 0.0)
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
	_hand_highlight.global_position = cell_to_world(cell) + Vector3(0.0, 0.05, 0.0)
	_hand_ring.visible = true
	_hand_ring.global_position = cell_to_world(cell) + Vector3(0.0, 0.06, 0.0)
	_hand_ring.scale = Vector3(maxf(radius, 0.1), 1.0, maxf(radius, 0.1))


func hide_hand_preview() -> void:
	if _hand_highlight:
		_hand_highlight.visible = false
	if _hand_ring:
		_hand_ring.visible = false
