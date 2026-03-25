extends Node

var _office: Node = null
var _astar: AStarGrid2D = null
var _nav_region: Rect2i = Rect2i(0, 0, 0, 0)
var _rest_door_inside_world: Vector2 = Vector2.ZERO
var _rest_door_outside_world: Vector2 = Vector2.ZERO
@onready var _floor_layer: TileMapLayer = $"../Layers/FloorLayer"
@onready var _items_layer: TileMapLayer = $"../Layers/ItemsLayer"
@onready var _desk_layer: TileMapLayer = $"../Layers/DeskLayer"

func setup(office: Node) -> void:
	_office = office

func move_agent_to(agent: Node2D, target_world: Vector2) -> void:
	if _office == null or agent == null:
		return
	var meta: Dictionary = _office._agent_meta.get(agent, {})
	var is_manager: bool = String(meta.get("role", "")) == String(_office.ROLE_MANAGER)
	if is_manager and agent.has_method("move_to_direct"):
		agent.call("move_to_direct", target_world)
		return

	var resolved_target: Vector2 = resolve_reachable_nav_target(agent.global_position, target_world)
	agent.call("move_to", resolved_target)

func resolve_reachable_nav_target(from_world: Vector2, target_world: Vector2) -> Vector2:
	if _office == null:
		return target_world
	var world2d_ref: World2D = _office.get_world_2d()
	if world2d_ref == null:
		return target_world

	var nav_map: RID = world2d_ref.navigation_map
	if not nav_map.is_valid():
		return target_world

	var direct_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, target_world, true)
	if not direct_path.is_empty():
		return target_world

	var closest_on_nav: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, target_world)
	var closest_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, closest_on_nav, true)
	if not closest_path.is_empty():
		return closest_on_nav

	var radii: PackedFloat32Array = PackedFloat32Array([12.0, 24.0, 36.0, 48.0, 64.0])
	for r in radii:
		for i in range(0, 12):
			var ang: float = TAU * float(i) / 12.0
			var p: Vector2 = target_world + Vector2.RIGHT.rotated(ang) * r
			var p_on_nav: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, p)
			var p_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, p_on_nav, true)
			if not p_path.is_empty():
				return p_on_nav

	return target_world

func build_nav_grid() -> void:
	if _office == null:
		return
	var layers: Array[TileMapLayer] = [_floor_layer, _items_layer, _desk_layer]
	var has_any_cell: bool = false
	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = 0
	var max_y: int = 0

	for layer in layers:
		var used_cells: Array[Vector2i] = layer.get_used_cells()
		for cell in used_cells:
			if not has_any_cell:
				min_x = cell.x
				min_y = cell.y
				max_x = cell.x
				max_y = cell.y
				has_any_cell = true
			else:
				min_x = mini(min_x, cell.x)
				min_y = mini(min_y, cell.y)
				max_x = maxi(max_x, cell.x)
				max_y = maxi(max_y, cell.y)

	if not has_any_cell:
		return

	var margin: int = 2
	_nav_region = Rect2i(min_x - margin, min_y - margin, (max_x - min_x + 1) + margin * 2, (max_y - min_y + 1) + margin * 2)

	_astar = AStarGrid2D.new()
	_astar.region = _nav_region
	_astar.cell_size = Vector2(1.0, 1.0)
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

	for x in range(_nav_region.position.x, _nav_region.position.x + _nav_region.size.x):
		for y in range(_nav_region.position.y, _nav_region.position.y + _nav_region.size.y):
			var cell: Vector2i = Vector2i(x, y)
			if is_cell_blocked(cell):
				_astar.set_point_solid(cell, true)

	force_open_door_cells()

func force_open_door_cells() -> void:
	if _office == null or _astar == null:
		return
	for center in _office.REST_DOOR_INSIDE_CELLS:
		for dx in range(-_office.door_clear_radius_cells, _office.door_clear_radius_cells + 1):
			for dy in range(-_office.door_clear_radius_cells, _office.door_clear_radius_cells + 1):
				var c: Vector2i = Vector2i(center.x + dx, center.y + dy)
				if _astar.is_in_boundsv(c):
					_astar.set_point_solid(c, false)
	for center in _office.REST_DOOR_OUTSIDE_CELLS:
		for dx in range(-_office.door_clear_radius_cells, _office.door_clear_radius_cells + 1):
			for dy in range(-_office.door_clear_radius_cells, _office.door_clear_radius_cells + 1):
				var c: Vector2i = Vector2i(center.x + dx, center.y + dy)
				if _astar.is_in_boundsv(c):
					_astar.set_point_solid(c, false)
	_rest_door_inside_world = cells_center_to_world(_office.REST_DOOR_INSIDE_CELLS)
	_rest_door_outside_world = cells_center_to_world(_office.REST_DOOR_OUTSIDE_CELLS)

func is_cell_blocked(cell: Vector2i) -> bool:
	if _office == null:
		return false
	if tile_has_collision(_items_layer, cell):
		return true
	if tile_has_collision(_desk_layer, cell):
		return true
	return false

func tile_has_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	var tile_data: TileData = layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_collision_polygons_count(0) > 0

func build_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array([end_world])

	var direct_path: PackedVector2Array = build_simple_world_path(start_world, end_world)
	if not direct_path.is_empty():
		return direct_path

	if bool(_office.force_rest_door_routing):
		var via_points: PackedVector2Array = build_path_via_rest_door(start_world, end_world)
		if not via_points.is_empty():
			return via_points

	return PackedVector2Array([end_world])

func build_path_via_rest_door(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _office == null:
		return PackedVector2Array()
	var first_gate: Vector2 = _rest_door_outside_world
	var second_gate: Vector2 = _rest_door_inside_world
	if start_world.x >= float(_office.rest_area_split_x):
		first_gate = _rest_door_inside_world
		second_gate = _rest_door_outside_world

	var seg1: PackedVector2Array = build_simple_world_path(start_world, first_gate)
	if seg1.is_empty():
		return PackedVector2Array()
	var seg2: PackedVector2Array = build_simple_world_path(first_gate, second_gate)
	if seg2.is_empty():
		return PackedVector2Array()
	var seg3: PackedVector2Array = build_simple_world_path(second_gate, end_world)
	if seg3.is_empty():
		return PackedVector2Array()

	return concat_paths(concat_paths(seg1, seg2), seg3)

func build_simple_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()

	var start_cell: Vector2i = find_nearest_walkable_cell(world_to_cell(start_world))
	var end_cell: Vector2i = find_nearest_walkable_cell(world_to_cell(end_world))
	if not _astar.is_in_boundsv(start_cell) or not _astar.is_in_boundsv(end_cell):
		return PackedVector2Array()

	var id_path: Array[Vector2i] = _astar.get_id_path(start_cell, end_cell)
	if id_path.is_empty():
		return PackedVector2Array()

	var world_path: PackedVector2Array = PackedVector2Array()
	for cell in id_path:
		world_path.append(cell_to_world(cell))
	if world_path[world_path.size() - 1].distance_to(end_world) > 1.0:
		world_path.append(end_world)
	return world_path

func concat_paths(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if a.is_empty():
		return b
	if b.is_empty():
		return a

	var out: PackedVector2Array = a
	var start_idx: int = 0
	if out[out.size() - 1].distance_to(b[0]) < 1.0:
		start_idx = 1
	for i in range(start_idx, b.size()):
		out.append(b[i])
	return out

func cells_center_to_world(cells: Array[Vector2i]) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for c in cells:
		sum += cell_to_world(c)
	return sum / float(cells.size())

func find_nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if _office == null or _astar == null:
		return cell
	if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
		return cell

	for r in range(1, int(_office.path_search_radius_cells) + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c: Vector2i = Vector2i(cell.x + dx, cell.y + dy)
				if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
					return c

	return cell

func world_to_cell(world_pos: Vector2) -> Vector2i:
	if _office == null:
		return Vector2i.ZERO
	var local_pos: Vector2 = _floor_layer.to_local(world_pos)
	return _floor_layer.local_to_map(local_pos)

func cell_to_world(cell: Vector2i) -> Vector2:
	if _office == null:
		return Vector2.ZERO
	var local_pos: Vector2 = _floor_layer.map_to_local(cell)
	return _floor_layer.to_global(local_pos)
