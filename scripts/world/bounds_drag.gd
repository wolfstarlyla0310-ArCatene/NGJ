extends RefCounted
class_name BoundsDrag
## 关卡边界的拖拽几何（纯函数，不碰编辑器 API），由 tests/misc/test_bounds_drag.gd 直接单测。
## 8 个手柄（四角 + 四边中点）：拖角动两条边，拖边中点只动那条边，拖边框线整体平移（MOVE）。
## 另含多房间用的 `union_rect()` / `rect_index_at()` / `axis_lock()`。
## 原理见 docs/设计说明/05-跨系统约定与引擎坑.md

## 最小边长（像素）：防止把某条边拖过对边，把矩形拖成零面积甚至翻面。
const MIN_SIZE := 16.0

## 拖拽命中的目标。
enum Handle {
	NONE,          ## 没命中任何东西 —— 交给编辑器自己处理（选节点、刷地形……）
	MOVE,          ## 拖边框线：整个矩形平移
	TOP_LEFT,
	TOP,
	TOP_RIGHT,
	RIGHT,
	BOTTOM_RIGHT,
	BOTTOM,
	BOTTOM_LEFT,
	LEFT,
}


## 8 个缩放手柄的位置；返回 Handle → Vector2 字典（顺序稳定）。
static func handle_points(rect: Rect2) -> Dictionary:
	var tl := rect.position
	var br := rect.end
	var center := rect.get_center()
	return {
		Handle.TOP_LEFT: tl,
		Handle.TOP: Vector2(center.x, tl.y),
		Handle.TOP_RIGHT: Vector2(br.x, tl.y),
		Handle.RIGHT: Vector2(br.x, center.y),
		Handle.BOTTOM_RIGHT: br,
		Handle.BOTTOM: Vector2(center.x, br.y),
		Handle.BOTTOM_LEFT: Vector2(tl.x, br.y),
		Handle.LEFT: Vector2(tl.x, center.y),
	}


## 命中测试：point 落在哪个手柄 / 边框带上；`tol` 是手柄方块半边长。
## 顺序：先测 8 个手柄方块、再测边框带（角上优先于整体平移）。
static func hit_test(rect: Rect2, point: Vector2, tol: float) -> Handle:
	var points := handle_points(rect)
	for handle in points:
		if in_square(point, points[handle], tol):
			return handle
	if near_border(rect, point, tol):
		return Handle.MOVE
	return Handle.NONE


## point 是否落在以 center 为中心、半边长 tol 的方块里。
static func in_square(point: Vector2, center: Vector2, tol: float) -> bool:
	return absf(point.x - center.x) <= tol and absf(point.y - center.y) <= tol


## point 是否落在矩形边框 ±tol 的环带上（矩形**内部**不算，所以框内点击不劫持）。
static func near_border(rect: Rect2, point: Vector2, tol: float) -> bool:
	if not in_rect(rect.grow(tol), point):
		return false
	var inner := rect.grow(-tol)
	# 框比环带还窄时内圈是空的，整个框都算边框
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return true
	return not in_rect(inner, point)


## 与 Rect2.has_point 的区别：四条边都算「在内」。
static func in_rect(rect: Rect2, point: Vector2) -> bool:
	return point.x >= rect.position.x and point.x <= rect.end.x \
		and point.y >= rect.position.y and point.y <= rect.end.y


## 一组矩形的并集矩形（多房间整体拖动时当外框）；空数组返回零矩形。
static func union_rect(rects: Array[Rect2]) -> Rect2:
	if rects.is_empty():
		return Rect2()
	var result := rects[0]
	for i in range(1, rects.size()):
		result = result.merge(rects[i])
	return result


## 一组矩形里第一个包含 point 的下标（都不含返回 -1）；四条边都算命中，顺序靠前优先。
static func rect_index_at(rects: Array[Rect2], point: Vector2) -> int:
	for i in rects.size():
		if in_rect(rects[i], point):
			return i
	return -1


## 轴向锁定：只保留绝对值较大的分量，另一个归零（同 Godot 2D 编辑器 Shift 拖节点的单轴吸附）；
## 相等时保留 X（定死，避免浮点抖动）。
static func axis_lock(delta: Vector2) -> Vector2:
	if absf(delta.x) >= absf(delta.y):
		return Vector2(delta.x, 0.0)
	return Vector2(0.0, delta.y)


## 按手柄把矩形拖 delta 像素：MOVE 只改位置，其余手柄只动管得到的边；带 MIN_SIZE 钳制。
static func apply(rect: Rect2, handle: Handle, delta: Vector2) -> Rect2:
	if handle == Handle.NONE:
		return rect
	if handle == Handle.MOVE:
		return Rect2(rect.position + delta, rect.size)

	var left := rect.position.x
	var top := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y

	if moves_left(handle):
		left = minf(left + delta.x, right - MIN_SIZE)
	if moves_right(handle):
		right = maxf(right + delta.x, left + MIN_SIZE)
	if moves_top(handle):
		top = minf(top + delta.y, bottom - MIN_SIZE)
	if moves_bottom(handle):
		bottom = maxf(bottom + delta.y, top + MIN_SIZE)

	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


## 这个手柄管得到矩形的左边吗
static func moves_left(handle: Handle) -> bool:
	return handle == Handle.LEFT or handle == Handle.TOP_LEFT or handle == Handle.BOTTOM_LEFT


## 这个手柄管得到矩形的右边吗
static func moves_right(handle: Handle) -> bool:
	return handle == Handle.RIGHT or handle == Handle.TOP_RIGHT or handle == Handle.BOTTOM_RIGHT


## 这个手柄管得到矩形的上边吗
static func moves_top(handle: Handle) -> bool:
	return handle == Handle.TOP or handle == Handle.TOP_LEFT or handle == Handle.TOP_RIGHT


## 这个手柄管得到矩形的下边吗
static func moves_bottom(handle: Handle) -> bool:
	return handle == Handle.BOTTOM or handle == Handle.BOTTOM_LEFT or handle == Handle.BOTTOM_RIGHT
