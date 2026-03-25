extends Node

var _office: Node = null

func setup(office: Node) -> void:
	_office = office

func load_agents_from_api() -> void:
	if _office == null:
		return

	print("[API] load agents tick")
	var list_result: Dictionary = await _office._api_request(HTTPClient.METHOD_GET, "/agents")
	if not bool(list_result.get("ok", false)):
		_office.push_warning("读取 Agent 列表失败: %s" % String(list_result.get("error", "unknown error")))
		return

	var agents_data_variant: Variant = list_result.get("data", [])
	if not (agents_data_variant is Array):
		_office.push_warning("Agent 列表格式无效")
		return

	var agents_data: Array = agents_data_variant as Array
	_office._reset_agents_from_api()
	for i in range(0, agents_data.size()):
		var item: Variant = agents_data[i]
		if not (item is Dictionary):
			continue
		var data: Dictionary = item as Dictionary
		var is_manager: bool = _office._is_manager_api_data(data)
		var new_agent: Node2D = _office.AGENT_SCENE.instantiate() as Node2D
		add_child(new_agent)
		_office._setup_new_agent(new_agent, is_manager and _office._manager_agent == null, data, i)
	_office._refresh_staff_strip_ui()

func sync_states_from_api() -> void:
	if _office == null:
		return
	if bool(_office._busy_api):
		return

	var list_result: Dictionary = await _office._api_request(HTTPClient.METHOD_GET, "/agents")
	if not bool(list_result.get("ok", false)):
		_office._warn_sync_error_throttled("同步 Agent 状态失败: %s" % String(list_result.get("error", "unknown error")))
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

	var stale_agents: Array[Node2D] = []
	for agent_key in _office._agent_meta.keys():
		var agent: Node2D = agent_key as Node2D
		if not is_instance_valid(agent):
			stale_agents.append(agent)
			continue
		var meta: Dictionary = _office._agent_meta[agent]
		var existing_id: String = String(meta.get("api_id", "")).strip_edges()
		if existing_id == "" or incoming_by_id.has(existing_id):
			continue
		stale_agents.append(agent)

	for stale in stale_agents:
		if is_instance_valid(stale):
			_office._release_working_marker(stale)
			if stale == _office._manager_agent:
				_office._manager_agent = null
			stale.queue_free()
		_office._agent_meta.erase(stale)

	for api_id_key in incoming_by_id.keys():
		var api_id: String = String(api_id_key)
		var api_data: Dictionary = incoming_by_id[api_id_key] as Dictionary
		var api_order: int = int(incoming_order_by_id.get(api_id, 2147483647))
		var scene_agent: Node2D = _office._find_agent_by_api_id(api_id)
		if scene_agent == null:
			var is_manager: bool = _office._is_manager_api_data(api_data)
			var new_agent: Node2D = _office.AGENT_SCENE.instantiate() as Node2D
			add_child(new_agent)
			_office._setup_new_agent(new_agent, is_manager and _office._manager_agent == null, api_data, api_order)
			continue

		var meta: Dictionary = _office._agent_meta.get(scene_agent, {})
		meta["api_id"] = String(api_data.get("id", api_id))
		meta["api_order"] = api_order
		meta["api_data"] = api_data
		var latest_job: String = _office._agent_role_from_api_data(api_data)
		if latest_job != "":
			meta["job"] = latest_job
		_office._apply_agent_job_sprite(scene_agent, meta, api_data)
		_office._agent_meta[scene_agent] = meta
		_office._update_agent_label(scene_agent)

		var desired_state: String = _office._state_from_api_data(api_data, "")
		if desired_state != "" and String(meta.get("state", "")) != desired_state:
			_office._set_agent_state(scene_agent, desired_state)
	_office._refresh_staff_strip_ui()
