class_name SoundField
extends Node2D
## 声场：方形扩散波的视觉效果。发出后 `expand_duration` 秒内从中心扩散到目标边长，
## 之后保持满框，并在 `lifetime` 秒生命周期内淡出。
## lv2 玩家落地/顶头波使用 `LV2_LIFETIME`（2 秒）。
## 判定（玻璃/噪音/安全）仍按目标尺寸 `side_length` 立即生效，不随视觉扩散。

const TILE_SIZE := 16.0
const LV2_LIFETIME := 2.0

@export var side_length: float = 96.0
@export var lifetime: float = 0.5
@export var line_width: float = 2.0
## 从中心扩到目标边长所需时间（秒）。
@export var expand_duration: float = 0.2
## 线框颜色；玩家声场白色，刺/死亡声场红色。
## setter 同时按颜色等级设置绘制层级：黄 > 蓝 > 白。
@export var color := Color(1.0, 1.0, 1.0, 1.0):
	set(value):
		color = value
		z_index = maxi(color_rank(value), 0)
## 接触是否杀死玩家。
@export var lethal := false
## 是否提供噪音免疫并隐藏噪音格。玩家声场 true，刺/死亡声场 false。
@export var safe_for_player := true
## 声场等级（0/1/2）；动物只响应 level == 1。
@export var level := 0
## 持久声场（门脉冲）：世界重置时不清理。
@export var persistent := false
## 为 true 时忽略其它声场的遮挡/合并，始终绘制完整边框（刺怪外缘闪烁用）。
@export var never_covered := false
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

## 标准声场颜色的覆盖等级：白 0 < 蓝 1 < 黄 2；其它颜色（红等）返回 -1，不参与等级覆盖。
static func color_rank(field_color: Color) -> int:
	if _rgb_equal(field_color, Color.WHITE):
		return 0
	if _rgb_equal(field_color, color_for_level(1)):
		return 1
	if _rgb_equal(field_color, color_for_level(2)):
		return 2
	return -1

static func _rgb_equal(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)

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
	if expand_duration <= 0.0:
		# 不扩散的声场（怪物外缘闪烁）直接满尺寸。
		current_side = side_length
	else:
		var t := clampf(age / expand_duration, 0.0, 1.0)
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

## 硬边、按像素对齐的方框；同色重叠处只保留并集外轮廓。
func _draw_pixel_square(draw_color: Color) -> void:
	for piece in visible_border_rects():
		draw_rect(Rect2(piece.position - global_position, piece.size), draw_color, true)

## 当前实际绘制的方形区域（世界坐标、按像素取整），用于同类重叠判定。
func drawn_world_rect() -> Rect2:
	var half := maxf(1.0, roundf(current_side * 0.5))
	var center := global_position.round()
	return Rect2(center - Vector2(half, half), Vector2(half * 2.0, half * 2.0))

## 同类判定：只看 RGB，忽略 alpha；白 / 蓝 / 黄 / 红各自成组。
func _is_same_family(other: SoundField) -> bool:
	return is_equal_approx(color.r, other.color.r) \
		and is_equal_approx(color.g, other.color.g) \
		and is_equal_approx(color.b, other.color.b)

## 同一父节点下、可见的同类兄弟声场矩形（收集品脉冲是子节点，不会参与）。
## 先按 `view_rect` 做相交预筛：不相交的场不可能切掉任何边段，跳过以免每次绘制全量扫描。
func _occluders(view_rect: Rect2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if never_covered:
		return rects
	var parent := get_parent()
	if parent == null:
		return rects
	var self_rank := color_rank(color)
	for child in parent.get_children():
		if child == self or not child is SoundField:
			continue
		var other := child as SoundField
		if other.is_queued_for_deletion() or not other.visible:
			continue
		var other_rect := other.drawn_world_rect()
		if not view_rect.intersects(other_rect):
			continue
		# 同色合并；标准色之间按等级单向覆盖：黄 > 蓝 > 白。
		var covers := _is_same_family(other)
		if not covers and self_rank >= 0:
			covers = color_rank(other.color) > self_rank
		if covers:
			rects.append(other_rect)
	return rects

## 当前可见的边界分段（世界坐标、厚度 line_width）；同类重叠处的内部边段已去掉。
func visible_border_rects() -> Array[Rect2]:
	var rect := drawn_world_rect()
	var occluders := _occluders(rect)
	var w := maxf(1.0, line_width)
	var out: Array[Rect2] = []
	for span in _visible_spans(rect.position.x, rect.end.x, rect.position.y, true, occluders):
		out.append(Rect2(span.x, rect.position.y - w * 0.5, span.y - span.x, w))
	for span in _visible_spans(rect.position.x, rect.end.x, rect.end.y, true, occluders):
		out.append(Rect2(span.x, rect.end.y - w * 0.5, span.y - span.x, w))
	for span in _visible_spans(rect.position.y, rect.end.y, rect.position.x, false, occluders):
		out.append(Rect2(rect.position.x - w * 0.5, span.x, w, span.y - span.x))
	for span in _visible_spans(rect.position.y, rect.end.y, rect.end.x, false, occluders):
		out.append(Rect2(rect.end.x - w * 0.5, span.x, w, span.y - span.x))
	return out

## 沿一条边计算未被同类矩形遮住的区间；fixed 是边线另一轴的坐标。
## 只有边线严格落在对方内部才遮挡：共享边/贴边不算重叠，公共边保留。
func _visible_spans(edge_start: float, edge_end: float, fixed: float, horizontal: bool,
		occluders: Array[Rect2]) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for r in occluders:
		var a := 0.0
		var b := 0.0
		if horizontal:
			if fixed <= r.position.y or fixed >= r.end.y:
				continue
			a = maxf(edge_start, r.position.x)
			b = minf(edge_end, r.end.x)
		else:
			if fixed <= r.position.x or fixed >= r.end.x:
				continue
			a = maxf(edge_start, r.position.y)
			b = minf(edge_end, r.end.y)
		if b > a:
			cuts.append(Vector2(a, b))
	cuts.sort_custom(_sort_spans)
	var spans: Array[Vector2] = []
	var cursor := edge_start
	for cut in cuts:
		if cut.x > cursor:
			spans.append(Vector2(roundf(cursor), roundf(cut.x)))
		cursor = maxf(cursor, cut.y)
		if cursor >= edge_end:
			break
	if cursor < edge_end:
		spans.append(Vector2(roundf(cursor), roundf(edge_end)))
	var cleaned: Array[Vector2] = []
	for span in spans:
		if span.y > span.x:
			cleaned.append(span)
	return cleaned

func _sort_spans(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x
