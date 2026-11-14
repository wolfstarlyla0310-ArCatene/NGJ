class_name SoundField
extends Node2D
## 声场：方形扩散波的视觉效果。发出后 `expand_duration` 秒内从中心扩散到目标边长，
## 之后保持满框，并在 `lifetime` 秒生命周期内淡出。
## `lifetime = INF` 表示常驻到重置（lv2 玩家落地波）。
## 判定（玻璃/噪音/安全）仍按目标尺寸 `side_length` 立即生效，不随视觉扩散。

const TILE_SIZE := 16.0

@export var side_length: float = 96.0
@export var lifetime: float = 0.5
@export var line_width: float = 2.0
## 从中心扩到目标边长所需时间（秒）。
@export var expand_duration: float = 0.2
## 线框颜色；玩家声场白色，刺/死亡声场红色。
@export var color := Color(1.0, 1.0, 1.0, 1.0)
## 接触是否杀死玩家。
@export var lethal := false
## 是否提供噪音免疫并隐藏噪音格。玩家声场 true，刺/死亡声场 false。
@export var safe_for_player := true
## 声场等级（0/1/2）；动物只响应 level == 1。
@export var level := 0
## 持久声场（门脉冲）：世界重置时不清理。
@export var persistent := false
## 白声场的主人（玩家 / 动物）；门的红色脉冲用它在接触白声场时吃掉主人。
var emitter: Node2D = null

var age: float = 0.0
## 当前可视边长；只影响绘制，不影响 contains_point / 世界判定。
var current_side: float = 0.0

## 玩家声场按等级取色：lv0 白色、lv1 蓝色、lv2 黄色。
static func color_for_level(field_level: int) -> Color:
	match field_level:
		1:
			return Color(0.3, 0.65, 1.0, 1.0)
		2:
			return Color(1.0, 0.9, 0.2, 1.0)
		_:
			return Color.WHITE

## 把以 `origin` 为中心、边长为 `side` 的方形声场吸附到 16px 网格：
## 将声场左上角取整到最近的格线，从而覆盖整格（副作用：中心最多偏移 8px）。
static func snap_origin_to_grid(origin: Vector2, side: float) -> Vector2:
	var half := side * 0.5
	var top_left := origin - Vector2(half, half)
	var snapped_top_left := Vector2(
		roundf(top_left.x / TILE_SIZE) * TILE_SIZE,
		roundf(top_left.y / TILE_SIZE) * TILE_SIZE)
	return snapped_top_left + Vector2(half, half)

func _physics_process(delta: float) -> void:
	age += delta
	var t := clampf(age / maxf(expand_duration, 0.001), 0.0, 1.0)
	# ease-out：起步快、收尾缓
	current_side = side_length * (1.0 - pow(1.0 - t, 3.0))
	if age >= lifetime:
		queue_free()
	else:
		queue_redraw()

func get_rect() -> Rect2:
	var half := side_length * 0.5
	return Rect2(global_position - Vector2(half, half), Vector2(side_length, side_length))

func contains_point(world_point: Vector2) -> bool:
	var rect := get_rect()
	return world_point.x >= rect.position.x and world_point.x <= rect.end.x \
		and world_point.y >= rect.position.y and world_point.y <= rect.end.y

func _draw() -> void:
	var alpha := clampf(1.0 - age / lifetime, 0.0, 1.0)
	var draw_color := Color(color.r, color.g, color.b, color.a * alpha)
	_draw_pixel_square(draw_color)

## 硬边、按像素对齐的方框：关闭抗锯齿，并把四边吸附到整数世界坐标。
func _draw_pixel_square(draw_color: Color) -> void:
	var half := maxf(1.0, roundf(current_side * 0.5))
	var pixel_offset := global_position.round() - global_position
	draw_rect(
		Rect2(pixel_offset.x - half, pixel_offset.y - half, half * 2.0, half * 2.0),
		draw_color, false, line_width, false)
