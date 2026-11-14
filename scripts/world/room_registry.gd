extends RefCounted
class_name RoomRegistry
## 房间几何判定（纯函数，零耦合）：回答「某个世界坐标 / 某个地形格属于哪个房间」。
## 判定规则：按传入数组顺序返回第一个命中的房间，命中判定用 BoundsDrag.in_rect()（四条边都算）。
## 原理见 docs/设计说明/04-世界与房间.md


## 包含该世界坐标的房间；不在任何房间内时返回 null（合法状态，调用方保持现状）。
## rooms 元素需具备 get_rect() -> Rect2（正常是 Room 节点）。
## 本函数是「某坐标属于哪个房间」的唯一真值源，别处判归属必须调它。
static func room_at(rooms: Array, world_point: Vector2) -> Room:
	for room in rooms:
		var r := room as Room
		if r == null:
			continue
		if r.contains_world_point(world_point):
			return r
	return null


## 收集「归属于该房间」的节点（按中心点 global_position 判定）。
## 归属一律走 room_at(rooms, ...)，必须传完整的 rooms 顺序表，不能用 room.contains_world_point。
static func members_in_room(rooms: Array, room: Room, candidates: Array) -> Array[Node]:
	var result: Array[Node] = []
	if room == null:
		return result
	for node in candidates:
		var n := node as Node
		if n is Node2D and room_at(rooms, (n as Node2D).global_position) == room:
			result.append(n)
	return result


## 某个地形格属于哪个房间（按格中心判定；房间边线最好对齐 16px 网格）。
static func room_of_cell(rooms: Array, terrain: TileMapLayer, cell: Vector2i) -> Room:
	if terrain == null:
		return null
	return room_at(rooms, terrain.to_global(terrain.map_to_local(cell)))


## 两个矩形是否上下/左右相邻（不把斜角算进来）。
## 房间之间常有 0.4~1.2px 的缝隙，默认容差 2px。
static func is_orthogonal_neighbor(a: Rect2, b: Rect2, tolerance := 2.0) -> bool:
	var x_gap := maxf(a.position.x, b.position.x) - minf(a.end.x, b.end.x)
	var y_gap := maxf(a.position.y, b.position.y) - minf(a.end.y, b.end.y)
	# 左右相邻：y 有真实重叠，x 间隙很小。
	if y_gap < 0.0 and absf(x_gap) <= tolerance:
		return true
	# 上下相邻：x 有真实重叠，y 间隙很小。
	if x_gap < 0.0 and absf(y_gap) <= tolerance:
		return true
	return false


## 某个房间的上下左右相邻房间（不含自身与斜角）。
static func orthogonal_neighbors(rooms: Array, room: Room, tolerance := 2.0) -> Array[Room]:
	var result: Array[Room] = []
	if room == null:
		return result
	var rect := room.get_rect()
	for other in rooms:
		var r := other as Room
		if r == null or r == room:
			continue
		if is_orthogonal_neighbor(rect, r.get_rect(), tolerance):
			result.append(r)
	return result
