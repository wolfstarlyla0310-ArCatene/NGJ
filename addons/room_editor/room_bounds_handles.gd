@tool
extends RefCounted
class_name RoomBoundsHandles
## 房间矩形的 2D 视口拖拽手柄（给房间编辑器插件用）；几何算法全在 scripts/common/bounds_drag.gd。
## 单选拖 8 个方块/边框线；多选（Shift）描并集外框、整组平移；任意拖动中 Shift = 轴向锁定。
## 单房间走局部坐标，多房间走世界坐标。
## ⚠️ 编辑器 2D 视图的平移缩放只存在于 `global_canvas_transform`，别用
## `get_global_transform_with_canvas()`，否则手柄被画到可见区外（房间蓝框却照常显示）。

## 手柄方块的边长（**屏幕像素**，不随视图缩放变大变小）
const HANDLE_PX := 12.0
## 撤销记录里的动作名
const UNDO_ACTION := "拖动房间矩形"
## 多选整组拖动时的撤销动作名（Ctrl+Z 一次退回整组）
const UNDO_ACTION_MULTI := "拖动多个房间矩形"
## 手柄方块颜色（白色填充 + 深蓝描边，与场景里那条蓝框区分开）
const HANDLE_FILL := Color(1.0, 1.0, 1.0, 1.0)
const HANDLE_EDGE := Color(0.1, 0.35, 0.6, 1.0)
## 正在拖的时候把边框高亮成这个颜色，明确「这次拖的是房间边界」
const DRAG_COLOR := Color(1.0, 0.85, 0.2, 0.9)
## 多选时给「这一整组」描的颜色（每个选中房间的边框 + 并集外框）
const MULTI_COLOR := Color(1.0, 0.62, 0.2, 0.95)
## 边框描边的线宽（**屏幕像素**）；并集外框略粗一点，好与单个房间的边框区分
const BORDER_PX := 1.0
const MULTI_BORDER_PX := 2.0

## 矩形被拖过（且记进了撤销栈）时发出，供插件标记场景「有未保存的修改」。
signal bounds_edited

## 正在拖的手柄；NONE 表示当前没在拖
var _active: BoundsDrag.Handle = BoundsDrag.Handle.NONE
## 本次拖的是「一个房间」（false）还是「一整组」（true）
var _multi := false
## 本次拖动涉及哪些房间（按下那一刻定格，免得拖到一半选区变了）。
var _drag_rooms: Array[Room] = []
## 单房间：按下时的矩形与鼠标位置（局部坐标），全程以它为基准算偏移，避免误差累积。
var _drag_start_rect := Rect2()
var _drag_origin := Vector2()
## 多房间：每个房间按下那一刻的**局部** rect（撤销用）与**世界** rect（算位移用）
var _drag_start_rects: Array[Rect2] = []
var _drag_world_rects: Array[Rect2] = []
## 多房间：按下那一刻的鼠标位置（世界坐标）
var _drag_origin_world := Vector2()
## 本次拖动是否真的改动了矩形（决定松开鼠标时要不要记一条撤销）
var _changed := false


## ——— 绘制 ———

## 把选中房间的手柄 / 边框画到 2D 视口 overlay 上：1 个走单房间画法，多个走整组画法。
func draw(overlay: Control, rooms: Array[Room]) -> void:
	var valid := _valid_rooms(rooms)
	if valid.is_empty():
		return
	if valid.size() == 1:
		_draw_single(overlay, valid[0])
	else:
		_draw_multi(overlay, valid)


## 单房间：8 个可拖方块 + （拖动中）黄色边框。
func _draw_single(overlay: Control, room: Room) -> void:
	var xf := view_transform(room)
	var scale_factor := view_scale(xf)
	var half := HANDLE_PX * 0.5 / scale_factor
	var rect: Rect2 = room.rect

	# 从此刻起按房间节点局部坐标画，overlay 自己会叠好视图的平移缩放
	overlay.draw_set_transform_matrix(xf)

	# 拖动中：把边框描成黄色，一眼看出这次拖的是这个房间
	if _active != BoundsDrag.Handle.NONE:
		overlay.draw_rect(rect, DRAG_COLOR, false, 2.0 / scale_factor)

	var points := BoundsDrag.handle_points(rect)
	for handle in points:
		var p: Vector2 = points[handle]
		var box := Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0)
		overlay.draw_rect(box, HANDLE_FILL, true)
		overlay.draw_rect(box, HANDLE_EDGE, false, 1.0 / scale_factor)

	# 还原成单位变换，别影响编辑器后续的绘制
	overlay.draw_set_transform_matrix(Transform2D())


## 多房间：每个选中房间的边框 + 它们的并集外框，都描成橙黄色。
## 房间边框用各自节点变换画（局部坐标），并集外框用世界坐标 + 纯视图变换画。
func _draw_multi(overlay: Control, rooms: Array[Room]) -> void:
	# 1) 逐个房间：描出自己的边框，谁被选中一目了然
	for room in rooms:
		var xf := view_transform(room)
		overlay.draw_set_transform_matrix(xf)
		overlay.draw_rect(room.rect, MULTI_COLOR, false, MULTI_BORDER_PX / view_scale(xf))
	overlay.draw_set_transform_matrix(Transform2D())

	# 2) 并集外框：整组的范围，也是最好抓的那个目标
	var view := view_only_transform()
	var union := BoundsDrag.union_rect(_world_rects(rooms))
	overlay.draw_set_transform_matrix(view)
	# 拖动中换成黄色，明确「整组正被抓着」
	var color := DRAG_COLOR if _active != BoundsDrag.Handle.NONE else MULTI_COLOR
	overlay.draw_rect(union, color, false, MULTI_BORDER_PX / view_scale(view))
	overlay.draw_set_transform_matrix(Transform2D())


## ——— 输入 ———

## 处理 2D 视口的鼠标事件；返回 true = 事件被吃掉，编辑器不要再当它是「选节点 / 拖节点」。
func gui_input(event: InputEvent, rooms: Array[Room], undo: EditorUndoRedoManager) -> bool:
	var valid := _valid_rooms(rooms)
	if valid.is_empty():
		return false

	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return false
		if event.pressed:
			return begin_drag(event.position, valid, event.shift_pressed)
		return end_drag(undo)

	if event is InputEventMouseMotion and _active != BoundsDrag.Handle.NONE:
		# 兜底：视口外松开鼠标收不到 release，靠 button_mask 认出已松手，免得手柄粘住鼠标。
		if event.button_mask == 0:
			return end_drag(undo)
		# Shift 每帧重读：拖到一半才按住也能立刻锁轴向，松开立刻恢复自由方向。
		update_drag(event.position, event.shift_pressed)
		return true

	return false


## 鼠标按下。判定顺序：① 抓到手柄/边框带 → 开始拖；② 没抓住 + Shift + 点在房间内部 →
## 加/移出选区；③ 其余交回编辑器。「点在哪」正是 Shift 一语双关的消解办法。
func begin_drag(viewport_pos: Vector2, rooms: Array[Room], shift: bool) -> bool:
	var handle := _hit(rooms, viewport_pos)
	if handle == BoundsDrag.Handle.NONE:
		if shift:
			return _toggle_selection_at(viewport_pos, rooms)
		return false

	_active = handle
	_changed = false
	_multi = rooms.size() > 1
	_drag_rooms.assign(rooms)
	if _multi:
		_drag_start_rects = _local_rects(_drag_rooms)
		_drag_world_rects = _world_rects(_drag_rooms)
		_drag_origin_world = screen_to_world(viewport_pos)
	else:
		var xf := view_transform(_drag_rooms[0])
		_drag_start_rect = _drag_rooms[0].rect
		_drag_origin = xf.affine_inverse() * viewport_pos
	return true


## 拖动中。单房间按「按下时的矩形 + 总位移」重算（避免误差累积），多房间把同一世界位移加到各起始矩形上。
func update_drag(viewport_pos: Vector2, shift: bool) -> void:
	if _drag_rooms.is_empty():
		return

	if _multi:
		var delta := screen_to_world(viewport_pos) - _drag_origin_world
		if shift:
			delta = BoundsDrag.axis_lock(delta)
		_changed = delta.length() > 0.001
		for i in _drag_rooms.size():
			var room := _drag_rooms[i]
			var want := Rect2(_drag_world_rects[i].position + delta, _drag_world_rects[i].size)
			# 世界矩形写回节点局部坐标（节点不在原点时也不会错位）
			room.rect = Rect2(room.to_local(want.position), want.size)
		return

	var room := _drag_rooms[0]
	var xf := view_transform(room)
	var local := xf.affine_inverse() * viewport_pos
	var delta := local - _drag_origin
	# ★ 只对「整体平移」做轴向锁定；缩放类手柄不受影响（需求要的是「平移」）
	if shift and _active == BoundsDrag.Handle.MOVE:
		delta = BoundsDrag.axis_lock(delta)
	var next := BoundsDrag.apply(_drag_start_rect, _active, delta)
	_changed = not next.is_equal_approx(_drag_start_rect)
	room.rect = next


## 松开鼠标：真拖动过就记一条可撤销动作（Ctrl+Z 整段回退）；多选时整组塞进同一条。
func end_drag(undo: EditorUndoRedoManager) -> bool:
	var was_dragging := _active != BoundsDrag.Handle.NONE
	var rooms := _drag_rooms
	_active = BoundsDrag.Handle.NONE
	_drag_rooms = []
	if not was_dragging:
		return false
	if not _changed:
		# 只是点了一下没拖动，不留撤销记录
		_clear_drag_cache()
		return true

	# 判据用「按下时那一组到底记了几个起始矩形」，比再推一遍 _multi 稳
	var use_multi := _drag_start_rects.size() == rooms.size()
	var action_name := UNDO_ACTION_MULTI if use_multi else UNDO_ACTION
	undo.create_action(action_name)
	for i in rooms.size():
		var start := _drag_start_rect
		if use_multi:
			start = _drag_start_rects[i]
		undo.add_do_property(rooms[i], "rect", rooms[i].rect)
		undo.add_undo_property(rooms[i], "rect", start)
	undo.commit_action()
	_clear_drag_cache()
	bounds_edited.emit()
	return true


## ——— 命中测试与选区 ———

## 鼠标点抓到了什么。单房间：8 个手柄 + 边框带；多房间：只有「整组平移」。
func _hit(rooms: Array[Room], viewport_pos: Vector2) -> BoundsDrag.Handle:
	if rooms.size() == 1:
		var xf := view_transform(rooms[0])
		var tol := HANDLE_PX * 0.5 / view_scale(xf)
		return BoundsDrag.hit_test(rooms[0].rect, xf.affine_inverse() * viewport_pos, tol)

	# 多选：并集外框的边框带，或任意选中房间自己的边框带 —— 都算「抓住整组」
	var world := screen_to_world(viewport_pos)
	var tol := HANDLE_PX * 0.5 / view_scale(view_only_transform())
	var world_rects := _world_rects(rooms)
	if BoundsDrag.near_border(BoundsDrag.union_rect(world_rects), world, tol):
		return BoundsDrag.Handle.MOVE
	for r in world_rects:
		if BoundsDrag.near_border(r, world, tol):
			return BoundsDrag.Handle.MOVE
	return BoundsDrag.Handle.NONE


## Shift+点房间内部：把它加进/移出编辑器选区（候选 = 同一容器下的全部房间）。返回 true = 事件被吃掉。
## 只动 EditorSelection，不另立选中状态；`add_node()`/`remove_node()` 不会标记场景被修改。
func _toggle_selection_at(viewport_pos: Vector2, rooms: Array[Room]) -> bool:
	var candidates := _sibling_rooms(rooms)
	if candidates.is_empty():
		return false

	var world := screen_to_world(viewport_pos)
	var index := BoundsDrag.rect_index_at(_world_rects(candidates), world)
	if index < 0:
		return false

	var target := candidates[index]
	var selection := EditorInterface.get_selection()
	if selection.get_selected_nodes().has(target):
		selection.remove_node(target)
	else:
		selection.add_node(target)
	return true


## 与给定房间处在同一个容器下的全部房间（点选时的候选集合）。
func _sibling_rooms(rooms: Array[Room]) -> Array[Room]:
	var out: Array[Room] = []
	if rooms.is_empty():
		return out
	var parent := rooms[0].get_parent()
	if parent == null:
		return out
	for child in parent.get_children():
		if child is Room:
			out.append(child)
	return out


## ——— 坐标换算 ———

## 房间节点局部坐标 → 编辑器视口的屏幕像素坐标（= 纯视图变换 × 节点全局变换）。
## ⚠️ 不能用 `room.get_global_transform_with_canvas()`：编辑器视图的平移缩放设在
## `global_canvas_transform` 上，用它等于丢掉视图变换，手柄会被画到可见区外。
func view_transform(room: Room) -> Transform2D:
	if room == null or not is_instance_valid(room):
		return Transform2D()
	return view_only_transform() * room.get_global_transform()


## 编辑器 2D 视图的纯视图变换（世界坐标 → 屏幕像素），不含任何节点变换；多房间拖动用它。
func view_only_transform() -> Transform2D:
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if editor_viewport == null:
		return Transform2D()
	return editor_viewport.get_global_canvas_transform()


## 视口屏幕坐标 → 世界坐标（`view_only_transform()` 的逆）。
func screen_to_world(viewport_pos: Vector2) -> Vector2:
	return view_only_transform().affine_inverse() * viewport_pos


## 视图缩放倍数（屏幕像素换算成局部单位时除它）；取绝对值并兜底，免得除出 inf。
func view_scale(xf: Transform2D) -> float:
	return maxf(absf(xf.get_scale().x), 0.0001)


## ——— 小工具 ———

## 过滤掉已经失效的引用（拖动期里有房间被删掉也不至于崩）。
func _valid_rooms(rooms: Array[Room]) -> Array[Room]:
	var out: Array[Room] = []
	for room in rooms:
		if room != null and is_instance_valid(room):
			out.append(room)
	return out


## 一组房间按下那一刻的**局部**矩形（撤销记录的起始值）。
func _local_rects(rooms: Array[Room]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for room in rooms:
		out.append(room.rect)
	return out


## 一组房间的**世界**矩形。
func _world_rects(rooms: Array[Room]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for room in rooms:
		out.append(room.get_rect())
	return out


## 清掉本次拖动的缓存（拖完 / 判定为「没拖动」时调）。
func _clear_drag_cache() -> void:
	_drag_start_rects = []
	_drag_world_rects = []
	_drag_rooms = []
	_multi = false
	_changed = false
