class_name SoundField
extends Node2D
## 声场：方形扩散波的视觉效果。发出后 0.1 秒内从中心扩散到目标边长，
## 之后保持满框，并在 0.5 秒生命周期内淡出。
## 判定（玻璃/噪音/安全）仍按目标尺寸 `side_length` 立即生效，不随视觉扩散。

@export var side_length: float = 96.0
@export var lifetime: float = 0.5
@export var line_width: float = 2.0
## 从中心扩到目标边长所需时间（秒）。
@export var expand_duration: float = 0.1

var age: float = 0.0
## 当前可视边长；只影响绘制，不影响 contains_point / 世界判定。
var current_side: float = 0.0

func _physics_process(delta: float) -> void:
	age += delta
	var t := clampf(age / maxf(expand_duration, 0.001), 0.0, 1.0)
	# ease-out：起步快、收尾缓
	current_side = side_length * (1.0 - pow(1.0 - t, 3.0))
	if age >= lifetime:
		queue_free()
	else:
		queue_redraw()

func contains_point(world_point: Vector2) -> bool:
	var half := side_length * 0.5
	return (
		world_point.x >= global_position.x - half and world_point.x <= global_position.x + half
		and world_point.y >= global_position.y - half and world_point.y <= global_position.y + half
	)

func _draw() -> void:
	var alpha := clampf(1.0 - age / lifetime, 0.0, 1.0)
	var half := current_side * 0.5
	draw_rect(Rect2(-half, -half, current_side, current_side), Color(1, 1, 1, alpha), false, line_width, true)
