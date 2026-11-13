class_name EchoPlayer
extends CharacterBody2D

signal sound_emitted(origin: Vector2, strength: float)
signal impulse_received(impulse: Vector2, source: String)
signal wall_impact(origin: Vector2, normal: Vector2, strength: float)
signal rebound_resolved(drop_pixels: float, tier: int, rebound_pixels: float)

@export var speed: float = 250.0
@export var acceleration: float = 1800.0
@export var jump_velocity: float = -560.0
@export var gravity: float = 1500.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12
@export var show_body_in_eye: bool = false
@export var direct_jump_enabled: bool = true
@export var collision_rebound_enabled: bool = false
@export var rebound_ratio: float = 0.55
@export var impulse_drag_ground: float = 450.0
@export var impulse_drag_air: float = 120.0
@export var movement_rules: MovementRules = preload("res://resources/movement_rules.tres")

var controls_enabled: bool = false
var debug_visible: bool = false
var _coyote_remaining: float = 0.0
var _jump_remaining: float = 0.0
var _step_distance: float = 0.0
var _clear_platform_on_next_step: bool = false
var _external_x: float = 0.0
var _impact_cooldown: float = 0.0
var _fall_apex_y: float = 0.0
var _tracking_fall: bool = false
var last_drop_pixels: float = 0.0
var last_rebound_tier: int = 0
var last_rebound_pixels: float = 0.0

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return
	var was_grounded := is_on_floor()
	if not _tracking_fall or (was_grounded and velocity.y >= 0.0):
		_fall_apex_y = global_position.y
		_tracking_fall = true
	_fall_apex_y = minf(_fall_apex_y, global_position.y)
	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)
	_coyote_remaining = coyote_time if was_grounded else maxf(0.0, _coyote_remaining - delta)
	_jump_remaining = maxf(0.0, _jump_remaining - delta)
	if direct_jump_enabled and Input.is_action_just_pressed("jump"):
		_jump_remaining = jump_buffer
	var axis := Input.get_axis("move_left", "move_right")
	var controlled_x := velocity.x - _external_x
	controlled_x = move_toward(controlled_x, axis * speed, acceleration * delta)
	_external_x = move_toward(_external_x, 0.0, (impulse_drag_ground if was_grounded else impulse_drag_air) * delta)
	velocity.x = controlled_x + _external_x
	velocity.y = minf(velocity.y + gravity * delta, 1000.0)
	if direct_jump_enabled and _jump_remaining > 0.0 and _coyote_remaining > 0.0:
		velocity.y = jump_velocity
		_jump_remaining = 0.0
		_coyote_remaining = 0.0
		sound_emitted.emit(global_position + Vector2(0, 20), 0.6)
	if direct_jump_enabled and Input.is_action_just_released("jump") and velocity.y < -200.0:
		velocity.y = -200.0
	# A respawn must not inherit the old ferry's teleport velocity or cached floor attachment.
	if _clear_platform_on_next_step:
		platform_floor_layers = 0
	var incoming := velocity
	move_and_slide()
	_fall_apex_y = minf(_fall_apex_y, global_position.y)
	if collision_rebound_enabled and _impact_cooldown <= 0.0:
		for i in range(get_slide_collision_count()):
			var contact := get_slide_collision(i)
			var normal := contact.get_normal()
			if normal.y < -0.7:
				if not was_grounded:
					_resolve_landing(contact.get_position())
				continue
			var impact_speed := -incoming.dot(normal)
			if impact_speed > 100.0:
				_external_x = 0.0 if absf(normal.x) > 0.7 else _external_x
				_impact_cooldown = 0.2
				var force := normal * maxf(130.0, impact_speed * rebound_ratio)
				add_impulse(force, "撞击反弹")
				wall_impact.emit(contact.get_position(), normal, force.length())
				break
	if _clear_platform_on_next_step:
		platform_floor_layers = 1
		_clear_platform_on_next_step = false
	if is_on_floor():
		if not was_grounded:
			sound_emitted.emit(global_position + Vector2(0, 20), 1.0)
		_step_distance += absf(velocity.x) * delta
		if _step_distance > 66.0:
			_step_distance = 0.0
			sound_emitted.emit(global_position + Vector2(0, 20), 0.48)
	queue_redraw()

func reset_to(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	_coyote_remaining = 0.0
	_jump_remaining = 0.0
	_step_distance = 0.0
	_clear_platform_on_next_step = true
	_external_x = 0.0
	_impact_cooldown = 0.0
	_fall_apex_y = point.y
	_tracking_fall = true
	last_drop_pixels = 0.0
	last_rebound_tier = 0
	last_rebound_pixels = 0.0
	reset_physics_interpolation()

func _resolve_landing(contact_position: Vector2) -> void:
	last_drop_pixels = maxf(0.0, global_position.y - _fall_apex_y)
	last_rebound_tier = movement_rules.rebound_tier(last_drop_pixels)
	last_rebound_pixels = movement_rules.rebound_height_pixels(last_rebound_tier)
	if last_rebound_tier > 0:
		var launch := movement_rules.launch_speed(last_rebound_pixels, gravity)
		velocity.y = -launch
		_fall_apex_y = global_position.y
		_impact_cooldown = 0.2
		impulse_received.emit(Vector2(0, -launch), "落地反弹")
		wall_impact.emit(contact_position, Vector2.UP, launch)
	if last_drop_pixels >= movement_rules.tile_size * 0.5:
		rebound_resolved.emit(last_drop_pixels, last_rebound_tier, last_rebound_pixels)

func add_impulse(impulse: Vector2, source: String = "声波推力") -> void:
	var previous_y := velocity.y
	_external_x = clampf(_external_x + impulse.x, -900.0, 900.0)
	velocity.x = clampf(velocity.x + impulse.x, -1100.0, 1100.0)
	velocity.y = clampf(velocity.y + impulse.y, -1100.0, 1100.0)
	if previous_y >= 0.0 and velocity.y < 0.0:
		_fall_apex_y = global_position.y
		_tracking_fall = true
	impulse_received.emit(impulse, source)

func _draw() -> void:
	if not show_body_in_eye and not debug_visible:
		return
	draw_rect(Rect2(-12, -20, 24, 40), Color.WHITE)
	draw_rect(Rect2(-12, -12, 24, 5), Color.BLACK)
