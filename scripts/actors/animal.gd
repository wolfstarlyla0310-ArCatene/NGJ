@tool
class_name Animal
extends CharacterBody2D
## 受重力影响的动物：附近出现 lv1 声场时向背离声源的方向水平移动，
## 移动时每 `wave_interval_pixels` 发出一个边长为 `move_wave_side_cells` 格的白色声场。
## 会爬上一格高的台阶、到平台边缘停住；被 lv2 声场命中会被震飞一段距离后掉落。

const TILE_SIZE := 16.0

@export var move_speed := 90.0
@export var gravity := 1500.0
@export var detection_margin := 16.0

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
var _step_cooldown := 0.0

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	add_to_group("animal")
	# 等调用方设好位置后再记录出生点。
	call_deferred("_capture_home")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	_prune_last_lv2()
	var lv2 := _new_overlapping_lv2()
	if lv2 != null:
		_last_lv2 = lv2
		_start_knockback(lv2)
	if _knockback_remaining > 0.0:
		_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
		velocity.y = minf(velocity.y + gravity * delta, 1000.0)
		_move_and_emit()
		return
	_walk(delta, _nearest_lv1_source())

func _walk(delta: float, source: SoundField) -> void:
	var dir := 0.0
	if source != null:
		dir = signf(global_position.x - source.global_position.x)
		if dir == 0.0:
			dir = 1.0

	# 用“正在移动的方向”做守边判定：即使没有声场、正在减速，也不能滑下平台。
	var facing := dir if absf(dir) > 0.0 else signf(velocity.x)
	if absf(facing) > 0.0 and is_on_floor():
		if _try_step_up(facing):
			if absf(dir) == 0.0:
				dir = facing
		elif not _has_floor_ahead(facing):
			if absf(dir) > 0.0:
				dir = 0.0
			else:
				velocity.x = 0.0

	if absf(dir) > 0.0:
		velocity.x = dir * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)
	velocity.y = minf(velocity.y + gravity * delta, 1000.0)
	_move_and_emit()

	var idle := source == null and is_on_floor() and absf(velocity.x) < 1.0
	if idle:
		_idle_wave_timer += delta
		if _idle_wave_timer >= idle_wave_interval:
			_idle_wave_timer = 0.0
			_spawn_wave(idle_wave_side_cells * TILE_SIZE)
	else:
		_idle_wave_timer = 0.0

func _move_and_emit() -> void:
	var pre_x := global_position.x
	move_and_slide()
	_wave_distance += absf(global_position.x - pre_x)
	while _wave_distance >= wave_interval_pixels:
		_wave_distance -= wave_interval_pixels
		_spawn_wave(move_wave_side_cells * TILE_SIZE)

## 贴着 1 格高的台阶时可以向上抬 16px 继续前进；2 格高的墙不会爬。
func _try_step_up(dir: float) -> bool:
	if _step_cooldown > 0.0 or not is_on_wall() or not is_on_floor():
		return false
	if test_move(global_transform, Vector2.UP * (TILE_SIZE + 2.0)):
		return false
	var raised := global_transform.translated(Vector2(0.0, -(TILE_SIZE + 1.0)))
	if test_move(raised, Vector2(dir * (TILE_SIZE * 0.75), 0.0)):
		return false
	global_position = raised.origin
	velocity.y = 0.0
	_step_cooldown = 0.1
	return true

## 前进方向的前缘下方 12px 是否有地板；没有就停在平台边缘。
func _has_floor_ahead(dir: float) -> bool:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(dir * (TILE_SIZE * 0.6), 4.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, 12.0))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()

func _nearest_lv1_source() -> SoundField:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return null
	var body_rect := Rect2(global_position - Vector2(8, 8), Vector2(16, 16)).grow(detection_margin)
	var best: SoundField = null
	var best_distance := INF
	for child in _sound_fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion() or child.level != 1:
			continue
		var field := child as SoundField
		if not field.get_rect().intersects(body_rect):
			continue
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

## R / 死亡重置时回到出生位置并清空所有临时状态。
func reset_home() -> void:
	if not _home_captured:
		_capture_home()
	global_position = _home_position
	velocity = Vector2.ZERO
	_wave_distance = 0.0
	_idle_wave_timer = 0.0
	_knockback_remaining = 0.0
	_step_cooldown = 0.0
	_last_lv2 = null

func _spawn_wave(side: float) -> void:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = wave_lifetime
	field.expand_duration = wave_expand_duration
	field.level = 0
	field.emitter = self
	field.safe_for_player = true
	_sound_fields.add_child(field)
	field.global_position = SoundField.snap_origin_to_grid(global_position, side)

func _draw() -> void:
	draw_rect(Rect2(-7, -6, 14, 12), Color.WHITE)
	draw_rect(Rect2(-4, -3, 2, 2), Color.BLACK)
	draw_rect(Rect2(2, -3, 2, 2), Color.BLACK)
