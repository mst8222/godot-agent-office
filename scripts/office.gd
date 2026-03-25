extends Node2D

const AGENT_SCENE: PackedScene = preload("res://scenes/agent.tscn")
const ANIM_RESOURCE_DIR: String = "res://resources"
const ANIM_RESOURCE_SUFFIX: String = "_sprite_frames.tres"

const ROLE_MANAGER: String = "\u7ecf\u7406"
const ROLE_STAFF: String = "\u5458\u5de5"
const STATE_WORKING: String = "\u5de5\u4f5c\u4e2d"
const STATE_IDLE: String = "\u7a7a\u95f2"
const BUILD_LABEL_TAG: String = ""

@export var api_state_sync_interval_sec: float = 3.0
@export var idle_wander_interval_sec: float = 5.0
@export var idle_wander_radius: float = 48.0
@export var idle_move_chance: float = 0.35
@export var idle_pause_min_sec: float = 2.0
@export var idle_pause_max_sec: float = 6.0
@export var worker_rest_scatter_radius: float = 120.0
@export var worker_rest_min_distance: float = 36.0
@export var employee_job_pool: PackedStringArray = [
	"\u7a0b\u5e8f\u5458",
	"\u7b56\u5212",
	"\u7f8e\u672f",
	"\u6d4b\u8bd5",
	"\u8fd0\u8425"
]
@export var create_manager_if_missing: bool = true
@export var path_search_radius_cells: int = 8
@export var force_rest_door_routing: bool = true
@export var rest_area_split_x: float = 1280.0
@export var door_clear_radius_cells: int = 1
@export var use_api_label_text: bool = true
@export var api_base_url: String = "/api"
@export var api_fallback_base_urls: PackedStringArray = ["http://fnos.qiansom.top:5180/api", "http://192.168.3.161:5180/api", "http://localhost:5180/api", "http://127.0.0.1:5180/api"]
@export var show_api_debug_overlay: bool = true
@export var auto_show_api_debug_in_dev: bool = false
# @export var api_base_url: String = "http://192.168.3.161:5180/api"
# @export var api_fallback_base_urls: PackedStringArray = ["http://localhost:5180/api", "http://127.0.0.1:5180/api"]

const REST_DOOR_INSIDE_CELLS: Array[Vector2i] = [Vector2i(47, 17), Vector2i(48, 17)]
const REST_DOOR_OUTSIDE_CELLS: Array[Vector2i] = [Vector2i(47, 18), Vector2i(48, 18)]
const REST_DOOR_VISUAL_CELLS: Array[Vector2i] = [
	Vector2i(46, 17), Vector2i(47, 17), Vector2i(48, 17), Vector2i(49, 17),
	Vector2i(46, 18), Vector2i(47, 18), Vector2i(48, 18), Vector2i(49, 18)
]
const WORKER_REST_MIN_CELL: Vector2i = Vector2i(43, 5)
const WORKER_REST_MAX_CELL: Vector2i = Vector2i(52, 16)

@onready var _agents_root: Node = $Layers/Agents
@onready var _office_pos: Node = $OfficePos
@onready var _add_button: Button = $Button

@onready var _floor_layer: TileMapLayer = $Layers/FloorLayer
@onready var _items_layer: TileMapLayer = $Layers/ItemsLayer
@onready var _desk_layer: TileMapLayer = $Layers/DeskLayer

@onready var _worker_rest_pos: Marker2D = $OfficePos/WorkerRestPos
@onready var _manager_work_pos: Marker2D = $OfficePos/ManagerWorktPos
@onready var _manager_rest_pos: Marker2D = $OfficePos/ManagerRestPos

var _working_pos_markers: Array[Marker2D] = []
var _sprite_frames_pool: Array[SpriteFrames] = []
var _unused_sprite_frames_pool: Array[SpriteFrames] = []
var _last_assigned_frames: SpriteFrames = null

var _manager_agent: Node2D = null
var _agent_meta: Dictionary = {}

var _astar: AStarGrid2D = null
var _nav_region: Rect2i = Rect2i(0, 0, 0, 0)
var _rest_door_inside_world: Vector2 = Vector2.ZERO
var _rest_door_outside_world: Vector2 = Vector2.ZERO
var _busy_api: bool = false
var _selected_agent: Node2D = null
var _last_sync_error: String = ""
var _last_sync_error_time_sec: float = -99999.0
var _rest_door_tile_cache: Dictionary = {}
var _rest_door_hidden: bool = false

var _agent_form_dialog: ConfirmationDialog = null
var _agent_detail_dialog: AcceptDialog = null
var _agent_detail_text: RichTextLabel = null
var _agent_session_input: TextEdit = null
var _agent_session_send_btn: Button = null
var _agent_session_cancel_btn: Button = null
var _busy_session_submit: bool = false
var _form_fields: Dictionary = {}
var _staff_strip_layer: CanvasLayer = null
var _staff_strip_scroll: ScrollContainer = null
var _staff_strip_row: HBoxContainer = null
var _api_debug_layer: CanvasLayer = null
var _api_debug_label: RichTextLabel = null
var _api_debug_last_method: int = -1
var _api_debug_last_url: String = ""
var _api_debug_last_response_code: int = -1
var _api_debug_last_request_result: int = -1
var _api_debug_last_ok: bool = false
var _api_debug_last_network_error: bool = false
var _api_debug_last_error: String = ""
var _api_debug_last_raw_preview: String = ""
var _api_debug_last_has_auth: bool = false
var _api_debug_last_time_sec: float = -1.0
var _api_debug_next_refresh_sec: float = 0.0

func _ready() -> void:
	randomize()
	_collect_markers()
	_cache_rest_door_tiles()
	_load_sprite_frames_pool()
	_build_nav_grid()
	_build_agent_dialogs()
	_setup_staff_strip_ui()
	_setup_api_debug_overlay()
	_add_button.text = _ui_text_add_agent()
	_style_add_agent_button()
	_add_button.pressed.connect(_on_add_agent_pressed)

	for child in _agents_root.get_children():
		if child is Node2D:
			_setup_new_agent(child as Node2D, _manager_agent == null)

	if create_manager_if_missing and _manager_agent == null:
		var manager: Node2D = AGENT_SCENE.instantiate() as Node2D
		_agents_root.add_child(manager)
		manager.global_position = _manager_rest_pos.global_position
		_setup_new_agent(manager, true)
	_refresh_staff_strip_ui()

	var timer: Timer = Timer.new()
	timer.name = "ApiStateSyncTimer"
	timer.wait_time = maxf(api_state_sync_interval_sec, 1.0)
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_on_api_state_sync_tick)
	add_child(timer)

	call_deferred("_load_agents_from_api")

func _ui_text_add_agent() -> String:
	return char(0x6dfb) + char(0x52a0) + "Agent"

func _style_add_agent_button() -> void:
	if _add_button == null:
		return

	_add_button.custom_minimum_size = Vector2(132.0, 40.0)

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.16, 0.49, 0.81, 1.0)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.31, 0.67, 1.0, 0.95)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.21, 0.56, 0.90, 1.0)
	hover.border_color = Color(0.46, 0.76, 1.0, 1.0)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.11, 0.40, 0.71, 1.0)
	pressed.border_color = Color(0.31, 0.67, 1.0, 0.95)

	var disabled: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.24, 0.28, 0.34, 1.0)
	disabled.border_color = Color(0.34, 0.42, 0.52, 0.9)

	_add_button.add_theme_stylebox_override("normal", normal)
	_add_button.add_theme_stylebox_override("hover", hover)
	_add_button.add_theme_stylebox_override("pressed", pressed)
	_add_button.add_theme_stylebox_override("disabled", disabled)
	_add_button.add_theme_color_override("font_color", Color(0.97, 0.99, 1.0, 1.0))
	_add_button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	_add_button.add_theme_color_override("font_pressed_color", Color(0.97, 0.99, 1.0, 1.0))
	_add_button.add_theme_color_override("font_disabled_color", Color(0.72, 0.78, 0.86, 0.95))

func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if _api_debug_label != null and now >= _api_debug_next_refresh_sec:
		_refresh_api_debug_overlay()
		_api_debug_next_refresh_sec = now + 0.25
	_update_rest_door_visibility()

	for agent_key in _agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if not is_instance_valid(agent):
			continue

		var meta: Dictionary = _agent_meta[agent]
		if String(meta.get("state", "")) != STATE_IDLE:
			continue
		if agent.has_method("is_moving") and bool(agent.call("is_moving")):
			continue
		if now < float(meta.get("wander_deadline", 0.0)):
			continue
		if randf() > clampf(idle_move_chance, 0.0, 1.0):
			meta["wander_deadline"] = now + randf_range(idle_pause_min_sec, idle_pause_max_sec)
			_agent_meta[agent] = meta
			continue

		var role: String = String(meta.get("role", ""))
		var rest_center: Vector2 = meta.get("rest_anchor_pos", _worker_rest_pos.global_position)
		var idle_target: Vector2 = _random_near(rest_center, idle_wander_radius)
		if role == ROLE_STAFF:
			idle_target = _clamp_to_worker_rest_room(idle_target)
		_move_agent_to(agent, idle_target)
		meta["wander_deadline"] = now + randf_range(idle_wander_interval_sec * 0.6, idle_wander_interval_sec * 1.4)
		_agent_meta[agent] = meta

func _cache_rest_door_tiles() -> void:
	_rest_door_tile_cache.clear()
	for cell in REST_DOOR_VISUAL_CELLS:
		var source_id: int = _items_layer.get_cell_source_id(cell)
		if source_id < 0:
			continue
		_rest_door_tile_cache[cell] = {
			"source_id": source_id,
			"atlas_coords": _items_layer.get_cell_atlas_coords(cell),
			"alternative_tile": _items_layer.get_cell_alternative_tile(cell),
		}

func _update_rest_door_visibility() -> void:
	var occupied: bool = false
	for child in _agents_root.get_children():
		if not (child is Node2D):
			continue
		var agent: Node2D = child as Node2D
		var cell: Vector2i = _world_to_cell(agent.global_position)
		if _is_rest_door_visual_cell(cell):
			occupied = true
			break

	if occupied and not _rest_door_hidden:
		_hide_rest_door_tiles()
	elif not occupied and _rest_door_hidden:
		_restore_rest_door_tiles()

func _is_rest_door_visual_cell(cell: Vector2i) -> bool:
	for c in REST_DOOR_VISUAL_CELLS:
		if c == cell:
			return true
	return false

func _hide_rest_door_tiles() -> void:
	for cell in REST_DOOR_VISUAL_CELLS:
		_items_layer.set_cell(cell, -1, Vector2i(-1, -1), 0)
	_rest_door_hidden = true

func _restore_rest_door_tiles() -> void:
	for cell in REST_DOOR_VISUAL_CELLS:
		if not _rest_door_tile_cache.has(cell):
			continue
		var tile_info: Dictionary = _rest_door_tile_cache[cell] as Dictionary
		_items_layer.set_cell(
			cell,
			int(tile_info.get("source_id", -1)),
			tile_info.get("atlas_coords", Vector2i(-1, -1)),
			int(tile_info.get("alternative_tile", 0))
		)
	_rest_door_hidden = false

func _on_add_agent_pressed() -> void:
	_open_agent_form_dialog("add", {})

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F9:
			if _api_debug_layer != null:
				_api_debug_layer.visible = not _api_debug_layer.visible

func _setup_api_debug_overlay() -> void:
	if not show_api_debug_overlay:
		return
	_api_debug_layer = CanvasLayer.new()
	_api_debug_layer.layer = 100
	add_child(_api_debug_layer)
	if auto_show_api_debug_in_dev:
		_api_debug_layer.visible = _is_dev_runtime()
	else:
		_api_debug_layer.visible = false

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.custom_minimum_size = Vector2(760.0, 180.0)
	_api_debug_layer.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	_api_debug_label = RichTextLabel.new()
	_api_debug_label.fit_content = true
	_api_debug_label.scroll_active = false
	_api_debug_label.bbcode_enabled = false
	margin.add_child(_api_debug_label)
	_refresh_api_debug_overlay()

func _is_dev_runtime() -> bool:
	return OS.is_debug_build() or Engine.is_editor_hint()

func _refresh_api_debug_overlay() -> void:
	if _api_debug_label == null:
		return

	var token_text: String = "missing"
	if _read_web_auth_token() != "":
		token_text = "present"

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[API DEBUG] F9 show/hide")
	lines.append("base_url=%s" % _normalize_base_url(api_base_url))
	lines.append("token=%s busy_api=%s" % [token_text, str(_busy_api)])
	if _api_debug_last_url != "":
		lines.append("last=%s %s" % [_http_method_text(_api_debug_last_method), _api_debug_last_url])
		lines.append("ok=%s code=%d req=%d network=%s auth=%s" % [
			str(_api_debug_last_ok),
			_api_debug_last_response_code,
			_api_debug_last_request_result,
			str(_api_debug_last_network_error),
			str(_api_debug_last_has_auth),
		])
		lines.append("error=%s" % _api_debug_last_error)
		if _api_debug_last_raw_preview != "":
			lines.append("raw=%s" % _api_debug_last_raw_preview)
	if _last_sync_error != "":
		lines.append("sync_error=%s" % _last_sync_error)
	_api_debug_label.text = "\n".join(lines)

func _http_method_text(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_DELETE:
			return "DELETE"
		HTTPClient.METHOD_PUT:
			return "PUT"
		HTTPClient.METHOD_PATCH:
			return "PATCH"
		_:
			return str(method)

func _api_debug_note_request(method: int, url: String, has_auth: bool) -> void:
	_api_debug_last_method = method
	_api_debug_last_url = url
	_api_debug_last_has_auth = has_auth
	_api_debug_last_time_sec = Time.get_ticks_msec() / 1000.0

func _api_debug_note_result(result: Dictionary, response_code: int = -1, request_result: int = -1, raw_text: String = "") -> void:
	_api_debug_last_ok = bool(result.get("ok", false))
	_api_debug_last_response_code = int(result.get("code", response_code))
	_api_debug_last_request_result = request_result
	_api_debug_last_network_error = bool(result.get("network_error", false))
	_api_debug_last_error = String(result.get("error", ""))
	var preview: String = raw_text.strip_edges()
	if preview == "":
		preview = String(result.get("raw", "")).strip_edges()
	if preview.length() > 220:
		preview = preview.substr(0, 220) + "..."
	_api_debug_last_raw_preview = preview

func _setup_new_agent(agent: Node2D, as_manager: bool, api_data: Dictionary = {}, api_order: int = 2147483647) -> void:
	if not agent.has_method("set_sprite_frames"):
		return

	agent.call("set_sprite_frames", _random_sprite_frames())
	if agent.has_signal("agent_arrived") and not agent.is_connected("agent_arrived", Callable(self , "_on_agent_arrived")):
		agent.connect("agent_arrived", Callable(self , "_on_agent_arrived"))
	if agent.has_signal("agent_clicked") and not agent.is_connected("agent_clicked", Callable(self , "_on_agent_clicked")):
		agent.connect("agent_clicked", Callable(self , "_on_agent_clicked"))

	var role: String = ROLE_MANAGER if as_manager else ROLE_STAFF
	var api_name: String = _agent_name_from_api_data(api_data)
	var api_role: String = _agent_role_from_api_data(api_data)
	var api_id: String = String(api_data.get("id", ""))
	var job: String = ROLE_MANAGER if as_manager else ROLE_STAFF
	if use_api_label_text:
		if api_role != "":
			job = api_role
		elif api_name != "":
			job = api_name
	var rest_anchor_pos: Vector2 = _manager_rest_pos.global_position if as_manager else _next_worker_rest_spot()
	var spawn_pos: Vector2 = rest_anchor_pos + Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	if not as_manager:
		spawn_pos = _clamp_to_worker_rest_room(spawn_pos)

	var meta: Dictionary = {
		"role": role,
		"job": job,
		"state": "",
		"work_marker": null,
		"rest_anchor_pos": rest_anchor_pos,
		"wander_deadline": 0.0,
		"api_id": api_id,
		"api_order": api_order,
		"api_data": api_data.duplicate(true),
	}
	_agent_meta[agent] = meta
	agent.global_position = spawn_pos

	if as_manager:
		_manager_agent = agent

	var initial_state: String = _state_from_api_data(api_data, STATE_IDLE)
	_update_agent_label(agent)
	_set_agent_state(agent, initial_state)

func _set_agent_state(agent: Node2D, new_state: String) -> void:
	if not _agent_meta.has(agent):
		return

	var meta: Dictionary = _agent_meta[agent]
	if String(meta.get("state", "")) == new_state and agent.has_method("is_moving") and not bool(agent.call("is_moving")):
		return

	if new_state == STATE_WORKING:
		if String(meta["role"]) == ROLE_MANAGER:
			_move_agent_to(agent, _manager_work_pos.global_position)
			meta["state"] = STATE_WORKING
		else:
			var marker: Marker2D = _assign_working_marker(agent)
			if marker == null:
				meta["state"] = STATE_IDLE
				var fallback_idle: Vector2 = _clamp_to_worker_rest_room(_random_near(_worker_rest_pos.global_position, idle_wander_radius))
				_move_agent_to(agent, fallback_idle)
			else:
				meta["state"] = STATE_WORKING
				_move_agent_to(agent, marker.global_position)
	else:
		if String(meta["role"]) == ROLE_STAFF:
			_release_working_marker(agent)
		meta["state"] = STATE_IDLE
		var rest_center: Vector2 = meta.get("rest_anchor_pos", _worker_rest_pos.global_position)
		var idle_target: Vector2 = _random_near(rest_center, idle_wander_radius)
		if String(meta.get("role", "")) == ROLE_STAFF:
			idle_target = _clamp_to_worker_rest_room(idle_target)
		_move_agent_to(agent, idle_target)
		meta["wander_deadline"] = 0.0

	_agent_meta[agent] = meta
	_update_agent_label(agent)
	_sync_agent_working_animation(agent, String(meta.get("state", STATE_IDLE)) == STATE_WORKING)

func _on_api_state_sync_tick() -> void:
	await _sync_states_from_api()

func _on_agent_arrived(agent: Node2D) -> void:
	if not _agent_meta.has(agent):
		return

	var meta: Dictionary = _agent_meta[agent]
	if String(meta.get("state", "")) == STATE_WORKING:
		meta["wander_deadline"] = 999999999.0
	else:
		meta["wander_deadline"] = 0.0
	_agent_meta[agent] = meta
	_sync_agent_working_animation(agent, String(meta.get("state", STATE_IDLE)) == STATE_WORKING)

func _sync_agent_working_animation(agent: Node2D, working: bool) -> void:
	if agent.has_method("set_working"):
		agent.call("set_working", working)

func _build_agent_dialogs() -> void:
	_agent_form_dialog = ConfirmationDialog.new()
	_agent_form_dialog.title = "Agent \u4fe1\u606f"
	_agent_form_dialog.ok_button_text = "\u63d0\u4ea4"
	_agent_form_dialog.get_cancel_button().text = "\u53d6\u6d88"
	_agent_form_dialog.min_size = Vector2i(620, 0)
	var form_dialog_panel_style: StyleBoxFlat = StyleBoxFlat.new()
	form_dialog_panel_style.bg_color = Color(0.09, 0.11, 0.14, 0.98)
	form_dialog_panel_style.border_width_left = 1
	form_dialog_panel_style.border_width_top = 1
	form_dialog_panel_style.border_width_right = 1
	form_dialog_panel_style.border_width_bottom = 1
	form_dialog_panel_style.border_color = Color(0.28, 0.36, 0.46, 0.95)
	form_dialog_panel_style.corner_radius_top_left = 8
	form_dialog_panel_style.corner_radius_top_right = 8
	form_dialog_panel_style.corner_radius_bottom_left = 8
	form_dialog_panel_style.corner_radius_bottom_right = 8
	_agent_form_dialog.add_theme_stylebox_override("panel", form_dialog_panel_style)
	_agent_form_dialog.confirmed.connect(_on_agent_form_confirmed)
	add_child(_agent_form_dialog)

	var form_margin: MarginContainer = MarginContainer.new()
	form_margin.add_theme_constant_override("margin_left", 12)
	form_margin.add_theme_constant_override("margin_top", 10)
	form_margin.add_theme_constant_override("margin_right", 12)
	form_margin.add_theme_constant_override("margin_bottom", 10)
	_agent_form_dialog.add_child(form_margin)

	var form_box: VBoxContainer = VBoxContainer.new()
	form_box.custom_minimum_size = Vector2(560.0, 0.0)
	form_box.add_theme_constant_override("separation", 6)
	form_margin.add_child(form_box)

	_form_fields.clear()
	_add_form_field(form_box, "name", "Name(\u5fc5\u586b)")
	_add_form_field(form_box, "emoji", "Emoji")
	_add_form_field(form_box, "role", "Role")
	_add_form_field(form_box, "vibe", "Vibe")
	_add_form_field(form_box, "specialties", "Specialties")
	_add_form_field(form_box, "model", "Model")
	_add_form_field(form_box, "bind", "Bind")
	_add_form_field(form_box, "workspace", "Workspace")

	var form_ok_btn: Button = _agent_form_dialog.get_ok_button()
	if form_ok_btn != null:
		form_ok_btn.custom_minimum_size = Vector2(84.0, 32.0)
		_style_detail_button(form_ok_btn, true)
	var form_cancel_btn: Button = _agent_form_dialog.get_cancel_button()
	if form_cancel_btn != null:
		form_cancel_btn.custom_minimum_size = Vector2(84.0, 32.0)
		_style_detail_button(form_cancel_btn, false)

	_agent_detail_dialog = AcceptDialog.new()
	_agent_detail_dialog.title = "Agent \u8be6\u60c5"
	_agent_detail_dialog.ok_button_text = "\u5173\u95ed"
	_agent_detail_dialog.min_size = Vector2i(620, 0)
	var dialog_panel_style: StyleBoxFlat = StyleBoxFlat.new()
	dialog_panel_style.bg_color = Color(0.09, 0.11, 0.14, 0.98)
	dialog_panel_style.border_width_left = 1
	dialog_panel_style.border_width_top = 1
	dialog_panel_style.border_width_right = 1
	dialog_panel_style.border_width_bottom = 1
	dialog_panel_style.border_color = Color(0.28, 0.36, 0.46, 0.95)
	dialog_panel_style.corner_radius_top_left = 8
	dialog_panel_style.corner_radius_top_right = 8
	dialog_panel_style.corner_radius_bottom_left = 8
	dialog_panel_style.corner_radius_bottom_right = 8
	_agent_detail_dialog.add_theme_stylebox_override("panel", dialog_panel_style)
	add_child(_agent_detail_dialog)

	var detail_margin: MarginContainer = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 12)
	detail_margin.add_theme_constant_override("margin_top", 10)
	detail_margin.add_theme_constant_override("margin_right", 12)
	detail_margin.add_theme_constant_override("margin_bottom", 10)
	_agent_detail_dialog.add_child(detail_margin)

	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.custom_minimum_size = Vector2(560.0, 0.0)
	detail_box.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_box)

	_agent_detail_text = RichTextLabel.new()
	_agent_detail_text.fit_content = false
	_agent_detail_text.scroll_active = true
	_agent_detail_text.custom_minimum_size = Vector2(0.0, 180.0)
	_agent_detail_text.bbcode_enabled = true
	_agent_detail_text.add_theme_color_override("default_color", Color(0.92, 0.96, 1.0, 1.0))
	var detail_text_style: StyleBoxFlat = StyleBoxFlat.new()
	detail_text_style.bg_color = Color(0.12, 0.16, 0.20, 0.95)
	detail_text_style.border_width_left = 1
	detail_text_style.border_width_top = 1
	detail_text_style.border_width_right = 1
	detail_text_style.border_width_bottom = 1
	detail_text_style.border_color = Color(0.31, 0.40, 0.52, 0.9)
	detail_text_style.corner_radius_top_left = 6
	detail_text_style.corner_radius_top_right = 6
	detail_text_style.corner_radius_bottom_left = 6
	detail_text_style.corner_radius_bottom_right = 6
	_agent_detail_text.add_theme_stylebox_override("normal", detail_text_style)
	detail_box.add_child(_agent_detail_text)

	var split_line: HSeparator = HSeparator.new()
	detail_box.add_child(split_line)

	var session_label: Label = Label.new()
	session_label.text = "会话/任务"
	session_label.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 1.0))
	detail_box.add_child(session_label)

	_agent_session_input = TextEdit.new()
	_agent_session_input.custom_minimum_size = Vector2(0.0, 120.0)
	_agent_session_input.placeholder_text = "输入要发送给当前 Agent 的会话或任务内容"
	var session_input_style: StyleBoxFlat = StyleBoxFlat.new()
	session_input_style.bg_color = Color(0.10, 0.14, 0.18, 1.0)
	session_input_style.border_width_left = 1
	session_input_style.border_width_top = 1
	session_input_style.border_width_right = 1
	session_input_style.border_width_bottom = 1
	session_input_style.border_color = Color(0.30, 0.40, 0.52, 0.9)
	session_input_style.corner_radius_top_left = 6
	session_input_style.corner_radius_top_right = 6
	session_input_style.corner_radius_bottom_left = 6
	session_input_style.corner_radius_bottom_right = 6
	_agent_session_input.add_theme_stylebox_override("normal", session_input_style)
	_agent_session_input.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	_agent_session_input.add_theme_color_override("font_placeholder_color", Color(0.62, 0.70, 0.80, 0.85))
	detail_box.add_child(_agent_session_input)

	var session_action_row: HBoxContainer = HBoxContainer.new()
	session_action_row.add_theme_constant_override("separation", 8)
	detail_box.add_child(session_action_row)

	_agent_session_send_btn = Button.new()
	_agent_session_send_btn.text = "发送"
	_agent_session_send_btn.custom_minimum_size = Vector2(84.0, 32.0)
	_style_detail_button(_agent_session_send_btn, true)
	_agent_session_send_btn.pressed.connect(_on_send_agent_session_pressed)
	session_action_row.add_child(_agent_session_send_btn)

	_agent_session_cancel_btn = Button.new()
	_agent_session_cancel_btn.text = "取消"
	_agent_session_cancel_btn.custom_minimum_size = Vector2(84.0, 32.0)
	_style_detail_button(_agent_session_cancel_btn, false)
	_agent_session_cancel_btn.pressed.connect(_on_cancel_agent_session_pressed)
	session_action_row.add_child(_agent_session_cancel_btn)

	var split_line_2: HSeparator = HSeparator.new()
	detail_box.add_child(split_line_2)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	detail_box.add_child(action_row)

	var edit_btn: Button = Button.new()
	edit_btn.text = "\u4fee\u6539"
	edit_btn.custom_minimum_size = Vector2(84.0, 30.0)
	_style_detail_button(edit_btn, false)
	edit_btn.pressed.connect(_on_edit_selected_agent_pressed)
	action_row.add_child(edit_btn)

	var delete_btn: Button = Button.new()
	delete_btn.text = "\u5220\u9664"
	delete_btn.custom_minimum_size = Vector2(84.0, 30.0)
	_style_danger_button(delete_btn)
	delete_btn.pressed.connect(_on_delete_selected_agent_pressed)
	action_row.add_child(delete_btn)

	var close_btn: Button = _agent_detail_dialog.get_ok_button()
	if close_btn != null:
		close_btn.hide()

func _style_detail_button(btn: Button, primary: bool) -> void:
	if btn == null:
		return

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	var hover: StyleBoxFlat = StyleBoxFlat.new()
	var pressed: StyleBoxFlat = StyleBoxFlat.new()

	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1

	hover.corner_radius_top_left = 6
	hover.corner_radius_top_right = 6
	hover.corner_radius_bottom_left = 6
	hover.corner_radius_bottom_right = 6
	hover.border_width_left = 1
	hover.border_width_top = 1
	hover.border_width_right = 1
	hover.border_width_bottom = 1

	pressed.corner_radius_top_left = 6
	pressed.corner_radius_top_right = 6
	pressed.corner_radius_bottom_left = 6
	pressed.corner_radius_bottom_right = 6
	pressed.border_width_left = 1
	pressed.border_width_top = 1
	pressed.border_width_right = 1
	pressed.border_width_bottom = 1

	if primary:
		normal.bg_color = Color(0.16, 0.49, 0.81, 1.0)
		normal.border_color = Color(0.31, 0.67, 1.0, 0.95)
		hover.bg_color = Color(0.21, 0.56, 0.90, 1.0)
		hover.border_color = Color(0.46, 0.76, 1.0, 1.0)
		pressed.bg_color = Color(0.11, 0.40, 0.71, 1.0)
		pressed.border_color = Color(0.31, 0.67, 1.0, 0.95)
	else:
		normal.bg_color = Color(0.18, 0.22, 0.27, 1.0)
		normal.border_color = Color(0.34, 0.42, 0.52, 0.9)
		hover.bg_color = Color(0.22, 0.27, 0.33, 1.0)
		hover.border_color = Color(0.44, 0.56, 0.68, 0.98)
		pressed.bg_color = Color(0.15, 0.19, 0.24, 1.0)
		pressed.border_color = Color(0.34, 0.42, 0.52, 0.9)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.94, 0.97, 1.0, 1.0))

func _style_danger_button(btn: Button) -> void:
	if btn == null:
		return

	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(0.69, 0.20, 0.23, 1.0)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.border_color = Color(0.94, 0.40, 0.44, 0.95)
	normal.corner_radius_top_left = 6
	normal.corner_radius_top_right = 6
	normal.corner_radius_bottom_left = 6
	normal.corner_radius_bottom_right = 6

	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.78, 0.24, 0.27, 1.0)
	hover.border_color = Color(1.0, 0.56, 0.60, 1.0)

	var pressed: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.58, 0.15, 0.18, 1.0)
	pressed.border_color = Color(0.94, 0.40, 0.44, 0.95)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", Color(1.0, 0.96, 0.96, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.96, 0.96, 1.0))

func _setup_staff_strip_ui() -> void:
	_staff_strip_layer = CanvasLayer.new()
	_staff_strip_layer.layer = 80
	add_child(_staff_strip_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 14.0
	panel.offset_right = -140.0
	panel.offset_top = -42.0
	panel.offset_bottom = -6.0
	panel.custom_minimum_size = Vector2(0.0, 36.0)
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.12, 0.12, 0.9)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.28, 0.28, 0.28, 1.0)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", panel_style)
	_staff_strip_layer.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)

	_staff_strip_scroll = ScrollContainer.new()
	_staff_strip_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_staff_strip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staff_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_staff_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(_staff_strip_scroll)

	_staff_strip_row = HBoxContainer.new()
	_staff_strip_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_staff_strip_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_staff_strip_row.add_theme_constant_override("separation", 8)
	_staff_strip_scroll.add_child(_staff_strip_row)

func _refresh_staff_strip_ui() -> void:
	if _staff_strip_row == null:
		return

	for child in _staff_strip_row.get_children():
		_staff_strip_row.remove_child(child)
		child.free()

	var agent_nodes: Array[Node2D] = []
	for agent_key in _agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if is_instance_valid(agent):
			agent_nodes.append(agent)

	agent_nodes.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_meta: Dictionary = _agent_meta.get(a, {})
		var b_meta: Dictionary = _agent_meta.get(b, {})
		var a_order: int = int(a_meta.get("api_order", 2147483647))
		var b_order: int = int(b_meta.get("api_order", 2147483647))
		if a_order != b_order:
			return a_order < b_order

		var a_id: String = String(a_meta.get("api_id", "")).strip_edges()
		var b_id: String = String(b_meta.get("api_id", "")).strip_edges()
		return a_id < b_id
	)

	for agent in agent_nodes:
		var meta: Dictionary = _agent_meta.get(agent, {})
		var api_data_variant: Variant = meta.get("api_data", {})
		var api_data: Dictionary = {}
		if api_data_variant is Dictionary:
			api_data = api_data_variant as Dictionary

		var display_name: String = _staff_strip_identity_name(meta)
		var runtime_status: String = _runtime_status_text_for_list(api_data, meta)
		var avatar_tex: Texture2D = _agent_avatar_texture(agent)
		_add_staff_strip_card(display_name, runtime_status, avatar_tex, agent)

	if agent_nodes.is_empty():
		_add_staff_strip_card(_manager_agent_name_fallback(), "idle", null, null)

func _is_manager_meta(meta: Dictionary) -> bool:
	if String(meta.get("role", "")) == ROLE_MANAGER:
		return true

	var api_data_variant: Variant = meta.get("api_data", {})
	if api_data_variant is Dictionary:
		return _is_manager_api_data(api_data_variant as Dictionary)
	return false

func _staff_strip_identity_name(meta: Dictionary) -> String:
	var title_text: String = _agent_title_from_meta(meta)
	if title_text != "":
		return title_text

	var api_data_variant: Variant = meta.get("api_data", {})
	var api_data: Dictionary = {}
	if api_data_variant is Dictionary:
		api_data = api_data_variant as Dictionary

	var identity_name: String = _agent_name_from_api_data(api_data)
	if identity_name != "":
		return identity_name
	if _is_manager_meta(meta):
		return _manager_agent_name_fallback()
	var api_id_text: String = String(meta.get("api_id", "")).strip_edges()
	return api_id_text if api_id_text != "" else _staff_agent_name_fallback()

func _manager_agent_name_fallback() -> String:
	return char(0x7ECF) + char(0x7406) + "Agent"

func _staff_agent_name_fallback() -> String:
	return char(0x5458) + char(0x5DE5) + "Agent"

func _manager_emoji_fallback() -> String:
	return char(0x1F4E6)

func _add_staff_strip_card(display_name: String, runtime_status: String, avatar_tex: Texture2D, agent: Node2D) -> void:
	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(200.0, 30.0)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var card_style: StyleBoxFlat = StyleBoxFlat.new()
	card_style.bg_color = Color(0.88, 0.92, 0.98, 0.18)
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.78, 0.84, 0.94, 0.5)
	card_style.corner_radius_top_left = 4
	card_style.corner_radius_top_right = 4
	card_style.corner_radius_bottom_left = 4
	card_style.corner_radius_bottom_right = 4
	var card_style_hover: StyleBoxFlat = card_style.duplicate() as StyleBoxFlat
	card_style_hover.bg_color = Color(0.95, 0.98, 1.0, 0.32)
	card_style_hover.border_color = Color(0.88, 0.94, 1.0, 0.95)
	card.set_meta("staff_card_style_normal", card_style)
	card.set_meta("staff_card_style_hover", card_style_hover)
	card.add_theme_stylebox_override("panel", card_style)
	card.mouse_entered.connect(_on_staff_strip_card_hover_changed.bind(card, true))
	card.mouse_exited.connect(_on_staff_strip_card_hover_changed.bind(card, false))
	if agent != null and is_instance_valid(agent):
		card.gui_input.connect(_on_staff_strip_card_gui_input.bind(agent))
	_staff_strip_row.add_child(card)

	var card_margin: MarginContainer = MarginContainer.new()
	card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_margin.add_theme_constant_override("margin_left", 4)
	card_margin.add_theme_constant_override("margin_top", 1)
	card_margin.add_theme_constant_override("margin_right", 4)
	card_margin.add_theme_constant_override("margin_bottom", 1)
	card.add_child(card_margin)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	card_margin.add_child(row)

	var avatar: TextureRect = TextureRect.new()
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.custom_minimum_size = Vector2(20.0, 20.0)
	if avatar_tex != null:
		avatar.texture = avatar_tex
	row.add_child(avatar)

	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text = display_name
	row.add_child(name_label)

	var status_label: Label = Label.new()
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.text = runtime_status
	status_label.modulate = Color(0.72, 0.78, 0.86, 1.0)
	row.add_child(status_label)

func _on_staff_strip_card_gui_input(event: InputEvent, agent: Node2D) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if agent == null or not is_instance_valid(agent):
		return
	await _on_agent_clicked(agent)

func _on_staff_strip_card_hover_changed(card: PanelContainer, hover: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	var style_key: String = "staff_card_style_hover" if hover else "staff_card_style_normal"
	var style_value: Variant = card.get_meta(style_key, null)
	if not (style_value is StyleBoxFlat):
		return
	card.add_theme_stylebox_override("panel", style_value as StyleBoxFlat)
	card.queue_redraw()

func _runtime_status_text_for_list(api_data: Dictionary, meta: Dictionary) -> String:
	var status_text: String = _normalize_text(String(api_data.get("runtimeStatus", "")))
	if status_text != "":
		return status_text
	status_text = _normalize_text(String(api_data.get("status", "")))
	if status_text != "":
		return status_text
	var state_text: String = _normalize_text(String(meta.get("state", "")))
	if state_text != "":
		return state_text
	return "unknown"

func _agent_avatar_texture(agent: Node2D) -> Texture2D:
	var anim: AnimatedSprite2D = agent.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim == null:
		return null
	if anim.sprite_frames == null:
		return null
	if not anim.sprite_frames.has_animation(anim.animation):
		return null
	return anim.sprite_frames.get_frame_texture(anim.animation, anim.frame)

func _add_form_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 1.0))
	parent.add_child(label)

	var input: LineEdit = LineEdit.new()
	input.placeholder_text = label_text
	input.custom_minimum_size = Vector2(0.0, 34.0)
	var input_style: StyleBoxFlat = StyleBoxFlat.new()
	input_style.bg_color = Color(0.10, 0.14, 0.18, 1.0)
	input_style.border_width_left = 1
	input_style.border_width_top = 1
	input_style.border_width_right = 1
	input_style.border_width_bottom = 1
	input_style.border_color = Color(0.30, 0.40, 0.52, 0.9)
	input_style.corner_radius_top_left = 6
	input_style.corner_radius_top_right = 6
	input_style.corner_radius_bottom_left = 6
	input_style.corner_radius_bottom_right = 6
	input.add_theme_stylebox_override("normal", input_style)
	input.add_theme_stylebox_override("read_only", input_style)
	input.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	input.add_theme_color_override("font_placeholder_color", Color(0.62, 0.70, 0.80, 0.85))
	parent.add_child(input)
	_form_fields[key] = input

func _open_agent_form_dialog(mode: String, source_data: Dictionary) -> void:
	if mode == "add":
		_agent_form_dialog.title = "\u65b0\u589e Agent"
	else:
		_agent_form_dialog.title = "\u4fee\u6539 Agent"

	_set_form_field_text("name", _agent_name_from_api_data(source_data))
	_set_form_field_text("emoji", _agent_emoji_from_api_data(source_data))
	_set_form_field_text("role", _agent_role_from_api_data(source_data))
	_set_form_field_text("vibe", String(source_data.get("vibe", "")))
	_set_form_field_text("specialties", String(source_data.get("specialties", "")))
	_set_form_field_text("model", String(source_data.get("model", "")))
	_set_form_field_text("bind", _bind_to_string(source_data.get("bind", "")))
	_set_form_field_text("workspace", String(source_data.get("workspace", "")))

	_agent_form_dialog.popup_centered()

func _set_form_field_text(key: String, value: String) -> void:
	if not _form_fields.has(key):
		return
	var line_edit: LineEdit = _form_fields[key] as LineEdit
	if line_edit == null:
		return
	line_edit.text = value

func _collect_form_payload() -> Dictionary:
	var payload: Dictionary = {}
	for key in _form_fields.keys():
		var line_edit: LineEdit = _form_fields[key] as LineEdit
		if line_edit == null:
			continue
		var value: String = line_edit.text.strip_edges()
		if value == "":
			continue
		payload[key] = value
	return payload

func _on_agent_form_confirmed() -> void:
	if _busy_api:
		return

	var payload: Dictionary = _collect_form_payload()
	var name_text: String = String(payload.get("name", "")).strip_edges()
	if name_text == "":
		push_warning("Name \u4e3a\u5fc5\u586b\u9879")
		_agent_form_dialog.popup_centered()
		return

	_busy_api = true
	var result: Dictionary = await _api_request(HTTPClient.METHOD_POST, "/agents", payload)
	_busy_api = false
	if not bool(result.get("ok", false)):
		push_warning("\u4fdd\u5b58 Agent \u5931\u8d25: %s" % String(result.get("error", "unknown error")))
		return

	await _load_agents_from_api()

func _on_agent_clicked(agent: Node2D) -> void:
	_selected_agent = agent
	_busy_session_submit = false
	_set_agent_session_ui_enabled(true)
	if _agent_session_input != null:
		_agent_session_input.text = ""
	await _refresh_selected_agent_detail()
	_agent_detail_dialog.popup_centered()

func _set_agent_session_ui_enabled(enabled: bool) -> void:
	if _agent_session_input != null:
		_agent_session_input.editable = enabled
	if _agent_session_send_btn != null:
		_agent_session_send_btn.disabled = not enabled
	if _agent_session_cancel_btn != null:
		_agent_session_cancel_btn.disabled = not enabled

func _on_cancel_agent_session_pressed() -> void:
	if _agent_session_input != null:
		_agent_session_input.text = ""

func _on_send_agent_session_pressed() -> void:
	if _busy_session_submit:
		return
	if _selected_agent == null or not _agent_meta.has(_selected_agent):
		push_warning("当前未选中 Agent")
		return
	if _agent_session_input == null:
		return

	var message_text: String = _agent_session_input.text.strip_edges()
	if message_text == "":
		push_warning("会话内容不能为空")
		return

	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_id: String = String(meta.get("api_id", "")).strip_edges()
	if api_id == "":
		push_warning("当前 Agent 无 API ID，无法发送会话")
		return

	_busy_session_submit = true
	_set_agent_session_ui_enabled(false)
	var session_result: Dictionary = await _api_request(
		HTTPClient.METHOD_POST,
		"/agents/%s/sessions" % api_id.uri_encode(),
		{"message": message_text}
	)
	_busy_session_submit = false
	_set_agent_session_ui_enabled(true)

	if not bool(session_result.get("ok", false)):
		push_warning("发送会话失败: %s" % String(session_result.get("error", "unknown error")))
		return

	var response_json_variant: Variant = session_result.get("json", {})
	var response_json: Dictionary = {}
	if response_json_variant is Dictionary:
		response_json = response_json_variant as Dictionary
	var accepted: bool = bool(response_json.get("accepted", false))
	if not accepted:
		push_warning("会话未被接受，请稍后重试")
		return

	_agent_session_input.text = ""

func _refresh_selected_agent_detail() -> void:
	if _selected_agent == null or not _agent_meta.has(_selected_agent):
		return
	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_id: String = String(meta.get("api_id", "")).strip_edges()
	var api_data_variant: Variant = meta.get("api_data", {})
	var api_data: Dictionary = {}
	if api_data_variant is Dictionary:
		api_data = api_data_variant as Dictionary

	if api_id != "":
		var detail_result: Dictionary = await _api_request(HTTPClient.METHOD_GET, "/agents/%s" % api_id.uri_encode())
		if bool(detail_result.get("ok", false)):
			api_data = detail_result.get("data", {})
			meta["api_data"] = api_data
			meta["api_id"] = String(api_data.get("id", api_id))
			_agent_meta[_selected_agent] = meta

	_agent_detail_text.text = _build_agent_detail_text(meta, api_data)

func _build_agent_detail_text(meta: Dictionary, api_data: Dictionary) -> String:
	var role_text: String = String(meta.get("role", ""))
	var state_text: String = String(meta.get("state", ""))
	var id_text: String = String(meta.get("api_id", ""))
	var name_text: String = _agent_name_from_api_data(api_data)
	var api_role: String = _agent_role_from_api_data(api_data)
	var model_text: String = String(api_data.get("model", ""))
	var workspace_text: String = String(api_data.get("workspace", ""))
	var bind_text: String = _bind_to_string(api_data.get("bind", ""))
	var specialties_text: String = String(api_data.get("specialties", ""))
	var vibe_text: String = String(api_data.get("vibe", ""))

	var lines: PackedStringArray = []
	lines.append("[b]Agent 信息[/b]")
	lines.append("[color=#9FC4E8]ID[/color]: %s" % id_text)
	lines.append("[color=#9FC4E8]Name[/color]: %s" % name_text)
	lines.append("[color=#9FC4E8]Role[/color]: %s / %s" % [role_text, api_role])
	lines.append("[color=#9FC4E8]State[/color]: %s" % state_text)
	lines.append("")
	lines.append("[b]配置[/b]")
	lines.append("[color=#9FC4E8]Model[/color]: %s" % model_text)
	lines.append("[color=#9FC4E8]Bind[/color]: %s" % bind_text)
	lines.append("[color=#9FC4E8]Workspace[/color]: %s" % workspace_text)
	lines.append("")
	lines.append("[b]能力画像[/b]")
	lines.append("[color=#9FC4E8]Specialties[/color]: %s" % specialties_text)
	lines.append("[color=#9FC4E8]Vibe[/color]: %s" % vibe_text)
	return "\n".join(lines)

func _on_edit_selected_agent_pressed() -> void:
	if _selected_agent == null or not _agent_meta.has(_selected_agent):
		return
	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_data_variant: Variant = meta.get("api_data", {})
	var api_data: Dictionary = {}
	if api_data_variant is Dictionary:
		api_data = api_data_variant as Dictionary
	_open_agent_form_dialog("edit", api_data)

func _on_delete_selected_agent_pressed() -> void:
	if _busy_api:
		return
	if _selected_agent == null or not _agent_meta.has(_selected_agent):
		return

	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_id: String = String(meta.get("api_id", "")).strip_edges()
	if api_id == "":
		push_warning("\u5f53\u524d Agent \u65e0 API ID\uff0c\u65e0\u6cd5\u5220\u9664")
		return

	_busy_api = true
	var delete_result: Dictionary = await _api_request(HTTPClient.METHOD_DELETE, "/agents/%s?force=true" % api_id.uri_encode())
	_busy_api = false
	if not bool(delete_result.get("ok", false)):
		push_warning("\u5220\u9664 Agent \u5931\u8d25: %s" % String(delete_result.get("error", "unknown error")))
		return

	_agent_detail_dialog.hide()
	await _load_agents_from_api()

func _load_agents_from_api() -> void:
	print("[API] load agents tick")
	var list_result: Dictionary = await _api_request(HTTPClient.METHOD_GET, "/agents")
	if not bool(list_result.get("ok", false)):
		push_warning("\u8bfb\u53d6 Agent \u5217\u8868\u5931\u8d25: %s" % String(list_result.get("error", "unknown error")))
		return

	var agents_data_variant: Variant = list_result.get("data", [])
	if not (agents_data_variant is Array):
		push_warning("Agent \u5217\u8868\u683c\u5f0f\u65e0\u6548")
		return

	var agents_data: Array = agents_data_variant as Array
	_reset_agents_from_api()
	for i in range(0, agents_data.size()):
		var item: Variant = agents_data[i]
		if not (item is Dictionary):
			continue
		var data: Dictionary = item as Dictionary
		var is_manager: bool = _is_manager_api_data(data)
		var new_agent: Node2D = AGENT_SCENE.instantiate() as Node2D
		_agents_root.add_child(new_agent)
		_setup_new_agent(new_agent, is_manager and _manager_agent == null, data, i)
	_refresh_staff_strip_ui()

func _sync_states_from_api() -> void:
	if _busy_api:
		return

	var list_result: Dictionary = await _api_request(HTTPClient.METHOD_GET, "/agents")
	if not bool(list_result.get("ok", false)):
		_warn_sync_error_throttled("\u540c\u6b65 Agent \u72b6\u6001\u5931\u8d25: %s" % String(list_result.get("error", "unknown error")))
		return

	var agents_data_variant: Variant = list_result.get("data", [])
	if not (agents_data_variant is Array):
		return
	var agents_data: Array = agents_data_variant as Array
	var incoming_by_id: Dictionary = {}
	var incoming_order_by_id: Dictionary = {}
	for i in range(0, agents_data.size()):
		var item: Variant = agents_data[i]
		if not (item is Dictionary):
			continue
		var api_data: Dictionary = item as Dictionary
		var api_id: String = String(api_data.get("id", "")).strip_edges()
		if api_id == "":
			continue
		incoming_by_id[api_id] = api_data
		incoming_order_by_id[api_id] = i

	# 1) 删除服务端已经不存在的 Agent
	var stale_agents: Array[Node2D] = []
	for agent_key in _agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if not is_instance_valid(agent):
			stale_agents.append(agent)
			continue
		var meta: Dictionary = _agent_meta[agent]
		var existing_id: String = String(meta.get("api_id", "")).strip_edges()
		if existing_id == "" or incoming_by_id.has(existing_id):
			continue
		stale_agents.append(agent)

	for stale in stale_agents:
		if is_instance_valid(stale):
			var stale_meta: Dictionary = _agent_meta.get(stale, {})
			if String(stale_meta.get("role", "")) == ROLE_STAFF:
				_release_working_marker(stale)
			if stale == _manager_agent:
				_manager_agent = null
			stale.queue_free()
		_agent_meta.erase(stale)

	# 2) 新增服务端新增的 Agent；并更新已存在 Agent 的显示与状态
	for api_id_key in incoming_by_id.keys():
		var api_id: String = String(api_id_key)
		var api_data: Dictionary = incoming_by_id[api_id_key] as Dictionary
		var api_order: int = int(incoming_order_by_id.get(api_id, 2147483647))
		var scene_agent: Node2D = _find_agent_by_api_id(api_id)
		if scene_agent == null:
			var is_manager: bool = _is_manager_api_data(api_data)
			var new_agent: Node2D = AGENT_SCENE.instantiate() as Node2D
			_agents_root.add_child(new_agent)
			_setup_new_agent(new_agent, is_manager and _manager_agent == null, api_data, api_order)
			continue

		var meta: Dictionary = _agent_meta.get(scene_agent, {})
		meta["api_id"] = String(api_data.get("id", api_id))
		meta["api_order"] = api_order
		meta["api_data"] = api_data
		var latest_job: String = _agent_role_from_api_data(api_data)
		if latest_job != "":
			meta["job"] = latest_job
		_agent_meta[scene_agent] = meta
		_update_agent_label(scene_agent)

		var desired_state: String = _state_from_api_data(api_data, "")
		if desired_state != "" and String(meta.get("state", "")) != desired_state:
			_set_agent_state(scene_agent, desired_state)
	_refresh_staff_strip_ui()

func _warn_sync_error_throttled(message: String) -> void:
	var now_sec: float = Time.get_ticks_msec() / 1000.0
	var too_soon: bool = now_sec - _last_sync_error_time_sec < 10.0
	if too_soon and message == _last_sync_error:
		return
	_last_sync_error = message
	_last_sync_error_time_sec = now_sec
	push_warning(message)

func _find_agent_by_api_id(api_id: String) -> Node2D:
	for agent_key in _agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if not is_instance_valid(agent):
			continue
		var meta: Dictionary = _agent_meta[agent]
		var id_text: String = String(meta.get("api_id", "")).strip_edges()
		if id_text == api_id:
			return agent
	return null

func _reset_agents_from_api() -> void:
	for child in _agents_root.get_children():
		if child is Node2D:
			child.queue_free()
	_agent_meta.clear()
	_manager_agent = null

func _api_request(method: int, endpoint: String, payload: Dictionary = {}) -> Dictionary:
	var bases: PackedStringArray = PackedStringArray()
	var primary: String = _normalize_base_url(api_base_url)
	if primary != "":
		bases.append(primary)
	# Web 端优先固定走当前站点 /api，避免回退到 localhost/内网地址导致跨域或连接错误。
	if OS.get_name() != "Web":
		for base in api_fallback_base_urls:
			var normalized: String = _normalize_base_url(String(base))
			if normalized == "" or bases.has(normalized):
				continue
			bases.append(normalized)

	var last_result: Dictionary = {"ok": false, "error": "no api base url configured"}
	for i in range(0, bases.size()):
		var base_url: String = String(bases[i])
		var result: Dictionary = await _api_request_with_base(base_url, method, endpoint, payload)
		if bool(result.get("ok", false)):
			if api_base_url != base_url:
				api_base_url = base_url
			return result
		last_result = result
		if i < bases.size() - 1 and _should_try_next_base(result):
			continue
		break

	return last_result

func _api_request_with_base(base_url: String, method: int, endpoint: String, payload: Dictionary) -> Dictionary:
	var req: HTTPRequest = HTTPRequest.new()
	add_child(req)

	var resolved_base_url: String = _resolve_request_base_url(base_url)
	var url: String = "%s%s" % [resolved_base_url, endpoint]
	print("[API] request ", method, " ", url)
	var headers: PackedStringArray = PackedStringArray()
	var auth_header: String = _build_authorization_header()
	var has_auth: bool = auth_header != ""
	_api_debug_note_request(method, url, has_auth)
	if auth_header != "":
		headers.append(auth_header)
	var body: String = ""
	if method == HTTPClient.METHOD_POST:
		headers.append("Content-Type: application/json")
		body = JSON.stringify(payload)

	var err: Error = req.request(url, headers, method, body)
	if err != OK:
		push_warning("[API] request start failed: %s url=%s" % [str(err), url])
		req.queue_free()
		var start_fail: Dictionary = {"ok": false, "error": "request start failed: %s" % str(err), "network_error": true}
		_api_debug_note_result(start_fail)
		return start_fail

	var response: Array = await req.request_completed
	req.queue_free()
	if response.size() < 4:
		var invalid_resp: Dictionary = {"ok": false, "error": "invalid response", "network_error": true}
		_api_debug_note_result(invalid_resp)
		return invalid_resp

	var request_result: int = int(response[0])
	var response_code: int = int(response[1])
	var response_body: PackedByteArray = response[3]
	var response_text: String = response_body.get_string_from_utf8()

	if request_result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[API] request failed result=%d code=%d url=%s" % [request_result, response_code, url])
		var req_fail: Dictionary = {
			"ok": false,
			"error": "request failed(%d): %s" % [request_result, _http_request_result_text(request_result)],
			"code": response_code,
			"raw": response_text,
			"network_error": true
		}
		_api_debug_note_result(req_fail, response_code, request_result, response_text)
		return req_fail

	if response_code == 0:
		push_warning("[API] HTTP 0 url=%s" % url)
		var http_zero: Dictionary = {"ok": false, "error": "HTTP 0 (network unreachable or API unavailable)", "code": response_code, "raw": response_text, "network_error": true}
		_api_debug_note_result(http_zero, response_code, request_result, response_text)
		return http_zero

	if response_text.strip_edges() == "":
		var empty_resp: Dictionary = {"ok": false, "error": "empty response body (HTTP %d)" % response_code, "code": response_code, "raw": response_text, "network_error": false}
		_api_debug_note_result(empty_resp, response_code, request_result, response_text)
		return empty_resp

	var parsed: Variant = JSON.parse_string(response_text)
	var parsed_dict: Dictionary = {}
	if parsed is Dictionary:
		parsed_dict = _normalize_api_dictionary(parsed as Dictionary)
	else:
		var invalid_json: Dictionary = {"ok": false, "error": "invalid JSON body (HTTP %d)" % response_code, "code": response_code, "raw": response_text, "network_error": false}
		_api_debug_note_result(invalid_json, response_code, request_result, response_text)
		return invalid_json

	var success: bool = response_code >= 200 and response_code < 300 and bool(parsed_dict.get("success", false))
	if not success:
		var err_msg: String = String(parsed_dict.get("error", "HTTP %d" % response_code))
		var biz_fail: Dictionary = {"ok": false, "error": err_msg, "code": response_code, "raw": response_text, "network_error": false}
		_api_debug_note_result(biz_fail, response_code, request_result, response_text)
		return biz_fail

	var ok_result: Dictionary = {"ok": true, "data": parsed_dict.get("data", {}), "json": parsed_dict, "code": response_code, "base_url": resolved_base_url}
	_api_debug_note_result(ok_result, response_code, request_result, response_text)
	return ok_result

func _normalize_api_dictionary(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in src.keys():
		out[key] = _normalize_api_value(src[key])
	return out

func _normalize_api_array(src: Array) -> Array:
	var out: Array = []
	out.resize(src.size())
	for i in range(0, src.size()):
		out[i] = _normalize_api_value(src[i])
	return out

func _normalize_api_value(value: Variant) -> Variant:
	if value is Dictionary:
		return _normalize_api_dictionary(value as Dictionary)
	if value is Array:
		return _normalize_api_array(value as Array)
	if value is String:
		return _normalize_text(String(value))
	return value

func _normalize_text(text: String) -> String:
	return text.strip_edges()

func _build_authorization_header() -> String:
	var token: String = _read_web_auth_token()
	if token == "":
		return ""
	return "Authorization: Bearer %s" % token

func _read_web_auth_token() -> String:
	if OS.get_name() != "Web":
		return ""
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""

	var js_bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if js_bridge == null:
		return ""
	var raw: Variant = js_bridge.call("eval", "(function(){try{return window.localStorage.getItem('aicube_auth')||'';}catch(e){return '';}})();")
	var raw_text: String = String(raw).strip_edges()
	if raw_text == "" or raw_text == "null":
		return ""

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		return String((parsed as Dictionary).get("token", "")).strip_edges()
	return ""

func _normalize_base_url(raw_url: String) -> String:
	var out: String = raw_url.strip_edges()
	if out == "":
		return ""
	if out.ends_with("/"):
		out = out.substr(0, out.length() - 1)
	return out

func _resolve_request_base_url(base_url: String) -> String:
	var out: String = _normalize_base_url(base_url)
	if OS.get_name() == "Web" and out.begins_with("/"):
		var origin: String = _get_web_origin()
		if origin != "":
			return "%s%s" % [origin, out]
	return out

func _get_web_origin() -> String:
	if OS.get_name() != "Web":
		return ""
	if not Engine.has_singleton("JavaScriptBridge"):
		return ""
	var js_bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if js_bridge == null:
		return ""
	var origin: Variant = js_bridge.call("eval", "(function(){try{return window.location.origin||'';}catch(e){return '';}})();")
	return String(origin).strip_edges()

func _should_try_next_base(result: Dictionary) -> bool:
	return bool(result.get("network_error", false))

func _http_request_result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "can't connect"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "can't resolve host"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body size limit exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body decompress failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download file can't open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect limit reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return "unknown"

func _agent_name_from_api_data(data: Dictionary) -> String:
	var identity_name: String = _identity_name_cn_from_api_data(data)
	if identity_name != "":
		return identity_name

	if data.has("identity"):
		var identity_value: Variant = data.get("identity", {})
		if identity_value is Dictionary:
			var identity: Dictionary = identity_value as Dictionary
			var identity_name_inner: String = _normalize_text(String(identity.get("name", "")))
			if identity_name_inner != "":
				return identity_name_inner
	var fallback_name: String = _normalize_text(String(data.get("name", data.get("id", ""))))
	return fallback_name

func _identity_name_cn_from_api_data(data: Dictionary) -> String:
	var raw_name: String = _normalize_text(String(data.get("identityName", "")))
	if raw_name == "":
		return ""

	var idx_ascii: int = raw_name.find(" (")
	var idx_cn: int = raw_name.find("\uFF08")
	var cut_idx: int = -1
	if idx_ascii >= 0 and idx_cn >= 0:
		cut_idx = mini(idx_ascii, idx_cn)
	elif idx_ascii >= 0:
		cut_idx = idx_ascii
	elif idx_cn >= 0:
		cut_idx = idx_cn

	if cut_idx > 0:
		return raw_name.substr(0, cut_idx).strip_edges()
	return raw_name

func _agent_role_from_api_data(data: Dictionary) -> String:
	var role_text: String = _normalize_text(String(data.get("role", "")))
	if role_text != "":
		return role_text
	var title_text: String = _normalize_text(String(data.get("title", "")))
	return title_text

func _agent_emoji_from_api_data(data: Dictionary) -> String:
	if data.has("identity"):
		var identity_value: Variant = data.get("identity", {})
		if identity_value is Dictionary:
			var identity: Dictionary = identity_value as Dictionary
			return String(identity.get("emoji", "")).strip_edges()
	return String(data.get("emoji", "")).strip_edges()

func _is_sub_agent_workspace(data: Dictionary) -> bool:
	if data.has("isPersistent"):
		return not bool(data.get("isPersistent", true))
	return false

func _is_manager_api_data(data: Dictionary) -> bool:
	var api_id: String = String(data.get("id", "")).strip_edges()
	if api_id == "main":
		return true
	if data.has("identity"):
		var identity_value: Variant = data.get("identity", {})
		if identity_value is Dictionary:
			var identity: Dictionary = identity_value as Dictionary
			var theme: String = String(identity.get("theme", "")).strip_edges().to_lower()
			var identity_name: String = String(identity.get("name", "")).strip_edges()
			if theme == "manager" or identity_name == ROLE_MANAGER:
				return true
	var name_text: String = _agent_name_from_api_data(data)
	return name_text == ROLE_MANAGER

func _bind_to_string(bind_value: Variant) -> String:
	if bind_value is Array:
		var binds: Array = bind_value as Array
		var out: PackedStringArray = []
		for item in binds:
			out.append(String(item))
		return ",".join(out)
	return String(bind_value)

func _state_from_api_data(data: Dictionary, default_state: String) -> String:
	if data.has("runtimeStatus"):
		return _normalize_state_value(data.get("runtimeStatus", default_state), default_state)
	if data.has("state"):
		return _normalize_state_value(data.get("state", default_state), default_state)
	if data.has("status"):
		return _normalize_state_value(data.get("status", default_state), default_state)
	if data.has("agentState"):
		return _normalize_state_value(data.get("agentState", default_state), default_state)
	if data.has("isWorking"):
		return STATE_WORKING if bool(data.get("isWorking", false)) else STATE_IDLE
	if data.has("working"):
		return STATE_WORKING if bool(data.get("working", false)) else STATE_IDLE
	if data.has("busy"):
		return STATE_WORKING if bool(data.get("busy", false)) else STATE_IDLE
	return default_state

func _normalize_state_value(value: Variant, default_state: String) -> String:
	var text: String = _normalize_text(String(value)).strip_edges().to_lower()
	if text == "":
		return default_state
	if text == "\u5de5\u4f5c\u4e2d" or text == "working" or text == "busy" or text == "running" or text == "active" or text == "executing" or text == "processing" or text == "1" or text == "true":
		return STATE_WORKING
	if text == "\u7a7a\u95f2" or text == "idle" or text == "rest" or text == "0" or text == "false":
		return STATE_IDLE
	return default_state

func _update_agent_label(agent: Node2D) -> void:
	if not _agent_meta.has(agent):
		return

	var meta: Dictionary = _agent_meta[agent]
	var title: String = _agent_title_from_meta(meta)

	var normalized_state: String = _normalize_state_value(meta.get("state", STATE_IDLE), STATE_IDLE)
	var state_text: String = STATE_IDLE
	if normalized_state == STATE_WORKING:
		state_text = STATE_WORKING

	var text: String = "%s\n(%s)" % [title, state_text]
	agent.call("set_display_name", text)

func _agent_title_from_meta(meta: Dictionary) -> String:
	var api_data_variant: Variant = meta.get("api_data", {})
	if api_data_variant is Dictionary:
		var api_data: Dictionary = api_data_variant as Dictionary
		var api_name: String = _agent_name_from_api_data(api_data)
		var api_role: String = _agent_role_from_api_data(api_data)
		var api_emoji: String = _agent_emoji_from_api_data(api_data)
		if _is_sub_agent_workspace(api_data) and api_name != "" and not api_name.begins_with("\u3010\u4e34\u65f6\u5de5\u3011"):
			api_name = "\u3010\u4e34\u65f6\u5de5\u3011" + api_name
		var title_text: String = ""
		if api_name != "" and api_role != "":
			title_text = "%s | %s" % [api_name, api_role]
		elif api_name != "":
			title_text = api_name
		elif api_role != "":
			title_text = api_role
		if title_text != "":
			if api_emoji != "":
				return "%s %s" % [api_emoji, title_text]
			return title_text

	var job_text: String = _normalize_text(String(meta.get("job", "")))
	if job_text != "":
		return job_text

	if String(meta.get("role", "")) == ROLE_MANAGER:
		return ROLE_MANAGER
	return ROLE_STAFF

func _collect_markers() -> void:
	_working_pos_markers.clear()
	for child in _office_pos.get_children():
		if child is Marker2D and child.name.begins_with("WorkingPos"):
			_working_pos_markers.append(child as Marker2D)
	_working_pos_markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool: return a.name < b.name)

func _assign_working_marker(agent: Node2D) -> Marker2D:
	var occupied: Dictionary = {}
	for other_key in _agent_meta.keys():
		var other: Node2D = other_key as Node2D
		if other == agent:
			continue

		var meta: Dictionary = _agent_meta[other]
		var marker: Marker2D = meta.get("work_marker") as Marker2D
		if String(meta.get("state", "")) == STATE_WORKING and marker != null:
			occupied[marker] = true

	var candidates: Array[Marker2D] = []
	for marker in _working_pos_markers:
		if not occupied.has(marker):
			candidates.append(marker)

	if candidates.is_empty():
		return null

	var selected: Marker2D = candidates[randi() % candidates.size()]
	var self_meta: Dictionary = _agent_meta[agent]
	self_meta["work_marker"] = selected
	_agent_meta[agent] = self_meta
	return selected

func _release_working_marker(agent: Node2D) -> void:
	if not _agent_meta.has(agent):
		return
	var meta: Dictionary = _agent_meta[agent]
	meta["work_marker"] = null
	_agent_meta[agent] = meta

func _random_staff_job() -> String:
	if employee_job_pool.is_empty():
		return ROLE_STAFF
	return String(employee_job_pool[randi() % employee_job_pool.size()])

func _next_worker_rest_spot() -> Vector2:
	var min_dist: float = maxf(worker_rest_min_distance, 8.0)
	var candidates: Array[Vector2] = _worker_rest_room_candidates()
	if candidates.is_empty():
		return _clamp_to_worker_rest_room(_worker_rest_pos.global_position)

	var anchors: Array[Vector2] = _staff_rest_anchors()
	if anchors.is_empty():
		return candidates[randi() % candidates.size()]

	var ranked: Array[Dictionary] = []
	for candidate in candidates:
		var nearest: float = INF
		for anchor in anchors:
			var d: float = candidate.distance_to(anchor)
			nearest = minf(nearest, d)
		ranked.append({"pos": candidate, "score": nearest})

	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))

	var preferred: Array[Vector2] = []
	for entry in ranked:
		var p: Vector2 = entry["pos"]
		var score: float = float(entry["score"])
		if score < min_dist and not preferred.is_empty():
			continue
		preferred.append(p)
		if preferred.size() >= 8:
			break

	if preferred.is_empty():
		return candidates[randi() % candidates.size()]
	return preferred[randi() % preferred.size()]

func _worker_rest_room_candidates() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var base: Vector2 = _worker_rest_pos.global_position
	var max_radius: float = maxf(worker_rest_scatter_radius, 1.0)
	for x in range(WORKER_REST_MIN_CELL.x, WORKER_REST_MAX_CELL.x + 1):
		for y in range(WORKER_REST_MIN_CELL.y, WORKER_REST_MAX_CELL.y + 1):
			var cell: Vector2i = Vector2i(x, y)
			if _is_cell_blocked(cell):
				continue
			var world_pos: Vector2 = _cell_to_world(cell)
			if world_pos.distance_to(base) > max_radius:
				continue
			out.append(world_pos)
	if out.is_empty():
		out.append(_clamp_to_worker_rest_room(base))
	return out

func _staff_rest_anchors() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for agent_key in _agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		var meta: Dictionary = _agent_meta[agent]
		if String(meta.get("role", "")) != ROLE_STAFF:
			continue
		var existing: Vector2 = meta.get("rest_anchor_pos", _worker_rest_pos.global_position)
		out.append(existing)
	return out

func _random_near(center: Vector2, radius: float) -> Vector2:
	var angle: float = randf_range(0.0, TAU)
	var distance: float = randf_range(6.0, maxf(radius, 6.0))
	return center + Vector2.RIGHT.rotated(angle) * distance

func _is_in_worker_rest_room(world_pos: Vector2) -> bool:
	var cell: Vector2i = _world_to_cell(world_pos)
	return cell.x >= WORKER_REST_MIN_CELL.x and cell.x <= WORKER_REST_MAX_CELL.x and cell.y >= WORKER_REST_MIN_CELL.y and cell.y <= WORKER_REST_MAX_CELL.y

func _clamp_to_worker_rest_room(world_pos: Vector2) -> Vector2:
	if _is_in_worker_rest_room(world_pos):
		return world_pos

	var cell: Vector2i = _world_to_cell(world_pos)
	var clamped_x: int = clampi(cell.x, WORKER_REST_MIN_CELL.x, WORKER_REST_MAX_CELL.x)
	var clamped_y: int = clampi(cell.y, WORKER_REST_MIN_CELL.y, WORKER_REST_MAX_CELL.y)
	return _cell_to_world(Vector2i(clamped_x, clamped_y))

func _load_sprite_frames_pool() -> void:
	_sprite_frames_pool.clear()
	_unused_sprite_frames_pool.clear()
	var dir: DirAccess = DirAccess.open(ANIM_RESOURCE_DIR)
	if dir == null:
		push_warning("Cannot open animation resource directory: %s" % ANIM_RESOURCE_DIR)
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(ANIM_RESOURCE_SUFFIX):
			continue

		var full_path: String = "%s/%s" % [ANIM_RESOURCE_DIR, file_name]
		var loaded_resource: Resource = load(full_path)
		var frames: SpriteFrames = loaded_resource as SpriteFrames
		if frames != null:
			_sprite_frames_pool.append(frames)
	dir.list_dir_end()
	_refill_unused_pool()

func _random_sprite_frames() -> SpriteFrames:
	if _sprite_frames_pool.is_empty():
		return null
	if _unused_sprite_frames_pool.is_empty():
		_refill_unused_pool()

	if not _unused_sprite_frames_pool.is_empty():
		var next_frames: SpriteFrames = _unused_sprite_frames_pool.pop_back() as SpriteFrames
		_last_assigned_frames = next_frames
		return next_frames

	var fallback: SpriteFrames = _sprite_frames_pool[randi() % _sprite_frames_pool.size()]
	_last_assigned_frames = fallback
	return fallback

func _refill_unused_pool() -> void:
	_unused_sprite_frames_pool = _sprite_frames_pool.duplicate()
	_unused_sprite_frames_pool.shuffle()
	if _unused_sprite_frames_pool.size() > 1 and _last_assigned_frames != null:
		if _unused_sprite_frames_pool.back() == _last_assigned_frames:
			var first: SpriteFrames = _unused_sprite_frames_pool[0]
			_unused_sprite_frames_pool[0] = _unused_sprite_frames_pool.back()
			_unused_sprite_frames_pool[_unused_sprite_frames_pool.size() - 1] = first

func _move_agent_to(agent: Node2D, target_world: Vector2) -> void:
	var meta: Dictionary = _agent_meta.get(agent, {})
	var is_manager: bool = String(meta.get("role", "")) == ROLE_MANAGER
	if is_manager and agent.has_method("move_to_direct"):
		agent.call("move_to_direct", target_world)
		return

	var resolved_target: Vector2 = _resolve_reachable_nav_target(agent.global_position, target_world)
	agent.call("move_to", resolved_target)

func _resolve_reachable_nav_target(from_world: Vector2, target_world: Vector2) -> Vector2:
	var world2d_ref: World2D = get_world_2d()
	if world2d_ref == null:
		return target_world

	var nav_map: RID = world2d_ref.navigation_map
	if not nav_map.is_valid():
		return target_world

	# 1) If target is reachable, use it directly
	var direct_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, target_world, true)
	if not direct_path.is_empty():
		return target_world

	# 2) Try the closest point from navigation map
	var closest_on_nav: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, target_world)
	var closest_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, closest_on_nav, true)
	if not closest_path.is_empty():
		return closest_on_nav

	# 3) Sample around target and use first reachable point
	var radii: PackedFloat32Array = PackedFloat32Array([12.0, 24.0, 36.0, 48.0, 64.0])
	for r in radii:
		for i in range(0, 12):
			var ang: float = TAU * float(i) / 12.0
			var p: Vector2 = target_world + Vector2.RIGHT.rotated(ang) * r
			var p_on_nav: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, p)
			var p_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, from_world, p_on_nav, true)
			if not p_path.is_empty():
				return p_on_nav

	# 4) Fallback: keep original target
	return target_world

func _build_nav_grid() -> void:
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
			if _is_cell_blocked(cell):
				_astar.set_point_solid(cell, true)

	_force_open_door_cells()

func _force_open_door_cells() -> void:
	if _astar == null:
		return
	for center in REST_DOOR_INSIDE_CELLS:
		for dx in range(-door_clear_radius_cells, door_clear_radius_cells + 1):
			for dy in range(-door_clear_radius_cells, door_clear_radius_cells + 1):
				var c: Vector2i = Vector2i(center.x + dx, center.y + dy)
				if _astar.is_in_boundsv(c):
					_astar.set_point_solid(c, false)
	for center in REST_DOOR_OUTSIDE_CELLS:
		for dx in range(-door_clear_radius_cells, door_clear_radius_cells + 1):
			for dy in range(-door_clear_radius_cells, door_clear_radius_cells + 1):
				var c: Vector2i = Vector2i(center.x + dx, center.y + dy)
				if _astar.is_in_boundsv(c):
					_astar.set_point_solid(c, false)
	_rest_door_inside_world = _cells_center_to_world(REST_DOOR_INSIDE_CELLS)
	_rest_door_outside_world = _cells_center_to_world(REST_DOOR_OUTSIDE_CELLS)

func _is_cell_blocked(cell: Vector2i) -> bool:
	if _tile_has_collision(_items_layer, cell):
		return true
	if _tile_has_collision(_desk_layer, cell):
		return true
	return false

func _tile_has_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	var tile_data: TileData = layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_collision_polygons_count(0) > 0

func _build_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array([end_world])

	var direct_path: PackedVector2Array = _build_simple_world_path(start_world, end_world)
	if not direct_path.is_empty():
		return direct_path

	if force_rest_door_routing:
		var via_points: PackedVector2Array = _build_path_via_rest_door(start_world, end_world)
		if not via_points.is_empty():
			return via_points

	return PackedVector2Array([end_world])

func _build_path_via_rest_door(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	var first_gate: Vector2 = _rest_door_outside_world
	var second_gate: Vector2 = _rest_door_inside_world
	if start_world.x >= rest_area_split_x:
		first_gate = _rest_door_inside_world
		second_gate = _rest_door_outside_world

	var seg1: PackedVector2Array = _build_simple_world_path(start_world, first_gate)
	if seg1.is_empty():
		return PackedVector2Array()
	var seg2: PackedVector2Array = _build_simple_world_path(first_gate, second_gate)
	if seg2.is_empty():
		return PackedVector2Array()
	var seg3: PackedVector2Array = _build_simple_world_path(second_gate, end_world)
	if seg3.is_empty():
		return PackedVector2Array()

	return _concat_paths(_concat_paths(seg1, seg2), seg3)

func _build_simple_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _astar == null:
		return PackedVector2Array()

	var start_cell: Vector2i = _find_nearest_walkable_cell(_world_to_cell(start_world))
	var end_cell: Vector2i = _find_nearest_walkable_cell(_world_to_cell(end_world))
	if not _astar.is_in_boundsv(start_cell) or not _astar.is_in_boundsv(end_cell):
		return PackedVector2Array()

	var id_path: Array[Vector2i] = _astar.get_id_path(start_cell, end_cell)
	if id_path.is_empty():
		return PackedVector2Array()

	var world_path: PackedVector2Array = PackedVector2Array()
	for cell in id_path:
		world_path.append(_cell_to_world(cell))
	if world_path[world_path.size() - 1].distance_to(end_world) > 1.0:
		world_path.append(end_world)
	return world_path

func _concat_paths(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
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

func _cells_center_to_world(cells: Array[Vector2i]) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var sum: Vector2 = Vector2.ZERO
	for c in cells:
		sum += _cell_to_world(c)
	return sum / float(cells.size())

func _find_nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if _astar == null:
		return cell
	if _astar.is_in_boundsv(cell) and not _astar.is_point_solid(cell):
		return cell

	for r in range(1, path_search_radius_cells + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				var c: Vector2i = Vector2i(cell.x + dx, cell.y + dy)
				if _astar.is_in_boundsv(c) and not _astar.is_point_solid(c):
					return c

	return cell

func _world_to_cell(world_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = _floor_layer.to_local(world_pos)
	return _floor_layer.local_to_map(local_pos)

func _cell_to_world(cell: Vector2i) -> Vector2:
	var local_pos: Vector2 = _floor_layer.map_to_local(cell)
	return _floor_layer.to_global(local_pos)
