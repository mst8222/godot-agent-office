extends CharacterBody2D

signal agent_clicked(agent: Node2D)
signal agent_arrived(agent: Node2D)

enum AgentState {
	IDLE,
	RUNNING,
	PHONE
}

const IDLE_PREFIX := "idel-"
const RUN_PREFIX := "run-"
const PHONE_ANIM := "playphone"
const DIR_DOWN := "down"
const DIR_LEFT := "left"
const DIR_RIGHT := "right"
const DIR_UP := "up"
const MIN_MOVE_ANIM_SPEED := 8.0

@export var move_speed: float = 120.0
@export var stop_distance: float = 2.0
@export var display_name: String = ""
@export var idle_phone_chance: float = 0.28

var _state: AgentState = AgentState.IDLE
var _target_position: Vector2
var _moving: bool = false
var _facing: String = DIR_DOWN
var _path_points: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _use_navigation_agent: bool = true
var _safe_velocity: Vector2 = Vector2.ZERO
var _force_direct_move: bool = false
var _is_working: bool = false

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _label: Label = $Label
@onready var _nav_agent: NavigationAgent2D = _ensure_nav_agent()

func _ready() -> void:
	_target_position = global_position
	input_pickable = true
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, false)
	if display_name.strip_edges() != "":
		_label.text = display_name
	_play_stationary_animation()
	input_event.connect(_on_body_input_event)
	if _nav_agent != null and not _nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		_nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(_delta: float) -> void:
	if _moving:
		var to_target: Vector2 = _target_position - global_position
		if _use_navigation_agent and _nav_agent != null and not _force_direct_move:
			if _nav_agent.is_navigation_finished():
				global_position = _target_position
				velocity = Vector2.ZERO
				_moving = false
				_force_direct_move = false
				_play_stationary_animation()
				agent_arrived.emit(self)
				move_and_slide()
				return
			var next_path_pos: Vector2 = _nav_agent.get_next_path_position()
			to_target = next_path_pos - global_position

		var distance: float = to_target.length()
		if distance <= stop_distance:
			if _advance_path_target():
				to_target = _target_position - global_position
				distance = to_target.length()
			else:
				global_position = _target_position
				velocity = Vector2.ZERO
				_moving = false
				_force_direct_move = false
				_play_stationary_animation()
				agent_arrived.emit(self)
				move_and_slide()
				return

		if distance > 0.0:
			var direction: Vector2 = to_target / distance
			var desired_velocity: Vector2 = direction * move_speed
			if _use_navigation_agent and _nav_agent != null and _nav_agent.avoidance_enabled and not _force_direct_move:
				_nav_agent.set_velocity(desired_velocity)
				velocity = _safe_velocity if _safe_velocity.length() > 0.0 else desired_velocity
			else:
				velocity = desired_velocity
			_facing = _direction_to_name(direction)
			_state = AgentState.RUNNING
			_play_run(_facing)
	else:
		velocity = Vector2.ZERO

	move_and_slide()

func set_sprite_frames(frames: SpriteFrames) -> void:
	if frames == null:
		return
	_anim.sprite_frames = frames
	_play_stationary_animation()

func set_display_name(name_text: String) -> void:
	display_name = name_text
	if is_node_ready():
		_label.text = display_name

func move_to(world_position: Vector2) -> void:
	_path_points = PackedVector2Array()
	_path_index = 0
	_target_position = world_position
	_force_direct_move = false
	if _use_navigation_agent and _nav_agent != null:
		_nav_agent.target_position = world_position
	_moving = true

func move_to_direct(world_position: Vector2) -> void:
	_path_points = PackedVector2Array()
	_path_index = 0
	_target_position = world_position
	_force_direct_move = true
	_moving = true

func move_along_path(path_points: PackedVector2Array) -> void:
	if _use_navigation_agent and _nav_agent != null and not path_points.is_empty():
		move_to(path_points[path_points.size() - 1])
		return
	if path_points.is_empty():
		move_to(global_position)
		return

	_path_points = path_points
	_path_index = 0
	_target_position = _path_points[0]
	_moving = true

func is_moving() -> bool:
	return _moving

func play_phone() -> void:
	if _is_working:
		_play_idle(DIR_DOWN)
		return
	_moving = false
	_force_direct_move = false
	_path_points = PackedVector2Array()
	_path_index = 0
	velocity = Vector2.ZERO
	_state = AgentState.PHONE
	_play_if_exists(PHONE_ANIM)

func stop_phone() -> void:
	_play_stationary_animation()

func set_working(working: bool) -> void:
	_is_working = working
	if _moving:
		return
	_play_stationary_animation()

func _advance_path_target() -> bool:
	if _path_points.is_empty():
		return false

	_path_index += 1
	if _path_index >= _path_points.size():
		return false

	_target_position = _path_points[_path_index]
	return true

func _direction_to_name(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return DIR_RIGHT if direction.x > 0.0 else DIR_LEFT
	return DIR_DOWN if direction.y > 0.0 else DIR_UP

func _play_idle(dir_name: String) -> void:
	_play_if_exists(IDLE_PREFIX + dir_name)

func _play_run(dir_name: String) -> void:
	_play_if_exists(RUN_PREFIX + dir_name)
	_anim.speed_scale = maxf(MIN_MOVE_ANIM_SPEED / maxf(move_speed, 1.0), 0.75)

func _play_if_exists(anim_name: String) -> void:
	if _anim.sprite_frames == null:
		return
	if not _anim.sprite_frames.has_animation(anim_name):
		return
	if _anim.animation != StringName(anim_name):
		_anim.animation = StringName(anim_name)
	_anim.play()

func _play_stationary_animation() -> void:
	_anim.speed_scale = 1.0
	if _is_working:
		_state = AgentState.IDLE
		_play_idle(DIR_DOWN)
		return

	if _anim.sprite_frames != null and _anim.sprite_frames.has_animation(PHONE_ANIM) and randf() < clampf(idle_phone_chance, 0.0, 1.0):
		_state = AgentState.PHONE
		_play_if_exists(PHONE_ANIM)
		return

	_state = AgentState.IDLE
	_play_idle(_facing)

func _on_body_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		agent_clicked.emit(self)

func _ensure_nav_agent() -> NavigationAgent2D:
	var agent_node: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if agent_node == null:
		agent_node = NavigationAgent2D.new()
		agent_node.name = "NavigationAgent2D"
		add_child(agent_node)

	agent_node.path_desired_distance = 4.0
	agent_node.target_desired_distance = 6.0
	agent_node.path_max_distance = 64.0
	agent_node.radius = 8.0
	agent_node.neighbor_distance = 36.0
	agent_node.max_neighbors = 10
	agent_node.time_horizon_agents = 0.9
	agent_node.avoidance_enabled = true
	return agent_node

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity
