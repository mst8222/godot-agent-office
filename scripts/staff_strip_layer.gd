extends CanvasLayer

var _office: Node = null
var _staff_strip_scroll: ScrollContainer = null
var _staff_strip_row: HBoxContainer = null

func setup(office: Node) -> void:
	_office = office
	layer = 80
	_build_ui()

func refresh_ui() -> void:
	if _office == null or _staff_strip_row == null:
		return

	for child in _staff_strip_row.get_children():
		_staff_strip_row.remove_child(child)
		child.free()

	var agent_nodes: Array[Node2D] = []
	for agent_key in _office._agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if is_instance_valid(agent):
			agent_nodes.append(agent)

	agent_nodes.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_meta: Dictionary = _office._agent_meta.get(a, {})
		var b_meta: Dictionary = _office._agent_meta.get(b, {})
		var a_order: int = int(a_meta.get("api_order", 2147483647))
		var b_order: int = int(b_meta.get("api_order", 2147483647))
		if a_order != b_order:
			return a_order < b_order
		var a_id: String = String(a_meta.get("api_id", "")).strip_edges()
		var b_id: String = String(b_meta.get("api_id", "")).strip_edges()
		return a_id < b_id
	)

	for agent in agent_nodes:
		var meta: Dictionary = _office._agent_meta.get(agent, {})
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

func _build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

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
	add_child(panel)

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

func _staff_strip_identity_name(meta: Dictionary) -> String:
	var title_text: String = _office._agent_title_from_meta(meta)
	if title_text != "":
		return title_text

	var api_data_variant: Variant = meta.get("api_data", {})
	var api_data: Dictionary = {}
	if api_data_variant is Dictionary:
		api_data = api_data_variant as Dictionary

	var identity_name: String = _office._agent_name_from_api_data(api_data)
	if identity_name != "":
		return identity_name
	if _is_manager_meta(meta):
		return _manager_agent_name_fallback()
	var api_id_text: String = String(meta.get("api_id", "")).strip_edges()
	return api_id_text if api_id_text != "" else _staff_agent_name_fallback()

func _is_manager_meta(meta: Dictionary) -> bool:
	if String(meta.get("role", "")) == _office.ROLE_MANAGER:
		return true
	var api_data_variant: Variant = meta.get("api_data", {})
	if api_data_variant is Dictionary:
		return _office._is_manager_api_data(api_data_variant as Dictionary)
	return false

func _manager_agent_name_fallback() -> String:
	return char(0x7ECF) + char(0x7406) + "Agent"

func _staff_agent_name_fallback() -> String:
	return char(0x5458) + char(0x5DE5) + "Agent"

func _runtime_status_text_for_list(api_data: Dictionary, meta: Dictionary) -> String:
	var status_text: String = _office._normalize_text(String(api_data.get("runtimeStatus", "")))
	if status_text != "":
		return status_text
	status_text = _office._normalize_text(String(api_data.get("status", "")))
	if status_text != "":
		return status_text
	var state_text: String = _office._normalize_text(String(meta.get("state", "")))
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

func _add_staff_strip_card(display_name: String, runtime_status: String, avatar_tex: Texture2D, agent: Node2D) -> void:
	if _staff_strip_row == null:
		return
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
	await _office._on_agent_clicked(agent)

func _on_staff_strip_card_hover_changed(card: PanelContainer, hover: bool) -> void:
	if card == null or not is_instance_valid(card):
		return
	var style_key: String = "staff_card_style_hover" if hover else "staff_card_style_normal"
	var style_value: Variant = card.get_meta(style_key, null)
	if not (style_value is StyleBoxFlat):
		return
	card.add_theme_stylebox_override("panel", style_value as StyleBoxFlat)
	card.queue_redraw()
