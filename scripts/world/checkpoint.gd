@tool
class_name Checkpoint
extends Area2D
## 存档点：记录重生坐标，并维持一个持续存在的白色安全声场。
## 未激活显示半透明闭旗；激活后换成开旗。

signal touched(checkpoint: Checkpoint)

const TILE_SIZE := 16.0
const FIELD_EXPAND_DURATION := 0.5
const FLAG_CLOSE := preload("res://assets/flag_close.png")
const FLAG_OPEN := preload("res://assets/flag_open.png")
const IDLE_ALPHA := 0.8
## 激活存档点时播放一次星星收集品音效。
const ACTIVATE_STREAM: AudioStream = preload("res://assets/sound/PickUP/pickup.mp3")

@export var respawn_offset := Vector2.ZERO

@export_group("声场")
## 是否启用安全声场（测试/调参可关闭）。
@export var fields_enabled := true
## 声场边长（格）；5 格 = 80px。
@export var field_side_cells := 5.0
## 持续声场的视觉渐隐渐显（只改透明度，不改变安全/隐藏噪音等实际作用）。
@export var field_fade_enabled := true
## 一次渐隐渐显周期（秒）。
@export var field_fade_seconds := 1.2
## 最暗时的视觉不透明度。
@export_range(0.05, 1.0, 0.05) var field_min_alpha := 0.35

var _active := false
## 玩家是否接触/绑定过这个存档点；一旦激活就永久保持声场。
var _field_activated := false
var _sound_fields: Node2D = null
var _current_field: SoundField = null
var _field_fade_elapsed := 0.0

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	_refresh_visual()

## 玩家激活后，地图加载/房间刷新/复活时确保安全声场存在（幂等）。
func restart_wave() -> void:
	if Engine.is_editor_hint() or not _field_activated:
		return
	_ensure_field()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not fields_enabled:
		_clear_field()
		return
	if _field_activated:
		_ensure_field()
	_update_field_visual(delta)

## 只改声场节点的 modulate.a（渲染透明度），安全范围/隐藏噪音等判定完全不变。
func _update_field_visual(delta: float) -> void:
	if not is_instance_valid(_current_field) or _current_field.is_queued_for_deletion():
		_field_fade_elapsed = 0.0
		return
	if not field_fade_enabled:
		_current_field.modulate.a = 1.0
		return
	_field_fade_elapsed += delta
	var phase := sin(_field_fade_elapsed * TAU / maxf(field_fade_seconds, 0.001))
	_current_field.modulate.a = lerpf(field_min_alpha, 1.0, 0.5 + 0.5 * phase)

func _ensure_field() -> void:
	if Engine.is_editor_hint() or not _field_activated:
		return
	if not fields_enabled:
		_clear_field()
		return
	if is_instance_valid(_current_field) and not _current_field.is_queued_for_deletion():
		return
	_current_field = null
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	if _sound_fields == null:
		return
	var field := SoundField.new()
	field.side_length = field_side_cells * TILE_SIZE
	field.lifetime = INF
	field.expand_duration = FIELD_EXPAND_DURATION
	field.color = Color.WHITE
	field.lethal = false
	field.safe_for_player = true
	field.level = 0
	field.emitter = null  # 门会跳过 emitter 为空的白色声场
	field.persistent = true
	_current_field = field
	_sound_fields.add_child(field)
	field.global_position = SoundField.snap_origin_to_grid(global_position, field.side_length)
	# 从最暗开始，随后由 _update_field_visual() 渐显。
	_field_fade_elapsed = 0.0
	field.modulate.a = field_min_alpha if field_fade_enabled else 1.0

func _clear_field() -> void:
	if is_instance_valid(_current_field) and not _current_field.is_queued_for_deletion():
		_current_field.queue_free()
	_current_field = null
	_field_fade_elapsed = 0.0

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer:
		touched.emit(self)

func set_active(value: bool) -> void:
	if value == _active:
		return
	var first_activation := value and not _field_activated
	_active = value
	_refresh_visual()
	if value:
		# 玩家激活：发出一次安全场，之后一直保持（换绑/离开房间都不删除）。
		_field_activated = true
		if first_activation:
			_play_activate_sound()
		_ensure_field()

## 只在 set_active 的 false→true 转换时调用，restart_wave/重生不会重播。
func _play_activate_sound() -> void:
	if Engine.is_editor_hint():
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = ACTIVATE_STREAM
	audio.bus = &"Pickup"
	get_tree().root.add_child(audio)
	audio.finished.connect(audio.queue_free, CONNECT_ONE_SHOT)
	audio.play()

func is_active() -> bool:
	return _active

func respawn_position() -> Vector2:
	return global_position + respawn_offset

func _refresh_visual() -> void:
	if _sprite == null:
		return
	if _active:
		_sprite.texture = FLAG_OPEN
		_sprite.modulate = Color.WHITE
	else:
		_sprite.texture = FLAG_CLOSE
		_sprite.modulate = Color(1.0, 1.0, 1.0, IDLE_ALPHA)
