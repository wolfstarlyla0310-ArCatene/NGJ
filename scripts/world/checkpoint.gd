@tool
class_name Checkpoint
extends Area2D
## 存档点：记录重生坐标，并每 `field_interval` 秒发出一个白色安全声场。
## 进房时由 WorldMap 自动绑定，碰到时也会更新。

signal touched(checkpoint: Checkpoint)

const TILE_SIZE := 16.0
const FIELD_EXPAND_DURATION := 0.5

@export var respawn_offset := Vector2.ZERO
@export var idle_color := Color(0.45, 0.5, 0.55, 0.9)
@export var active_color := Color(1.0, 1.0, 1.0, 1.0)

@export_group("声场")
## 是否周期性发射声场（测试/调参可关闭）。
@export var fields_enabled := true
## 声场边长（格）；5 格 = 80px。
@export var field_side_cells := 5.0
## 发射间隔（秒）；与动物静止声波一致，每秒一次。
@export var field_interval := 1.0
## 单个声场寿命（秒）；持续到下一次发射，保持安全区域连续生效。
@export var field_lifetime := 1.0

var _active := false
var _emit_elapsed := 0.0
var _sound_fields: Node2D = null
var _current_field: SoundField = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_emit_elapsed = 0.0
	queue_redraw()

## 地图加载、房间刷新或复活时同步发出第一道安全声波，并重新计算周期。
func restart_wave() -> void:
	_emit_elapsed = 0.0
	if Engine.is_editor_hint() or not fields_enabled:
		return
	_spawn_field()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not fields_enabled:
		_emit_elapsed = 0.0
		return
	# 独立场景或外部清场后也立即恢复，不能等到旧计时器走完。
	if not is_instance_valid(_current_field) or _current_field.is_queued_for_deletion():
		restart_wave()
		return
	_emit_elapsed += delta
	if _emit_elapsed < field_interval:
		return
	_emit_elapsed = fmod(_emit_elapsed, maxf(field_interval, 0.001))
	_spawn_field()

func _spawn_field() -> void:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	if _sound_fields == null:
		return
	# 新一轮替换上一轮，避免计时边界或参数热更新时出现多层方框。
	if is_instance_valid(_current_field) and not _current_field.is_queued_for_deletion():
		_current_field.queue_free()
	var field := SoundField.new()
	field.side_length = field_side_cells * TILE_SIZE
	field.lifetime = field_lifetime
	field.expand_duration = FIELD_EXPAND_DURATION
	field.color = Color.WHITE
	field.lethal = false
	field.safe_for_player = true
	field.level = 0
	field.emitter = null  # 门会跳过 emitter 为空的白色声场
	_current_field = field
	_sound_fields.add_child(field)
	field.global_position = SoundField.snap_origin_to_grid(global_position, field.side_length)

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer:
		touched.emit(self)

func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	queue_redraw()

func is_active() -> bool:
	return _active

func respawn_position() -> Vector2:
	return global_position + respawn_offset

func _draw() -> void:
	var color := active_color if _active else idle_color
	draw_rect(Rect2(-8, -8, 16, 16), color, false, 2.0)
	draw_rect(Rect2(-3, -3, 6, 6), color, true)
