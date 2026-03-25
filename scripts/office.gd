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

@onready var _items_layer: TileMapLayer = $Layers/ItemsLayer

@onready var _worker_rest_pos: Marker2D = $OfficePos/WorkerRestPos
@onready var _manager_work_pos: Marker2D = $OfficePos/ManagerWorktPos
@onready var _manager_rest_pos: Marker2D = $OfficePos/ManagerRestPos
@onready var _api_client_node: Node = $ApiClient
@onready var _agent_visual_config_node: Node = $AgentVisualConfig
@onready var _agent_dialogs_layer_node: CanvasLayer = $AgentDialogsLayer
@onready var _staff_strip_layer_node: CanvasLayer = $StaffStripLayer
@onready var _nav_controller_node: Node = $NavController

var _working_pos_markers: Array[Marker2D] = []

var _manager_agent: Node2D = null
var _agent_meta: Dictionary = {}
var _busy_api: bool = false
var _selected_agent: Node2D = null
var _last_sync_error: String = ""
var _last_sync_error_time_sec: float = -99999.0

var _agent_form_dialog: ConfirmationDialog = null
var _agent_detail_dialog: AcceptDialog = null
var _agent_detail_text: RichTextLabel = null
var _agent_session_input: TextEdit = null
var _agent_session_send_btn: Button = null
var _agent_session_cancel_btn: Button = null
var _busy_session_submit: bool = false
var _form_fields: Dictionary = {}
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
	if _api_client_node != null and _api_client_node.has_method("setup"):
		_api_client_node.call("setup", self)
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("setup"):
		_agent_visual_config_node.call("setup", self)
	if _agent_dialogs_layer_node != null and _agent_dialogs_layer_node.has_method("setup"):
		_agent_dialogs_layer_node.call("setup", self)
	if _items_layer != null and _items_layer.has_method("setup"):
		_items_layer.call("setup", self)
	if _items_layer != null and _items_layer.has_method("cache_rest_door_tiles"):
		_items_layer.call("cache_rest_door_tiles")
	if _nav_controller_node != null and _nav_controller_node.has_method("setup"):
		_nav_controller_node.call("setup", self)
	_load_sprite_frames_pool()
	if _agents_root != null and _agents_root.has_method("setup"):
		_agents_root.call("setup", self)
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
	if _items_layer != null and _items_layer.has_method("update_rest_door_visibility"):
		_items_layer.call("update_rest_door_visibility")

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

	var sprite_key: String = _sprite_job_key(role, api_data, job)
	var assigned_frames: SpriteFrames = _sprite_frames_for_job_key(sprite_key)
	if assigned_frames != null:
		agent.call("set_sprite_frames", assigned_frames)
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
	if _agents_root != null and _agents_root.has_method("sync_states_from_api"):
		await _agents_root.call("sync_states_from_api")
	else:
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
	if _agent_dialogs_layer_node != null and _agent_dialogs_layer_node.has_method("build_dialogs"):
		_agent_dialogs_layer_node.call("build_dialogs")
		return
	push_warning("AgentDialogsLayer script missing")
func _style_detail_button(btn: Button, primary: bool) -> void:
	if _agent_dialogs_layer_node != null and _agent_dialogs_layer_node.has_method("style_detail_button"):
		_agent_dialogs_layer_node.call("style_detail_button", btn, primary)
func _style_danger_button(btn: Button) -> void:
	if _agent_dialogs_layer_node != null and _agent_dialogs_layer_node.has_method("style_danger_button"):
		_agent_dialogs_layer_node.call("style_danger_button", btn)
func _setup_staff_strip_ui() -> void:
	if _staff_strip_layer_node != null and _staff_strip_layer_node.has_method("setup"):
		_staff_strip_layer_node.call("setup", self)

func _refresh_staff_strip_ui() -> void:
	if _staff_strip_layer_node != null and _staff_strip_layer_node.has_method("refresh_ui"):
		_staff_strip_layer_node.call("refresh_ui")

func _add_form_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	if _agent_dialogs_layer_node != null and _agent_dialogs_layer_node.has_method("add_form_field"):
		_agent_dialogs_layer_node.call("add_form_field", parent, key, label_text)
		return
	push_warning("AgentDialogsLayer script missing")
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
	if _agent_detail_text != null and (_selected_agent == null or not _agent_meta.has(_selected_agent)):
		_agent_detail_text.text = _build_partial_agent_detail_text_from_node(_selected_agent)
		_agent_detail_text.scroll_to_line(0)
		_set_agent_session_ui_enabled(false)
		_agent_detail_dialog.popup_centered()
		return
	_refresh_selected_agent_detail()
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
		push_warning("No selected agent")
		return
	if _agent_session_input == null:
		return

	var message_text: String = _agent_session_input.text.strip_edges()
	if message_text == "":
		push_warning("Session message is required")
		return

	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_id: String = String(meta.get("api_id", "")).strip_edges()
	if api_id == "":
		push_warning("Current agent has no API ID")
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
		push_warning("Failed to send session: %s" % String(session_result.get("error", "unknown error")))
		return

	var response_json_variant: Variant = session_result.get("json", {})
	var response_json: Dictionary = {}
	if response_json_variant is Dictionary:
		response_json = response_json_variant as Dictionary
	var accepted: bool = bool(response_json.get("accepted", false))
	if not accepted:
		push_warning("Session was not accepted by agent")
		return

	_agent_session_input.text = ""
func _refresh_selected_agent_detail() -> void:
	if _selected_agent == null or not _agent_meta.has(_selected_agent):
		if _agent_detail_text != null:
			_agent_detail_text.text = _build_partial_agent_detail_text_from_node(_selected_agent)
			_agent_detail_text.scroll_to_line(0)
		_set_agent_session_ui_enabled(false)
		return
	var meta: Dictionary = _agent_meta[_selected_agent]
	var api_data_variant: Variant = meta.get("api_data", {})
	var api_data: Dictionary = {}
	if api_data_variant is Dictionary:
		api_data = api_data_variant as Dictionary

	_agent_detail_text.text = _build_agent_detail_text(meta, api_data)
	if _agent_detail_text.text.strip_edges() == "":
		_agent_detail_text.text = _build_agent_detail_text_fallback(meta, api_data)
	_agent_detail_text.scroll_to_line(0)

func _build_partial_agent_detail_text_from_node(agent: Node2D) -> String:
	var lines: PackedStringArray = []
	lines.append("Agent Info (partial)")
	if agent == null or not is_instance_valid(agent):
		lines.append("Node: <invalid>")
		lines.append("Reason: metadata missing and node is invalid")
		return "\n".join(lines)

	lines.append("Node: %s" % String(agent.name))
	lines.append("Scene: %s" % String(agent.scene_file_path))
	lines.append("Position: (%.1f, %.1f)" % [agent.global_position.x, agent.global_position.y])

	var display_name: String = ""
	var has_display_name_property: bool = false
	for prop in agent.get_property_list():
		if String((prop as Dictionary).get("name", "")) == "display_name":
			has_display_name_property = true
			break
	if has_display_name_property:
		display_name = String(agent.get("display_name")).strip_edges()
	if display_name != "":
		lines.append("Display: %s" % display_name)

	var moving_text: String = "unknown"
	if agent.has_method("is_moving"):
		moving_text = "yes" if bool(agent.call("is_moving")) else "no"
	lines.append("Moving: %s" % moving_text)

	var anim: AnimatedSprite2D = agent.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		lines.append("Anim: %s" % String(anim.animation))
		lines.append("Frame: %d" % int(anim.frame))

	lines.append("")
	lines.append("API metadata is missing for this node.")
	return "\n".join(lines)

func _build_agent_detail_text(meta: Dictionary, api_data: Dictionary) -> String:
	var role_text: String = _variant_to_text(meta.get("role", ""))
	var state_text: String = _variant_to_text(meta.get("state", ""))
	var id_text: String = _variant_to_text(meta.get("api_id", ""))
	var name_text: String = _agent_name_from_api_data(api_data)
	var api_role: String = _agent_role_from_api_data(api_data)
	var model_text: String = _variant_to_text(api_data.get("model", ""))
	var workspace_text: String = _variant_to_text(api_data.get("workspace", ""))
	var bind_text: String = _bind_to_string(api_data.get("bind", ""))
	var specialties_text: String = _variant_to_text(api_data.get("specialties", ""))
	var vibe_text: String = _variant_to_text(api_data.get("vibe", ""))

	var lines: PackedStringArray = []
	lines.append("Agent Info")
	lines.append("ID: %s" % id_text)
	lines.append("Name: %s" % name_text)
	lines.append("Role: %s / %s" % [role_text, api_role])
	lines.append("State: %s" % state_text)
	lines.append("")
	lines.append("Config")
	lines.append("Model: %s" % model_text)
	lines.append("Bind: %s" % bind_text)
	lines.append("Workspace: %s" % workspace_text)
	lines.append("")
	lines.append("Traits")
	lines.append("Specialties: %s" % specialties_text)
	lines.append("Vibe: %s" % vibe_text)
	return "\n".join(lines)

func _build_agent_detail_text_fallback(meta: Dictionary, api_data: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("Agent Info (fallback)")
	lines.append("Metadata exists but rendered detail text is empty.")
	lines.append("")
	lines.append("meta.api_id: %s" % _variant_to_text(meta.get("api_id", "")))
	lines.append("meta.role: %s" % _variant_to_text(meta.get("role", "")))
	lines.append("meta.job: %s" % _variant_to_text(meta.get("job", "")))
	lines.append("meta.state: %s" % _variant_to_text(meta.get("state", "")))
	lines.append("")
	lines.append("api.id: %s" % _variant_to_text(api_data.get("id", "")))
	lines.append("api.identityName: %s" % _variant_to_text(api_data.get("identityName", "")))
	lines.append("api.runtimeStatus: %s" % _variant_to_text(api_data.get("runtimeStatus", "")))
	lines.append("api.specialties: %s" % _variant_to_text(api_data.get("specialties", "")))
	lines.append("api.vibe: %s" % _variant_to_text(api_data.get("vibe", "")))
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
		push_warning("Current agent has no API ID")
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
	if _agents_root != null and _agents_root.has_method("load_agents_from_api"):
		await _agents_root.call("load_agents_from_api")
		return
	push_warning("Agents node script missing")

func _sync_states_from_api() -> void:
	if _agents_root != null and _agents_root.has_method("sync_states_from_api"):
		await _agents_root.call("sync_states_from_api")
		return
	_warn_sync_error_throttled("Agents node script missing")
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
	if _api_client_node != null and _api_client_node.has_method("request"):
		return await _api_client_node.call("request", method, endpoint, payload)
	return {"ok": false, "error": "api client unavailable"}
func _api_request_with_base(base_url: String, method: int, endpoint: String, payload: Dictionary) -> Dictionary:
	if _api_client_node != null and _api_client_node.has_method("request_with_base"):
		return await _api_client_node.call("request_with_base", base_url, method, endpoint, payload)
	return {"ok": false, "error": "api client unavailable", "network_error": true}
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
	if bind_value == null:
		return ""
	if bind_value is Array:
		var binds: Array = bind_value as Array
		var out: PackedStringArray = []
		for item in binds:
			out.append(_variant_to_text(item))
		return ",".join(out)
	return _variant_to_text(bind_value)

func _variant_to_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is String:
		return String(value).strip_edges()
	return str(value).strip_edges()

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
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("load_sprite_frames_pool"):
		_agent_visual_config_node.call("load_sprite_frames_pool")
		return
	push_warning("AgentVisualConfig script missing")
func _random_sprite_frames() -> SpriteFrames:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("random_sprite_frames"):
		var result: Variant = _agent_visual_config_node.call("random_sprite_frames")
		if result is SpriteFrames:
			return result as SpriteFrames
	return null
func _refill_unused_pool() -> void:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("refill_unused_pool"):
		_agent_visual_config_node.call("refill_unused_pool")
func _sprite_job_key(role: String, api_data: Dictionary, fallback_job: String) -> String:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("sprite_job_key"):
		return String(_agent_visual_config_node.call("sprite_job_key", role, api_data, fallback_job))
	return "job:default"
func _sprite_frames_for_job_key(job_key: String) -> SpriteFrames:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("sprite_frames_for_job_key"):
		var result: Variant = _agent_visual_config_node.call("sprite_frames_for_job_key", job_key)
		if result is SpriteFrames:
			return result as SpriteFrames
	return null
func _fixed_sprite_resource_id_for_job_key(job_key: String) -> String:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("fixed_sprite_resource_id_for_job_key"):
		return String(_agent_visual_config_node.call("fixed_sprite_resource_id_for_job_key", job_key))
	return "adam"
func _apply_agent_job_sprite(agent: Node2D, meta: Dictionary, api_data: Dictionary) -> void:
	if _agent_visual_config_node != null and _agent_visual_config_node.has_method("apply_agent_job_sprite"):
		_agent_visual_config_node.call("apply_agent_job_sprite", agent, meta, api_data)
func _move_agent_to(agent: Node2D, target_world: Vector2) -> void:
	if _nav_controller_node != null and _nav_controller_node.has_method("move_agent_to"):
		_nav_controller_node.call("move_agent_to", agent, target_world)
		return
	if agent != null and agent.has_method("move_to"):
		agent.call("move_to", target_world)
func _resolve_reachable_nav_target(from_world: Vector2, target_world: Vector2) -> Vector2:
	if _nav_controller_node != null and _nav_controller_node.has_method("resolve_reachable_nav_target"):
		return _nav_controller_node.call("resolve_reachable_nav_target", from_world, target_world)
	return target_world
func _build_nav_grid() -> void:
	if _nav_controller_node != null and _nav_controller_node.has_method("build_nav_grid"):
		_nav_controller_node.call("build_nav_grid")
func _force_open_door_cells() -> void:
	if _nav_controller_node != null and _nav_controller_node.has_method("force_open_door_cells"):
		_nav_controller_node.call("force_open_door_cells")
func _is_cell_blocked(cell: Vector2i) -> bool:
	if _nav_controller_node != null and _nav_controller_node.has_method("is_cell_blocked"):
		return bool(_nav_controller_node.call("is_cell_blocked", cell))
	return false
func _tile_has_collision(layer: TileMapLayer, cell: Vector2i) -> bool:
	if _nav_controller_node != null and _nav_controller_node.has_method("tile_has_collision"):
		return bool(_nav_controller_node.call("tile_has_collision", layer, cell))
	return false
func _build_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _nav_controller_node != null and _nav_controller_node.has_method("build_world_path"):
		return _nav_controller_node.call("build_world_path", start_world, end_world)
	return PackedVector2Array([end_world])
func _build_path_via_rest_door(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _nav_controller_node != null and _nav_controller_node.has_method("build_path_via_rest_door"):
		return _nav_controller_node.call("build_path_via_rest_door", start_world, end_world)
	return PackedVector2Array()
func _build_simple_world_path(start_world: Vector2, end_world: Vector2) -> PackedVector2Array:
	if _nav_controller_node != null and _nav_controller_node.has_method("build_simple_world_path"):
		return _nav_controller_node.call("build_simple_world_path", start_world, end_world)
	return PackedVector2Array()
func _concat_paths(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if _nav_controller_node != null and _nav_controller_node.has_method("concat_paths"):
		return _nav_controller_node.call("concat_paths", a, b)
	return PackedVector2Array()
func _cells_center_to_world(cells: Array[Vector2i]) -> Vector2:
	if _nav_controller_node != null and _nav_controller_node.has_method("cells_center_to_world"):
		return _nav_controller_node.call("cells_center_to_world", cells)
	return Vector2.ZERO
func _find_nearest_walkable_cell(cell: Vector2i) -> Vector2i:
	if _nav_controller_node != null and _nav_controller_node.has_method("find_nearest_walkable_cell"):
		return _nav_controller_node.call("find_nearest_walkable_cell", cell)
	return cell
func _world_to_cell(world_pos: Vector2) -> Vector2i:
	if _nav_controller_node != null and _nav_controller_node.has_method("world_to_cell"):
		return _nav_controller_node.call("world_to_cell", world_pos)
	return Vector2i.ZERO
func _cell_to_world(cell: Vector2i) -> Vector2:
	if _nav_controller_node != null and _nav_controller_node.has_method("cell_to_world"):
		return _nav_controller_node.call("cell_to_world", cell)
	return Vector2.ZERO
