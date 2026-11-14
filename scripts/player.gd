
class_name EchoPlayer
extends CharacterBody2D

signal wave_emitted(origin: Vector2, side_pixels: float, level: int, kind: String)

const TILE_SIZE: float = 16.0
const CONTACT_TOLERANCE_PIXELS: float = 0.5
const CEILING_PROBE_PIXELS: float = 3.0


# ==============================
# 玩家移动参数
# ==============================

@export var speed: float = 250.0
@export var acceleration: float = 1800.0
@export var jump_height_tiles: float = 6.0
@export var gravity: float = 1500.0
@export var terminal_fall_speed: float = 1000.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.12

@export var walk_wave_interval_tiles: float = 2.0

## 走路 / lv0 落地声场边长（格）。
@export var walk_wave_side_cells: float = 3.0

## lv1 落地声场边长（格）。
@export var landing_lv1_side_cells: float = 6.0

## lv2 落地声场边长（格）。
@export var landing_lv2_side_cells: float = 10.0

## 到达跳跃最高点后额外滞空的时间。
@export var apex_hover_time: float = 0.0


# ==============================
# 音效节点
# 音频文件在 Inspector 的 Stream 中挂载
# ==============================

@onready var move_audio: AudioStreamPlayer = get_node_or_null("MoveSound") as AudioStreamPlayer
@onready var die_audio: AudioStreamPlayer = get_node_or_null("DieSound") as AudioStreamPlayer


# ==============================
# 玩家状态
# ==============================

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

var _jumping: bool = false
var _hover_used: bool = false
var _hover_remaining: float = 0.0
var _jump_start_against_ceiling: bool = false


# ==============================
# 初始化
# ==============================

func _ready() -> void:
	_fall_apex_y = global_position.y
	_jump_start_against_ceiling = false

	if move_audio == null:
		push_warning("Player 缺少 MoveSound 音效节点")
	elif move_audio.stream == null:
		push_warning("MoveSound 尚未挂载音频文件")

	if die_audio == null:
		push_warning("Player 缺少 DieSound 音效节点")
	elif die_audio.stream == null:
		push_warning("DieSound 尚未挂载音频文件")


# ==============================
# 玩家移动与跳跃
# ==============================

func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return

	var was_grounded: bool = is_on_floor()

	if was_grounded:
		_jumping = false
		_hover_used = false
		_hover_remaining = 0.0

	_jump_remaining = maxf(
		0.0,
		_jump_remaining - delta
	)

	_coyote_remaining = (
		coyote_time if was_grounded
		else maxf(0.0, _coyote_remaining - delta)
	)

	if was_grounded and velocity.y >= 0.0:
		_fall_apex_y = global_position.y

	_fall_apex_y = minf(
		_fall_apex_y,
		global_position.y
	)

	if Input.is_action_just_pressed("jump"):
		_jump_remaining = jump_buffer

	var axis: float = Input.get_axis(
		"move_left",
		"move_right"
	)

	velocity.x = move_toward(
		velocity.x,
		axis * speed,
		acceleration * delta
	)

	velocity.y = minf(
		velocity.y + gravity * delta,
		terminal_fall_speed
	)

	# ==============================
	# 跳跃
	# ==============================

	if _jump_remaining > 0.0 and _coyote_remaining > 0.0:

		var launch: float = (
			_launch_speed(
				jump_height_tiles * TILE_SIZE,
				gravity
			)
			- gravity / Engine.physics_ticks_per_second
		)

		velocity.y = -launch

		_jump_remaining = 0.0
		_coyote_remaining = 0.0

		_jumping = true
		_hover_used = false
		_hover_remaining = 0.0

		_jump_start_against_ceiling = test_move(
			global_transform,
			Vector2.UP * CEILING_PROBE_PIXELS
		)

		# 起跳产生 lv0 声场
		wave_emitted.emit(
			global_position,
			walk_wave_side_cells * TILE_SIZE,
			0,
			"jump"
		)

	# ==============================
	# 跳跃最高点悬停
	# ==============================

	if _jumping and not _hover_used and velocity.y >= 0.0:
		_hover_used = true
		_hover_remaining = apex_hover_time

	if _hover_remaining > 0.0:
		_hover_remaining = maxf(
			0.0,
			_hover_remaining - delta
		)
		velocity.y = 0.0

	var pre_velocity_y: float = velocity.y
	var pre_x: float = global_position.x

	move_and_slide()

	# ==============================
	# 顶头声波
	# ==============================

	if pre_velocity_y < 0.0 and is_on_ceiling():
		_emit_ceiling_wave()

	_fall_apex_y = minf(
		_fall_apex_y,
		global_position.y
	)

	# ==============================
	# 落地声波
	# ==============================

	if not was_grounded and is_on_floor():
		_emit_landing_wave()

	# ==============================
	# 走路声波与音效
	# ==============================

	_emit_step_waves(
		was_grounded,
		pre_x,
		axis,
		delta
	)


# ==============================
# 落地声波
# ==============================

func _emit_landing_wave() -> void:

	var drop: float = maxf(
		0.0,
		global_position.y - _fall_apex_y
	)

	var tiles: int = floori(
		(drop + CONTACT_TOLERANCE_PIXELS) / TILE_SIZE
	)

	_fall_apex_y = global_position.y

	if tiles < 1:
		return

	var level: int = 0

	if tiles > 6:
		level = 2
	elif tiles > 2:
		level = 1

	var side_cells: float = walk_wave_side_cells

	if level == 1:
		side_cells = landing_lv1_side_cells
	elif level == 2:
		side_cells = landing_lv2_side_cells

	wave_emitted.emit(
		global_position,
		side_cells * TILE_SIZE,
		level,
		"landing"
	)


# ==============================
# 顶头声波
# ==============================

func _emit_ceiling_wave() -> void:

	if _jump_start_against_ceiling:
		wave_emitted.emit(
			global_position,
			landing_lv2_side_cells * TILE_SIZE,
			2,
			"ceiling"
		)
	else:
		wave_emitted.emit(
			global_position,
			landing_lv1_side_cells * TILE_SIZE,
			1,
			"ceiling"
		)


# ==============================
# 走路声波与走路音效
# ==============================

func _emit_step_waves(
	was_grounded: bool,
	pre_x: float,
	axis: float,
	delta: float
) -> void:

	var moved: float = absf(
		global_position.x - pre_x
	)

	if not was_grounded:
		_was_moving_grounded = false
		return

	var wall_normal: Vector2 = get_wall_normal()

	var pushing: bool = (
		absf(axis) > 0.1
		and is_on_wall()
		and absf(wall_normal.x) > 0.7
		and signf(axis) == -signf(wall_normal.x)
	)

	if pushing:
		moved = maxf(
			moved,
			absf(axis) * speed * delta
		)

	var interval: float = maxf(
		1.0,
		walk_wave_interval_tiles * TILE_SIZE
	)

	var moving: bool = (
		absf(velocity.x) > 1.0
		or pushing
	)

	# 开始移动时立即产生声波
	if moved > 0.01 and moving and not _was_moving_grounded:
		_walk_wave_distance = maxf(
			_walk_wave_distance,
			interval
		)

	_was_moving_grounded = moving
	_walk_wave_distance += moved

	while _walk_wave_distance >= interval:
		_walk_wave_distance -= interval

		wave_emitted.emit(
			global_position,
			walk_wave_side_cells * TILE_SIZE,
			0,
			"step"
		)

		_play_move_sound()


# ==============================
# 走路音效播放
# ==============================

func _play_move_sound() -> void:
	if move_audio == null or move_audio.stream == null:
		return

	move_audio.play()


# ==============================
# 死亡音效
# ==============================

func play_death_sound() -> void:

	if die_audio == null:
		return

	if die_audio.stream == null:
		return

	# 使用 Inspector 中 DieSound 的配置
	# 创建一次性播放器，确保 Player 删除后音效仍可播放
	var death_player := AudioStreamPlayer.new()

	death_player.stream = die_audio.stream
	death_player.volume_db = die_audio.volume_db
	death_player.pitch_scale = die_audio.pitch_scale
	death_player.bus = die_audio.bus
	death_player.mix_target = die_audio.mix_target

	get_tree().root.add_child(death_player)

	death_player.finished.connect(
		death_player.queue_free,
		CONNECT_ONE_SHOT
	)

	death_player.play()


# ==============================
# 玩家重置
# ==============================

func reset_to(point: Vector2) -> void:

	# 停止仍在播放的走路音效
	if move_audio != null:
		move_audio.stop()

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


# ==============================
# 跳跃速度计算
# ==============================

func _launch_speed(
	height_pixels: float,
	g: float
) -> float:

	if height_pixels <= 0.0:
		return 0.0

	return (
		sqrt(2.0 * g * height_pixels)
		+ g / (
			2.0 * Engine.physics_ticks_per_second
		)
	)
