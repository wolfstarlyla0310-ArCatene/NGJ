@tool
class_name Checkpoint
extends Area2D
## 存档点：只记录一个重生坐标。进房时由 WorldMap 自动绑定，碰到时也会更新。

signal touched(checkpoint: Checkpoint)

@export var respawn_offset := Vector2.ZERO
@export var idle_color := Color(0.45, 0.5, 0.55, 0.9)
@export var active_color := Color(1.0, 1.0, 1.0, 1.0)

var _active := false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)
	queue_redraw()

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
