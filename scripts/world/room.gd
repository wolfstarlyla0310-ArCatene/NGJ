@tool
class_name Room
extends Node2D
## 大地图里的一个房间：rect 同时决定相机取景范围、切关判定与 R 重置范围。
## 坐标约定：rect 是本节点坐标系矩形，get_rect() 返回世界坐标矩形；房间节点不要加缩放或旋转。

const CAMERA_ANCHOR_NAME := "CameraAnchor"
const GIZMO_COLOR := Color(0.35, 0.65, 1.0, 0.9)
const GIZMO_WIDTH := 1.0
const GIZMO_Z_INDEX := 100

@export var rect := Rect2(Vector2.ZERO, Vector2(1152, 648)):
	set(value):
		rect = value
		queue_redraw()

@export var room_name := ""

func _ready() -> void:
	z_as_relative = false
	z_index = GIZMO_Z_INDEX
	queue_redraw()

func get_rect() -> Rect2:
	return Rect2(to_global(rect.position), rect.size)

func contains_world_point(world_point: Vector2) -> bool:
	return BoundsDrag.in_rect(get_rect(), world_point)

func get_camera_target() -> Vector2:
	var anchor := get_node_or_null(CAMERA_ANCHOR_NAME) as Node2D
	if anchor != null:
		return anchor.global_position
	return get_rect().get_center()

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(rect, GIZMO_COLOR, false, GIZMO_WIDTH)
