class_name DoorButton
extends Area2D
## 门按钮：只被蓝色（lv1）声场覆盖时视为「按下」；lv0 白色 / lv2 黄色都不触发。
## 两种模式：ONE_SHOT 一次性（首次触发后永久锁定）；REBOUND 回弹（声场消失即松开，
## 除非 PuzzleDoorManager 判定同组 ≥2 个按钮同时满足而整组锁死）。
## 与门单向关系：按钮只管自己的状态，door_cells 由管理器解析，不引用门节点。

signal pressed_changed(button: DoorButton)

enum Mode {
	ONE_SHOT,
	REBOUND,
}

## 按钮模式；两个按钮场景各自预置。
@export var mode: Mode = Mode.REBOUND
## 本按钮控制的门：填门范围内任意一格（填一格即代表整扇门）。
@export var door_cells: Array[Vector2i] = []
## 锁定后 R / 死亡重置也不清除（ButtonOnce4 等永久按钮）。
@export var keep_latched_on_reset := false

const SPRITE_NAME := "Sprite2D"
const TRIGGER_SIZE := Vector2(16.0, 16.0)

var _sound_fields: Node2D = null
var _held := false
var _latched := false

@onready var _sprite: Sprite2D = get_node_or_null(SPRITE_NAME) as Sprite2D

func _ready() -> void:
	add_to_group("door_button")
	_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	if _sprite != null:
		_sprite.frame_coords = atlas_coords_for(mode, is_pressed())

func _physics_process(_delta: float) -> void:
	var held := _is_triggering_field_on_me()
	if held == _held:
		return
	_held = held
	# 一次性按钮：首次被声场覆盖就锁死，之后不再回弹。
	if mode == Mode.ONE_SHOT and held:
		_latched = true
	_refresh_visual()
	pressed_changed.emit(self)

func is_held() -> bool:
	return _held

func is_latched() -> bool:
	return _latched

func is_pressed() -> bool:
	return _held or _latched

## 把按钮锁死（同组 ≥2 个回弹按钮同时满足时由 PuzzleDoorManager 调用）；幂等。
func latch() -> void:
	if _latched:
		return
	_latched = true
	_refresh_visual()
	pressed_changed.emit(self)

## 清回未触发态（R / 死亡重置房间时由 PuzzleDoorManager 调用）。
func reset_state() -> void:
	if keep_latched_on_reset and _latched:
		_held = _is_triggering_field_on_me()
		_refresh_visual()
		pressed_changed.emit(self)
		return
	_latched = false
	_held = _is_triggering_field_on_me()
	_refresh_visual()
	pressed_changed.emit(self)

## 贴图帧：点亮统一用上面第一张蓝色图 (1,0)；熄灭仍按行区分一次性/回弹。
static func atlas_coords_for(button_mode: int, pressed: bool) -> Vector2i:
	if pressed:
		return Vector2i(1, 0)
	return Vector2i(0, 0 if button_mode == Mode.ONE_SHOT else 1)

func _refresh_visual() -> void:
	if _sprite != null:
		_sprite.frame_coords = atlas_coords_for(mode, is_pressed())

## 只有蓝色（lv1）声场触发；动物声场现在也是蓝色。
func _is_triggering_field_on_me() -> bool:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	if _sound_fields == null:
		return false
	var trigger_rect := Rect2(global_position - TRIGGER_SIZE * 0.5, TRIGGER_SIZE)
	for child in _sound_fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion():
			continue
		var field := child as SoundField
		if field.level == 1 and field.get_rect().intersects(trigger_rect):
			return true
	return false
