extends TileMapLayer

var _office: Node = null
var _rest_door_tile_cache: Dictionary = {}
var _rest_door_hidden: bool = false
const _EXTRA_DOOR_VISUAL_GROUPS: Array[Array] = [
	[
		Vector2i(29, 22), Vector2i(30, 22), Vector2i(31, 22), Vector2i(32, 22),
		Vector2i(29, 23), Vector2i(30, 23), Vector2i(31, 23), Vector2i(32, 23),
	],
	[
		Vector2i(5, 11), Vector2i(6, 11), Vector2i(7, 11), Vector2i(8, 11),
		Vector2i(5, 12), Vector2i(6, 12), Vector2i(7, 12), Vector2i(8, 12),
	],
]

func setup(office: Node) -> void:
	_office = office

func cache_rest_door_tiles() -> void:
	if _office == null:
		return
	_rest_door_tile_cache.clear()
	for cell in _all_door_visual_cells():
		var source_id: int = get_cell_source_id(cell)
		if source_id < 0:
			continue
		_rest_door_tile_cache[cell] = {
			"source_id": source_id,
			"atlas_coords": get_cell_atlas_coords(cell),
			"alternative_tile": get_cell_alternative_tile(cell),
		}

func update_rest_door_visibility() -> void:
	if _office == null:
		return

	var occupied: bool = false
	for actor in _door_trigger_actors():
		if not (actor is Node2D):
			continue
		var agent: Node2D = actor as Node2D
		var cell: Vector2i = _office._world_to_cell(agent.global_position)
		if is_rest_door_visual_cell(cell):
			occupied = true
			break

	if occupied and not _rest_door_hidden:
		hide_rest_door_tiles()
	elif not occupied and _rest_door_hidden:
		restore_rest_door_tiles()

func is_rest_door_visual_cell(cell: Vector2i) -> bool:
	if _office == null:
		return false
	for c in _all_door_visual_cells():
		if c == cell:
			return true
	return false

func hide_rest_door_tiles() -> void:
	if _office == null:
		return
	for cell in _all_door_visual_cells():
		set_cell(cell, -1, Vector2i(-1, -1), 0)
	_rest_door_hidden = true

func restore_rest_door_tiles() -> void:
	if _office == null:
		return
	for cell in _all_door_visual_cells():
		if not _rest_door_tile_cache.has(cell):
			continue
		var tile_info: Dictionary = _rest_door_tile_cache[cell] as Dictionary
		set_cell(
			cell,
			int(tile_info.get("source_id", -1)),
			tile_info.get("atlas_coords", Vector2i(-1, -1)),
			int(tile_info.get("alternative_tile", 0))
		)
	_rest_door_hidden = false

func _all_door_visual_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for base_cell in _office.REST_DOOR_VISUAL_CELLS:
		cells.append(base_cell)
	for group in _EXTRA_DOOR_VISUAL_GROUPS:
		for cell in group:
			cells.append(cell)
	return cells

func _door_trigger_actors() -> Array[Node]:
	var out: Array[Node] = []
	var seen: Dictionary = {}
	if _office != null and _office._agents_root != null:
		for child in _office._agents_root.get_children():
			out.append(child)
			seen[child] = true
	for node in get_tree().get_nodes_in_group("door_trigger_actor"):
		if seen.has(node):
			continue
		out.append(node)
		seen[node] = true
	return out
