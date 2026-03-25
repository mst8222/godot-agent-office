extends CharacterBody2D

const ANIM_IDLE: StringName = &"Idle"
const ANIM_MOVING: StringName = &"Moving"
const DOOR_TRIGGER_GROUP: StringName = &"door_trigger_actor"

@export var move_speed: float = 32.0
@export var stop_distance: float = 6.0
@export var wander_radius: float = 420.0
@export var pause_min_sec: float = 1.2
@export var pause_max_sec: float = 3.8
@export var sample_attempts: int = 24

var _moving: bool = false
var _idle_deadline_sec: float = 0.0
var _safe_velocity: Vector2 = Vector2.ZERO

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _nav_agent: NavigationAgent2D = _ensure_nav_agent()

func _ready() -> void:
	add_to_group(DOOR_TRIGGER_GROUP)
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, false)
	if _collision != null:
		_collision.disabled = false
	if _anim != null and _anim.sprite_frames != null and _anim.sprite_frames.has_animation(String(ANIM_MOVING)):
		_anim.sprite_frames.set_animation_loop(String(ANIM_MOVING), true)
	_play_idle()
	_begin_idle_pause()
	if _nav_agent != null and not _nav_agent.velocity_computed.is_connected(_on_velocity_computed):
		_nav_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(_delta: float) -> void:
	if _moving:
		_update_move()
	else:
		velocity = Vector2.ZERO
		if _now_sec() >= _idle_deadline_sec:
			_start_random_move()
	move_and_slide()

func _update_move() -> void:
	if _nav_agent == null:
		_finish_move()
		return
	if _nav_agent.is_navigation_finished():
		_finish_move()
		return

	var next_pos: Vector2 = _nav_agent.get_next_path_position()
	var to_next: Vector2 = next_pos - global_position
	var distance: float = to_next.length()
	if distance <= stop_distance:
		_finish_move()
		return

	var dir: Vector2 = to_next / maxf(distance, 0.001)
	var desired_velocity: Vector2 = dir * move_speed
	if _nav_agent.avoidance_enabled:
		_nav_agent.set_velocity(desired_velocity)
		velocity = _safe_velocity if _safe_velocity.length() > 0.0 else desired_velocity
	else:
		velocity = desired_velocity

	if absf(velocity.x) > 0.05 and _anim != null:
		_anim.flip_h = velocity.x < 0.0
	_play_moving()

func _start_random_move() -> void:
	if _nav_agent == null:
		_begin_idle_pause()
		return
	var target: Vector2 = _pick_wander_target()
	if global_position.distance_to(target) <= stop_distance:
		_begin_idle_pause()
		return
	_nav_agent.target_position = target
	_moving = true
	_play_moving()

func _finish_move() -> void:
	_moving = false
	velocity = Vector2.ZERO
	_play_idle()
	_begin_idle_pause()

func _begin_idle_pause() -> void:
	var wait_sec: float = randf_range(maxf(0.2, pause_min_sec), maxf(pause_min_sec, pause_max_sec))
	_idle_deadline_sec = _now_sec() + wait_sec

func _pick_wander_target() -> Vector2:
	var world2d_ref: World2D = get_world_2d()
	if world2d_ref == null:
		return global_position
	var nav_map: RID = world2d_ref.navigation_map
	if not nav_map.is_valid():
		return global_position

	for _i in range(sample_attempts):
		var ang: float = randf_range(0.0, TAU)
		var dist: float = randf_range(32.0, maxf(32.0, wander_radius))
		var candidate: Vector2 = global_position + Vector2.RIGHT.rotated(ang) * dist
		var on_nav: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, candidate)
		var path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, global_position, on_nav, true)
		if path.size() >= 2:
			return on_nav

	var fallback: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, global_position)
	var fallback_path: PackedVector2Array = NavigationServer2D.map_get_path(nav_map, global_position, fallback, true)
	if fallback_path.size() >= 2:
		return fallback
	return global_position

func _play_idle() -> void:
	if _anim == null:
		return
	if _anim.animation != ANIM_IDLE:
		_anim.animation = ANIM_IDLE
	_anim.play()

func _play_moving() -> void:
	if _anim == null:
		return
	if _anim.animation != ANIM_MOVING:
		_anim.animation = ANIM_MOVING
	_anim.play()

func _ensure_nav_agent() -> NavigationAgent2D:
	var agent_node: NavigationAgent2D = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if agent_node == null:
		agent_node = NavigationAgent2D.new()
		agent_node.name = "NavigationAgent2D"
		add_child(agent_node)

	agent_node.path_desired_distance = 4.0
	agent_node.target_desired_distance = 8.0
	agent_node.path_max_distance = 96.0
	agent_node.radius = 8.0
	agent_node.neighbor_distance = 28.0
	agent_node.max_neighbors = 8
	agent_node.time_horizon_agents = 0.8
	agent_node.avoidance_enabled = true
	return agent_node

func _on_velocity_computed(safe_velocity: Vector2) -> void:
	_safe_velocity = safe_velocity

func _now_sec() -> float:
	return Time.get_ticks_msec() / 1000.0
