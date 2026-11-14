@tool
class_name Animal
extends CharacterBody2D
## 蓝框每次触发后，向背离声源的方向前进至多 5 格；蓝框消失后仍继续。
## 移动时每 `wave_interval_pixels` 发出一个边长为 `move_wave_side_cells` 格的白色声场。
## 会爬上一格高的台阶、到平台边缘停住；被 lv2 声场命中会被震飞一段距离后掉落。

const TILE_SIZE := 16.0
# 留出碰撞余量，同时允许在恰好一格高的上层通道内落脚。
const STEP_CLEARANCE := 0.1
const STEP_PROBE := 2.0
const TURN_DURATION := 0.12

enum ClimbPhase { NONE, TURN_UP, RISE, TURN_FORWARD, MOVE_ONTO }

@export var move_speed := 90.0
@export var gravity := 1500.0
@export var detection_margin := 16.0
## 外层地形瓦片为 16px 一格；每次新蓝框触发后水平前进的距离。
@export_range(0.0, 32.0, 0.5) var flee_distance_cells := 5.0

@export_group("声场")
## 移动时发出的白色声场边长（格；1 格 = 16px）。当前 1 格 = 16px。
@export_range(0.25, 16.0, 0.25) var move_wave_side_cells := 1.0
@export var wave_interval_pixels := 16.0
## 动物声场持续时间（秒）；比玩家声场更久。
@export var wave_lifetime := 1.0
## 动物声场从中心扩散到目标边长的时间（秒）；比玩家声场更慢。
@export var wave_expand_duration := 0.5
## 静止时每隔这么久发一次声场（秒）。
@export var idle_wave_interval := 0.5
## 静止时发出的白色声场边长（格；1 格 = 16px）。当前 1.4 格 = 22.4px。
@export_range(0.25, 16.0, 0.25) var idle_wave_side_cells := 1.4

@export_group("受击")
## 被 lv2 声场命中时的水平击飞速度（像素/秒）。
@export var knockback_speed := 260.0
## 被 lv2 声场命中时的向上初速度（像素/秒）。
@export var knockback_up_speed := 200.0
## 击飞期间不受行走/守边控制的时间（秒）。
@export var knockback_duration := 0.35

var _sound_fields: Node2D = null
var _wave_distance := 0.0
var _idle_wave_timer := 0.0
var _home_position := Vector2.ZERO
var _home_captured := false
var _knockback_remaining := 0.0
var _last_lv2: SoundField = null
var _climb_phase := ClimbPhase.NONE
var _climb_top := Vector2.ZERO
var _climb_target := Vector2.ZERO
var _climb_angle := 0.0
var _turn_elapsed := 0.0
var _climb_can_land := false
var _walk_direction := 0.0
var _walk_remaining := 0.0
var _was_idle := false
var _alive := true
var _seen_lv1: Dictionary[int, WeakRef] = {}

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	add_to_group("animal")
	# 等调用方设好位置后再记录出生点。
	call_deferred("_capture_home")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _alive:
		return
	_prune_last_lv2()
	var lv2 := _new_overlapping_lv2()
	if lv2 != null:
		_last_lv2 = lv2
		_start_knockback(lv2)
	if _knockback_remaining > 0.0:
		_was_idle = false
		_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
		velocity.y = minf(velocity.y + gravity * delta, 1000.0)
		_move_and_emit()
		return
	if _climb_phase != ClimbPhase.NONE:
		_was_idle = false
		_climb(delta)
		return
	var source := _nearest_new_lv1_source()
	if source != null:
		_walk_direction = signf(global_position.x - source.global_position.x)
		if _walk_direction == 0.0:
			_walk_direction = 1.0
		_walk_remaining = flee_distance_cells * TILE_SIZE
	_walk(delta)

func _walk(delta: float) -> void:
	var dir := _walk_direction if _walk_remaining > 0.001 else 0.0

	# 用“正在移动的方向”做守边判定：即使没有声场、正在减速，也不能滑下平台。
	var facing := dir if absf(dir) > 0.0 else signf(velocity.x)
	if absf(facing) > 0.0 and is_on_floor():
		if _try_step_up(facing):
			_climb(delta)
			return
		elif not _has_floor_ahead(facing):
			dir = 0.0
			velocity.x = 0.0
			_walk_remaining = 0.0

	if absf(dir) > 0.0:
		velocity.x = dir * minf(move_speed, _walk_remaining / delta)
	else:
		velocity.x = 0.0
	velocity.y = minf(velocity.y + gravity * delta, 1000.0)
	var before_x := global_position.x
	_move_and_emit()
	_walk_remaining = maxf(0.0, _walk_remaining - absf(global_position.x - before_x))

	# 被蓝框驱赶但停在墙边/平台边缘时也会叫。
	var idle := is_on_floor() and absf(velocity.x) < 1.0
	if idle:
		# 停止移动的第一帧立刻叫一声，之后按 idle_wave_interval 重复。
		if not _was_idle:
			_idle_wave_timer = 0.0
			_spawn_wave(idle_wave_side_cells * TILE_SIZE)
		_idle_wave_timer += delta
		if _idle_wave_timer >= idle_wave_interval:
			_idle_wave_timer = 0.0
			_spawn_wave(idle_wave_side_cells * TILE_SIZE)
	else:
		_idle_wave_timer = 0.0
	_was_idle = idle

func _move_and_emit() -> void:
	var before := global_position
	move_and_slide()
	_emit_travel_waves(absf(global_position.x - before.x))

func _emit_travel_waves(distance: float) -> void:
	_wave_distance += distance
	var interval := maxf(1.0, wave_interval_pixels)
	while _wave_distance >= interval:
		_wave_distance -= interval
		_spawn_wave(move_wave_side_cells * TILE_SIZE)

## 先检查完整的一格台阶路径，再转身、贴侧面向上爬、转回并爬上台面。
func _try_step_up(dir: float) -> bool:
	if not is_on_floor():
		return false
	# 主动探测侧壁，避免守边射线进入台阶内部后先把动物拦住。
	var wall := KinematicCollision2D.new()
	if not test_move(global_transform, Vector2(dir * STEP_PROBE, 0.0), wall):
		return false
	if wall.get_normal().dot(Vector2(-dir, 0.0)) < 0.9:
		return false
	var rise := Vector2.UP * (TILE_SIZE + STEP_CLEARANCE)
	if test_move(global_transform, rise):
		return false
	var raised := global_transform.translated(rise)
	# 先让身体中心越过台阶侧面，保留下一阶的净空，支持连续一格宽的楼梯。
	var across := Vector2(dir * (TILE_SIZE * 0.75), 0.0)
	if _walk_remaining < absf(across.x):
		_walk_remaining = 0.0
		return false
	var landing := raised.translated(across)
	var support := KinematicCollision2D.new()
	# 高墙也先爬一格；到这个高度仍不能上台面，就松开侧壁掉回地面。
	_climb_can_land = not test_move(raised, across) \
		and test_move(landing, Vector2.DOWN * (STEP_CLEARANCE + 1.0), support) \
		and support.get_normal().dot(Vector2.UP) >= 0.9
	_climb_top = raised.origin
	_climb_target = landing.origin
	_climb_angle = -dir * PI * 0.5
	_turn_elapsed = 0.0
	_climb_phase = ClimbPhase.TURN_UP
	_idle_wave_timer = 0.0
	velocity = Vector2.ZERO
	return true

func _climb(delta: float) -> void:
	velocity = Vector2.ZERO
	if _climb_phase == ClimbPhase.TURN_UP or _climb_phase == ClimbPhase.TURN_FORWARD:
		_turn_elapsed = minf(_turn_elapsed + delta, TURN_DURATION)
		var t := _turn_elapsed / TURN_DURATION
		if _sprite != null:
			_sprite.rotation = lerpf(0.0, _climb_angle, t) if _climb_phase == ClimbPhase.TURN_UP \
				else lerpf(_climb_angle, 0.0, t)
		if _turn_elapsed >= TURN_DURATION:
			if _climb_phase == ClimbPhase.TURN_FORWARD and not _climb_can_land:
				_walk_remaining = 0.0
				_clear_climb()
				return
			_climb_phase = ClimbPhase.RISE if _climb_phase == ClimbPhase.TURN_UP else ClimbPhase.MOVE_ONTO
			_turn_elapsed = 0.0
		return

	var target := _climb_top if _climb_phase == ClimbPhase.RISE else _climb_target
	var motion := global_position.direction_to(target) * minf(move_speed * delta, global_position.distance_to(target))
	var before := global_position
	var collision := move_and_collide(motion)
	_walk_remaining = maxf(0.0, _walk_remaining - absf(global_position.x - before.x))
	_emit_travel_waves(global_position.distance_to(before))
	# 爬到一半路径被新碰撞挡住时停止攀爬，让重力接管。
	if collision != null:
		_walk_remaining = 0.0
		_clear_climb()
		return
	if global_position.distance_to(target) < 0.01:
		if _climb_phase == ClimbPhase.RISE:
			_climb_phase = ClimbPhase.TURN_FORWARD
		else:
			_clear_climb()
			# 刷新落地状态，下一帧继续正常行走和守边。
			velocity.y = gravity * delta
			_move_and_emit()

func _clear_climb() -> void:
	_climb_phase = ClimbPhase.NONE
	_turn_elapsed = 0.0
	if _sprite != null:
		_sprite.rotation = 0.0

## 前进方向的前缘下方约一格内是否有地板；一格深的沟会走过去，更深则停在边缘。
func _has_floor_ahead(dir: float) -> bool:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(dir * (TILE_SIZE * 0.6), TILE_SIZE * 0.5)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, TILE_SIZE + 2.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _nearest_new_lv1_source() -> SoundField:
	for id: int in _seen_lv1.keys():
		if _seen_lv1[id].get_ref() == null:
			_seen_lv1.erase(id)
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return null
	var body_rect := Rect2(global_position - Vector2(8, 8), Vector2(16, 16)).grow(detection_margin)
	var best: SoundField = null
	var best_distance := INF
	for child in _sound_fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion() or child.level != 1:
			continue
		var field := child as SoundField
		if field.emitter == self:
			continue
		if not field.get_rect().intersects(body_rect):
			continue
		var id := field.get_instance_id()
		if _seen_lv1.has(id):
			continue
		_seen_lv1[id] = weakref(field)
		var distance := global_position.distance_squared_to(field.global_position)
		if distance < best_distance:
			best_distance = distance
			best = field
	return best

func _prune_last_lv2() -> void:
	if _last_lv2 != null and (not is_instance_valid(_last_lv2) or _last_lv2.is_queued_for_deletion()):
		_last_lv2 = null

## 与身体相交、且尚未震飞过的新 lv2 声场。
func _new_overlapping_lv2() -> SoundField:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return null
	var body_rect := Rect2(global_position - Vector2(8, 8), Vector2(16, 16))
	for child in _sound_fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion():
			continue
		var field := child as SoundField
		if field.level != 2 or field == _last_lv2:
			continue
		if field.get_rect().intersects(body_rect):
			return field
	return null

func _start_knockback(field: SoundField) -> void:
	_clear_climb()
	_walk_remaining = 0.0
	_walk_direction = 0.0
	var dir := signf(global_position.x - field.global_position.x)
	if dir == 0.0:
		dir = 1.0
	velocity = Vector2(dir * knockback_speed, -knockback_up_speed)
	_knockback_remaining = knockback_duration

func _capture_home() -> void:
	if _home_captured:
		return
	_home_position = global_position
	_home_captured = true

func home_position() -> Vector2:
	return _home_position

func is_alive() -> bool:
	return _alive

## 被怪/门吃掉：隐藏并停止处理，但保留节点，R 时由 reset_home 复活。
func consume() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	_clear_climb()
	_walk_remaining = 0.0
	visible = false
	set_physics_process(false)

## 玩家进入动物当前所在房间时，把刷新点改到当前位置（Room11 → Room12 场景）。
func rebase_home() -> void:
	_home_position = global_position
	_home_captured = true

## R / 死亡重置时回到出生位置并清空所有临时状态。
func reset_home() -> void:
	if not _home_captured:
		_capture_home()
	global_position = _home_position
	velocity = Vector2.ZERO
	_wave_distance = 0.0
	_idle_wave_timer = 0.0
	_knockback_remaining = 0.0
	_clear_climb()
	_last_lv2 = null
	_walk_direction = 0.0
	_walk_remaining = 0.0
	_was_idle = false
	_seen_lv1.clear()
	_alive = true
	set_physics_process(true)
	visible = process_mode != Node.PROCESS_MODE_DISABLED

func _spawn_wave(side: float) -> void:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = wave_lifetime
	field.expand_duration = wave_expand_duration
	field.level = 1
	field.color = SoundField.color_for_level(1)
	field.emitter = self
	field.safe_for_player = true
	_sound_fields.add_child(field)
	field.global_position = SoundField.snap_origin_to_grid(global_position, side)

func _draw() -> void:
	if _sprite != null and _sprite.texture != null:
		return
	draw_rect(Rect2(-7, -6, 14, 12), Color.WHITE)
	draw_rect(Rect2(-4, -3, 2, 2), Color.BLACK)
	draw_rect(Rect2(2, -3, 2, 2), Color.BLACK)
