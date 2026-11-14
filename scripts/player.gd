class_name EchoPlayer
extends CharacterBody2D

signal wave_emitted(origin: Vector2, side_pixels: float, level: int, kind: String)

const TILE_SIZE: float = 16.0
const CONTACT_TOLERANCE_PIXELS: float = 0.5

@export var speed: float = 250.0
@export var acceleration: float = 1800.0
@export var jump_height_tiles: float = 6.0
@export var gravity: float = 1500.0
@export var terminal_fall_speed: float = 1000.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12
@export var walk_wave_interval_tiles: float = 2.0
## 走路声场边长（格）；当前 3 格 = 48 像素。
@export var walk_wave_side_cells: float = 3.0
## 跳跃/落地声场边长（格）；当前 5 格 = 80 像素。
@export var jump_wave_side_cells: float = 5.0

var controls_enabled: bool = false:
	set(value):
		controls_enabled = value
		if not value:
			_jump_remaining = 0.0
			_coyote_remaining = 0.0

var _coyote_remaining: float = 0.0
var _jump_remaining: float = 0.0
var _fall_apex_y: float = 0.0
var _walk_wave_distance: float = 0.0
var _was_moving_grounded: bool = false

func _ready() -> void:
	_fall_apex_y = global_position.y

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return
	var was_grounded := is_on_floor()
	_jump_remaining = maxf(0.0, _jump_remaining - delta)
	_coyote_remaining = coyote_time if was_grounded else maxf(0.0, _coyote_remaining - delta)
	if was_grounded and velocity.y >= 0.0:
		_fall_apex_y = global_position.y
	_fall_apex_y = minf(_fall_apex_y, global_position.y)
	if Input.is_action_just_pressed("jump"):
		_jump_remaining = jump_buffer

	var axis := Input.get_axis("move_left", "move_right")
	velocity.x = move_toward(velocity.x, axis * speed, acceleration * delta)
	velocity.y = minf(velocity.y + gravity * delta, terminal_fall_speed)
	if _jump_remaining > 0.0 and _coyote_remaining > 0.0:
		# Jump velocity is applied after this tick's gravity, so compensate one gravity step.
		var launch := _launch_speed(jump_height_tiles * TILE_SIZE, gravity) - gravity / Engine.physics_ticks_per_second
		velocity.y = -launch
		_jump_remaining = 0.0
		_coyote_remaining = 0.0

	var pre_x := global_position.x
	move_and_slide()
	_fall_apex_y = minf(_fall_apex_y, global_position.y)
	if not was_grounded and is_on_floor():
		_emit_landing_wave()
	_emit_step_waves(was_grounded, pre_x)

func _emit_landing_wave() -> void:
	var drop := maxf(0.0, global_position.y - _fall_apex_y)
	var tiles := floori((drop + CONTACT_TOLERANCE_PIXELS) / TILE_SIZE)
	_fall_apex_y = global_position.y
	if tiles < 1:
		return
	var level := 0
	if tiles >= 8:
		level = 2
	elif tiles >= 4:
		level = 1
	wave_emitted.emit(global_position, jump_wave_side_cells * TILE_SIZE, level, "landing")

func _emit_step_waves(was_grounded: bool, pre_x: float) -> void:
	var moved := absf(global_position.x - pre_x)
	if not was_grounded:
		_was_moving_grounded = false
		return
	var interval := maxf(1.0, walk_wave_interval_tiles * TILE_SIZE)
	var moving := absf(velocity.x) > 1.0
	# Emit one frame immediately when starting to walk, so continuous movement is always covered.
	if moved > 0.01 and moving and not _was_moving_grounded:
		_walk_wave_distance = maxf(_walk_wave_distance, interval)
	_was_moving_grounded = moving
	_walk_wave_distance += moved
	while _walk_wave_distance >= interval:
		_walk_wave_distance -= interval
		wave_emitted.emit(global_position, walk_wave_side_cells * TILE_SIZE, 0, "step")

func reset_to(point: Vector2) -> void:
	global_position = point
	velocity = Vector2.ZERO
	_coyote_remaining = 0.0
	_jump_remaining = 0.0
	_walk_wave_distance = 0.0
	_was_moving_grounded = false
	_fall_apex_y = point.y

func _launch_speed(height_pixels: float, g: float) -> float:
	if height_pixels <= 0.0:
		return 0.0
	# Semi-implicit Euler applies gravity before movement; compensate half a physics step.
	return sqrt(2.0 * g * height_pixels) + g / (2.0 * Engine.physics_ticks_per_second)
