class_name EchoPlayer
extends CharacterBody2D

signal wave_emitted(origin: Vector2, side_pixels: float, level: int, kind: String)

const TILE_SIZE: float = 16.0
const CONTACT_TOLERANCE_PIXELS: float = 0.5
## 起跳时向上探测“头顶净空”的距离：一格高走廊头顶约 2px，视为没有空间。
const CEILING_PROBE_PIXELS: float = 3.0

@export var speed: float = 250.0
@export var acceleration: float = 1800.0
@export var jump_height_tiles: float = 6.0
@export var gravity: float = 1500.0
@export var terminal_fall_speed: float = 1000.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12
@export var walk_wave_interval_tiles: float = 2.0
## 走路 / lv0 落地声场边长（格）；当前 3 格 = 48 像素。
@export var walk_wave_side_cells: float = 3.0
## lv1 落地声场边长（格）；2 < 落差 ≤ 6 格，当前 5 格 = 80 像素。
@export var landing_lv1_side_cells: float = 6.0
## lv2 落地声场边长（格）；落差 > 6 格，当前 7 格 = 112 像素。
@export var landing_lv2_side_cells: float = 10.0
## 到达跳跃最高点后额外滞空的时间（秒）。
@export var apex_hover_time := 0.0


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
var _jumping := false
var _hover_used := false
var _hover_remaining := 0.0
var _jump_start_against_ceiling := false

func _ready() -> void:
	_fall_apex_y = global_position.y
	_jump_start_against_ceiling = false

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return
	var was_grounded := is_on_floor()
	if was_grounded:
		_jumping = false
		_hover_used = false
		_hover_remaining = 0.0
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
		_jumping = true
		_hover_used = false
		_hover_remaining = 0.0
		# 起跳瞬间头顶是否已经贴着天花板（没有净空）。
		_jump_start_against_ceiling = test_move(global_transform, Vector2.UP * CEILING_PROBE_PIXELS)
		# 起跳也发出一次 lv0 声场（与走路同尺寸）。
		wave_emitted.emit(global_position, walk_wave_side_cells * TILE_SIZE, 0, "jump")

	# 到达跳跃最高点时悬停 `apex_hover_time` 秒，再恢复原来的下落速度。
	if _jumping and not _hover_used and velocity.y >= 0.0:
		_hover_used = true
		_hover_remaining = apex_hover_time
	if _hover_remaining > 0.0:
		_hover_remaining = maxf(0.0, _hover_remaining - delta)
		velocity.y = 0.0

	var pre_velocity_y := velocity.y
	var pre_x := global_position.x
	move_and_slide()
	# 上升过程中顶到天花板：发一次与小跳 lv1 落地波一致的蓝色声场。
	if pre_velocity_y < 0.0 and is_on_ceiling():
		_emit_ceiling_wave()
	_fall_apex_y = minf(_fall_apex_y, global_position.y)
	if not was_grounded and is_on_floor():
		_emit_landing_wave()
	_emit_step_waves(was_grounded, pre_x, axis, delta)

func _emit_landing_wave() -> void:
	var drop := maxf(0.0, global_position.y - _fall_apex_y)
	var tiles := floori((drop + CONTACT_TOLERANCE_PIXELS) / TILE_SIZE)
	_fall_apex_y = global_position.y
	if tiles < 1:
		return
	var level := 0
	if tiles > 6:
		level = 2
	elif tiles > 2:
		level = 1
	var side_cells := walk_wave_side_cells
	if level == 1:
		side_cells = landing_lv1_side_cells
	elif level == 2:
		side_cells = landing_lv2_side_cells
	wave_emitted.emit(global_position, side_cells * TILE_SIZE, level, "landing")

## 跳跃顶到天花板：只有起跳瞬间头顶没有净空才发 lv2，否则与小跳 lv1 落地波一致。
func _emit_ceiling_wave() -> void:
	if _jump_start_against_ceiling:
		wave_emitted.emit(global_position, landing_lv2_side_cells * TILE_SIZE, 2, "ceiling")
	else:
		wave_emitted.emit(global_position, landing_lv1_side_cells * TILE_SIZE, 1, "ceiling")

func _emit_step_waves(was_grounded: bool, pre_x: float, axis: float, delta: float) -> void:
	var moved := absf(global_position.x - pre_x)
	if not was_grounded:
		_was_moving_grounded = false
		return
	# 贴着墙按方向键时按“预期前进距离”累计，节奏与走路一致。
	var wall_normal := get_wall_normal()
	var pushing := absf(axis) > 0.1 and is_on_wall() \
		and absf(wall_normal.x) > 0.7 \
		and signf(axis) == -signf(wall_normal.x)
	if pushing:
		moved = maxf(moved, absf(axis) * speed * delta)
	var interval := maxf(1.0, walk_wave_interval_tiles * TILE_SIZE)
	var moving := absf(velocity.x) > 1.0 or pushing
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
	_jumping = false
	_hover_used = false
	_hover_remaining = 0.0
	_fall_apex_y = point.y
	_jump_start_against_ceiling = false

func _launch_speed(height_pixels: float, g: float) -> float:
	if height_pixels <= 0.0:
		return 0.0
	# Semi-implicit Euler applies gravity before movement; compensate half a physics step.
	return sqrt(2.0 * g * height_pixels) + g / (2.0 * Engine.physics_ticks_per_second)
