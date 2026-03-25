extends Node

var _office: Node = null
var _sprite_frames_pool: Array[SpriteFrames] = []
var _unused_sprite_frames_pool: Array[SpriteFrames] = []
var _last_assigned_frames: SpriteFrames = null
var _sprite_frames_by_job_key: Dictionary = {}
var _sprite_frames_by_resource_id: Dictionary = {}

func setup(office: Node) -> void:
	_office = office

func load_sprite_frames_pool() -> void:
	_sprite_frames_pool.clear()
	_unused_sprite_frames_pool.clear()
	_sprite_frames_by_job_key.clear()
	_sprite_frames_by_resource_id.clear()
	var dir: DirAccess = DirAccess.open(String(_office.ANIM_RESOURCE_DIR))
	if dir == null:
		_office.push_warning("Cannot open animation resource directory: %s" % String(_office.ANIM_RESOURCE_DIR))
		return

	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(String(_office.ANIM_RESOURCE_SUFFIX)):
			continue

		var full_path: String = "%s/%s" % [String(_office.ANIM_RESOURCE_DIR), file_name]
		var loaded_resource: Resource = load(full_path)
		var frames: SpriteFrames = loaded_resource as SpriteFrames
		if frames != null:
			_sprite_frames_pool.append(frames)
			var resource_id: String = file_name
			var suffix: String = String(_office.ANIM_RESOURCE_SUFFIX)
			if resource_id.ends_with(suffix):
				resource_id = resource_id.substr(0, resource_id.length() - suffix.length())
			resource_id = _normalize_text(resource_id).to_lower()
			if resource_id != "":
				_sprite_frames_by_resource_id[resource_id] = frames
	dir.list_dir_end()
	refill_unused_pool()

func random_sprite_frames() -> SpriteFrames:
	if _sprite_frames_pool.is_empty():
		return null
	if _unused_sprite_frames_pool.is_empty():
		refill_unused_pool()

	if not _unused_sprite_frames_pool.is_empty():
		var next_frames: SpriteFrames = _unused_sprite_frames_pool.pop_back() as SpriteFrames
		_last_assigned_frames = next_frames
		return next_frames

	var fallback: SpriteFrames = _sprite_frames_pool[randi() % _sprite_frames_pool.size()]
	_last_assigned_frames = fallback
	return fallback

func refill_unused_pool() -> void:
	_unused_sprite_frames_pool = _sprite_frames_pool.duplicate()
	_unused_sprite_frames_pool.shuffle()
	if _unused_sprite_frames_pool.size() > 1 and _last_assigned_frames != null:
		if _unused_sprite_frames_pool.back() == _last_assigned_frames:
			var first: SpriteFrames = _unused_sprite_frames_pool[0]
			_unused_sprite_frames_pool[0] = _unused_sprite_frames_pool.back()
			_unused_sprite_frames_pool[_unused_sprite_frames_pool.size() - 1] = first

func sprite_job_key(role: String, api_data: Dictionary, fallback_job: String) -> String:
	var normalized_role: String = _normalize_text(role)
	if normalized_role == String(_office.ROLE_MANAGER):
		return "role:manager"

	var api_id: String = _normalize_text(String(api_data.get("id", ""))).to_lower()
	if api_id != "":
		return "id:%s" % api_id

	var api_role: String = _normalize_text(_office._agent_role_from_api_data(api_data))
	if api_role != "":
		return "job:%s" % api_role.to_lower()

	var api_name: String = _normalize_text(_office._agent_name_from_api_data(api_data))
	var normalized_job: String = _normalize_text(fallback_job)
	# fallback_job already carries business intent from office.gd (api role/name chosen upstream).
	# Do not force fallback to role:员工 when fallback_job equals api_name.
	if normalized_job != "":
		return "job:%s" % normalized_job.to_lower()
	if api_name != "":
		return "job:%s" % api_name.to_lower()

	if normalized_role != "":
		return "role:%s" % normalized_role.to_lower()
	return "job:default"

func sprite_frames_for_job_key(job_key: String) -> SpriteFrames:
	var key: String = _normalize_text(job_key)
	if key == "":
		key = "job:default"

	var fixed_resource_id: String = fixed_sprite_resource_id_for_job_key(key)
	if fixed_resource_id != "":
		var fixed_frames_variant: Variant = _sprite_frames_by_resource_id.get(fixed_resource_id, null)
		if fixed_frames_variant is SpriteFrames:
			var fixed_frames: SpriteFrames = fixed_frames_variant as SpriteFrames
			_sprite_frames_by_job_key[key] = fixed_frames
			return fixed_frames

	if _sprite_frames_by_job_key.has(key):
		var cached: Variant = _sprite_frames_by_job_key[key]
		if cached is SpriteFrames:
			return cached as SpriteFrames

	var assigned: SpriteFrames = random_sprite_frames()
	if assigned != null:
		_sprite_frames_by_job_key[key] = assigned
	return assigned

func fixed_sprite_resource_id_for_job_key(job_key: String) -> String:
	var key: String = _normalize_text(job_key).to_lower()
	if key == "":
		return "adam"

	if key.begins_with("id:"):
		var api_id: String = key.substr(3, key.length() - 3)
		if api_id == "art" or api_id == "analyst":
			return "amalia"
		if api_id == "frontend" or api_id == "devops":
			return "alex"
		if api_id == "backend" or api_id == "godot":
			return "bob"
		return "adam"

	var kw_art_designer: String = "%s%s%s%s%s" % [char(0x7F8E), char(0x672F), char(0x8BBE), char(0x8BA1), char(0x5E08)]
	var kw_data_analyst: String = "%s%s%s%s%s" % [char(0x6570), char(0x636E), char(0x5206), char(0x6790), char(0x5E08)]
	var kw_art: String = "%s%s" % [char(0x7F8E), char(0x672F)]
	var kw_data_analysis: String = "%s%s%s%s" % [char(0x6570), char(0x636E), char(0x5206), char(0x6790)]
	var kw_frontend: String = "%s%s" % [char(0x524D), char(0x7AEF)]
	var kw_ops: String = "%s%s" % [char(0x8FD0), char(0x7EF4)]
	var kw_backend: String = "%s%s" % [char(0x540E), char(0x7AEF)]

	if key.contains(kw_art_designer) or key.contains(kw_data_analyst) or key.contains(kw_art) or key.contains(kw_data_analysis):
		return "amalia"
	if key.contains(kw_frontend) or key.contains(kw_ops) or key.contains("frontend") or key.contains("devops"):
		return "alex"
	if key.contains(kw_backend) or key.contains("godot") or key.contains("backend"):
		return "bob"
	return "adam"

func apply_agent_job_sprite(agent: Node2D, meta: Dictionary, api_data: Dictionary) -> void:
	if agent == null or not is_instance_valid(agent):
		return
	if not agent.has_method("set_sprite_frames"):
		return
	var role_text: String = String(meta.get("role", ""))
	var job_text: String = String(meta.get("job", ""))
	var key: String = sprite_job_key(role_text, api_data, job_text)
	var frames: SpriteFrames = sprite_frames_for_job_key(key)
	if frames != null:
		agent.call("set_sprite_frames", frames)

func _normalize_text(text: String) -> String:
	return text.strip_edges()
