extends CanvasLayer

var _office: Node = null

func setup(office: Node) -> void:
	_office = office

func build_dialogs() -> void:
	if _office == null:
		return

	_office._agent_form_dialog = ConfirmationDialog.new()
	_office._agent_form_dialog.title = "Agent Info"
	_office._agent_form_dialog.ok_button_text = "提交"
	_office._agent_form_dialog.get_cancel_button().text = "取消"
	_office._agent_form_dialog.min_size = Vector2i(620, 0)

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
	_office._agent_form_dialog.add_theme_stylebox_override("panel", form_dialog_panel_style)
	_office._agent_form_dialog.confirmed.connect(_office._on_agent_form_confirmed)
	_office.add_child(_office._agent_form_dialog)

	var form_margin: MarginContainer = MarginContainer.new()
	form_margin.add_theme_constant_override("margin_left", 12)
	form_margin.add_theme_constant_override("margin_top", 10)
	form_margin.add_theme_constant_override("margin_right", 12)
	form_margin.add_theme_constant_override("margin_bottom", 10)
	_office._agent_form_dialog.add_child(form_margin)

	var form_box: VBoxContainer = VBoxContainer.new()
	form_box.custom_minimum_size = Vector2(560.0, 0.0)
	form_box.add_theme_constant_override("separation", 6)
	form_margin.add_child(form_box)

	_office._form_fields.clear()
	add_form_field(form_box, "name", "Name (required)")
	add_form_field(form_box, "emoji", "Emoji")
	add_form_field(form_box, "role", "Role")
	add_form_field(form_box, "vibe", "Vibe")
	add_form_field(form_box, "specialties", "Specialties")
	add_form_field(form_box, "model", "Model")
	add_form_field(form_box, "bind", "Bind")
	add_form_field(form_box, "workspace", "Workspace")

	var form_ok_btn: Button = _office._agent_form_dialog.get_ok_button()
	if form_ok_btn != null:
		form_ok_btn.custom_minimum_size = Vector2(84.0, 32.0)
		style_detail_button(form_ok_btn, true)
	var form_cancel_btn: Button = _office._agent_form_dialog.get_cancel_button()
	if form_cancel_btn != null:
		form_cancel_btn.custom_minimum_size = Vector2(84.0, 32.0)
		style_detail_button(form_cancel_btn, false)

	_office._agent_detail_dialog = AcceptDialog.new()
	_office._agent_detail_dialog.title = "Agent Detail"
	_office._agent_detail_dialog.ok_button_text = "关闭"
	_office._agent_detail_dialog.min_size = Vector2i(620, 0)

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
	_office._agent_detail_dialog.add_theme_stylebox_override("panel", dialog_panel_style)
	_office.add_child(_office._agent_detail_dialog)

	var detail_margin: MarginContainer = MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_left", 12)
	detail_margin.add_theme_constant_override("margin_top", 10)
	detail_margin.add_theme_constant_override("margin_right", 12)
	detail_margin.add_theme_constant_override("margin_bottom", 10)
	_office._agent_detail_dialog.add_child(detail_margin)

	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_box.custom_minimum_size = Vector2(560.0, 0.0)
	detail_box.add_theme_constant_override("separation", 8)
	detail_margin.add_child(detail_box)

	_office._agent_detail_text = RichTextLabel.new()
	_office._agent_detail_text.fit_content = false
	_office._agent_detail_text.scroll_active = true
	_office._agent_detail_text.custom_minimum_size = Vector2(0.0, 180.0)
	_office._agent_detail_text.bbcode_enabled = false
	_office._agent_detail_text.add_theme_color_override("default_color", Color(0.92, 0.96, 1.0, 1.0))

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
	_office._agent_detail_text.add_theme_stylebox_override("normal", detail_text_style)
	detail_box.add_child(_office._agent_detail_text)

	var split_line: HSeparator = HSeparator.new()
	detail_box.add_child(split_line)

	var session_label: Label = Label.new()
	session_label.text = "Session / Task"
	session_label.add_theme_color_override("font_color", Color(0.84, 0.92, 1.0, 1.0))
	detail_box.add_child(session_label)

	_office._agent_session_input = TextEdit.new()
	_office._agent_session_input.custom_minimum_size = Vector2(0.0, 120.0)
	_office._agent_session_input.placeholder_text = "Type a message or task for the current agent"

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
	_office._agent_session_input.add_theme_stylebox_override("normal", session_input_style)
	_office._agent_session_input.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	_office._agent_session_input.add_theme_color_override("font_placeholder_color", Color(0.62, 0.70, 0.80, 0.85))
	detail_box.add_child(_office._agent_session_input)

	var session_action_row: HBoxContainer = HBoxContainer.new()
	session_action_row.add_theme_constant_override("separation", 8)
	detail_box.add_child(session_action_row)

	_office._agent_session_send_btn = Button.new()
	_office._agent_session_send_btn.text = "发送"
	_office._agent_session_send_btn.custom_minimum_size = Vector2(84.0, 32.0)
	style_detail_button(_office._agent_session_send_btn, true)
	_office._agent_session_send_btn.pressed.connect(_office._on_send_agent_session_pressed)
	session_action_row.add_child(_office._agent_session_send_btn)

	_office._agent_session_cancel_btn = Button.new()
	_office._agent_session_cancel_btn.text = "取消"
	_office._agent_session_cancel_btn.custom_minimum_size = Vector2(84.0, 32.0)
	style_detail_button(_office._agent_session_cancel_btn, false)
	_office._agent_session_cancel_btn.pressed.connect(_office._on_cancel_agent_session_pressed)
	session_action_row.add_child(_office._agent_session_cancel_btn)

	var split_line_2: HSeparator = HSeparator.new()
	detail_box.add_child(split_line_2)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	detail_box.add_child(action_row)

	var edit_btn: Button = Button.new()
	edit_btn.text = "修改"
	edit_btn.custom_minimum_size = Vector2(84.0, 30.0)
	style_detail_button(edit_btn, false)
	edit_btn.pressed.connect(_office._on_edit_selected_agent_pressed)
	action_row.add_child(edit_btn)

	var delete_btn: Button = Button.new()
	delete_btn.text = "删除"
	delete_btn.custom_minimum_size = Vector2(84.0, 30.0)
	style_danger_button(delete_btn)
	delete_btn.pressed.connect(_office._on_delete_selected_agent_pressed)
	action_row.add_child(delete_btn)

	var close_btn: Button = _office._agent_detail_dialog.get_ok_button()
	if close_btn != null:
		close_btn.hide()

func style_detail_button(btn: Button, primary: bool) -> void:
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

func style_danger_button(btn: Button) -> void:
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

func add_form_field(parent: VBoxContainer, key: String, label_text: String) -> void:
	if _office == null:
		return

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
	_office._form_fields[key] = input
