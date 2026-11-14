class_name PuzzleDoorManager
extends Node
## 解谜门控制器（移植自 CCCAT DoorManager）：
## ① 把 DoorTiles 图层里四邻相连的门格认成一扇门；
## ② 每物理帧按相连按钮是否全部满足决定门开/关，开门擦格、关门按开局快照回填；
## ③ R / 死亡重置时恢复该房间的门与按钮。
## 没有连接任何按钮的门恒为关闭。

signal door_opened(door_id: int, cells: Array[Vector2i])
signal door_closed(door_id: int, cells: Array[Vector2i])

## 少于这个数量的相连按钮时不做整组锁死：单按钮门锁死会退化成一次性按钮。
const MIN_BUTTONS_TO_LATCH := 2
const ORTHO_CELLS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]

@export var doors_layer: TileMapLayer
@export var buttons_root: Node2D
## 关卡载入时打印门清单，方便给按钮的 Door Cells 填坐标。
@export var log_doors := true

var _rooms: Array = []
## 每扇门：{cells, min_cell, room, open, buttons}
var _doors: Array[Dictionary] = []
var _cell_to_door: Dictionary = {}
## 开局快照：格坐标 -> [source_id, atlas_coords, alternative]
var _initial: Dictionary = {}
var _buttons: Array[DoorButton] = []
var _button_doors: Dictionary = {}

func _ready() -> void:
	# 按钮默认 0、WorldMap 100：管理器排在按钮之后、世界之前。
	process_physics_priority = 10

func clear() -> void:
	_rooms = []
	_doors.clear()
	_cell_to_door.clear()
	_initial.clear()
	_buttons.clear()
	_button_doors.clear()

## 接管本关的门图层与按钮。可重复调用（测试画完门/放完按钮后再调用一次）。
func setup(rooms: Array) -> void:
	clear()
	_rooms = rooms
	if doors_layer == null:
		return
	_group_doors()
	_collect_buttons()
	_log_manifest()

func get_door_id_at_cell(cell: Vector2i) -> int:
	return int(_cell_to_door.get(cell, -1))

func get_door_count() -> int:
	return _doors.size()

func is_door_open(door_id: int) -> bool:
	if door_id < 0 or door_id >= _doors.size():
		return false
	return bool(_doors[door_id]["open"])

func get_door_cells(door_id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if door_id < 0 or door_id >= _doors.size():
		return out
	out.assign(_doors[door_id]["cells"])
	return out

## 按 R 复位某个房间的门与按钮（与 WorldMap 的「只重置那一个房间」一致）。
func reset_room(room: Room) -> void:
	if doors_layer == null or room == null:
		return
	for door_id in _doors.size():
		var door: Dictionary = _doors[door_id]
		if door["room"] != room or not bool(door["open"]):
			continue
		door["open"] = false
		_restore_door_cells(door)
		door_closed.emit(door_id, get_door_cells(door_id))
	_reset_buttons_in_room(room)

func _physics_process(_delta: float) -> void:
	if doors_layer == null:
		return
	_latch_satisfied_doors()
	_apply_door_states()

## 某扇门连接按钮数 >= 2 且全部满足时，整组永久锁死（回弹按钮也变常开）。
func _latch_satisfied_doors() -> void:
	for door: Dictionary in _doors:
		var buttons: Array = door["buttons"]
		if buttons.size() < MIN_BUTTONS_TO_LATCH or not _all_buttons_satisfied(door):
			continue
		for button: DoorButton in buttons:
			if is_instance_valid(button):
				button.latch()

## 按当前按钮状态决定每扇门开还是关；只在状态翻转时动瓦片。
func _apply_door_states() -> void:
	for door_id in _doors.size():
		var door: Dictionary = _doors[door_id]
		var want_open := _all_buttons_satisfied(door)
		if want_open == bool(door["open"]):
			continue
		door["open"] = want_open
		if want_open:
			_erase_door_cells(door)
			door_opened.emit(door_id, get_door_cells(door_id))
		else:
			_restore_door_cells(door)
			door_closed.emit(door_id, get_door_cells(door_id))

# —— 分组：四邻连成一片的门格 = 一扇门 ——

func _group_doors() -> void:
	var all_cells := {}
	for cell in doors_layer.get_used_cells():
		all_cells[cell] = true

	var visited := {}
	var groups: Array = []
	for cell: Vector2i in all_cells:
		if visited.has(cell):
			continue
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [cell]
		visited[cell] = true
		var head := 0
		while head < queue.size():
			var current: Vector2i = queue[head]
			head += 1
			group.append(current)
			for offset in ORTHO_CELLS:
				var next: Vector2i = current + offset
				if not all_cells.has(next) or visited.has(next):
					continue
				visited[next] = true
				queue.append(next)
		groups.append(group)

	# 先按最左上格排序，再按行优先给门编号，保证稳定。
	for group: Array in groups:
		group.sort_custom(_is_cell_before)
	groups.sort_custom(func(a: Array, b: Array) -> bool: return _is_cell_before(a[0], b[0]))

	for group: Array in groups:
		var min_cell: Vector2i = group[0]
		var door_index := _doors.size()
		_doors.append({
			"cells": group,
			"min_cell": min_cell,
			"room": RoomRegistry.room_of_cell(_rooms, doors_layer, min_cell),
			"open": false,
			"buttons": [],
		})
		for cell: Vector2i in group:
			_cell_to_door[cell] = door_index
			# 开局快照：必须在任何门被打开之前记录。
			_initial[cell] = [
				doors_layer.get_cell_source_id(cell),
				doors_layer.get_cell_atlas_coords(cell),
				doors_layer.get_cell_alternative_tile(cell),
			]

func _is_cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

# —— 按钮接线 ——

func _collect_buttons() -> void:
	if buttons_root == null:
		return
	_collect_buttons_recursive(buttons_root)
	for button in _buttons:
		_button_doors[button] = _resolve_button_doors(button)
	for button in _buttons:
		for door_id in _button_doors[button]:
			(_doors[int(door_id)]["buttons"] as Array).append(button)

func _collect_buttons_recursive(node: Node) -> void:
	for child in node.get_children():
		if child is DoorButton:
			_buttons.append(child)
		_collect_buttons_recursive(child)

func _resolve_button_doors(button: DoorButton) -> Array[int]:
	var door_ids: Array[int] = []
	if _doors.is_empty():
		return door_ids
	for cell in button.door_cells:
		var door_id := get_door_id_at_cell(cell)
		if door_id < 0:
			push_warning("PuzzleDoorManager：按钮 %s 填的门格 %s 不是任何一扇门（该条已忽略）"
				% [button.name, str(cell)])
			continue
		if not door_ids.has(door_id):
			door_ids.append(door_id)
	return door_ids

# —— 门的状态 ↔ 瓦片 ——

## 没有连任何按钮的门恒为关闭。
func _all_buttons_satisfied(door: Dictionary) -> bool:
	var buttons: Array = door["buttons"]
	if buttons.is_empty():
		return false
	for button: DoorButton in buttons:
		if not is_instance_valid(button) or not button.is_pressed():
			return false
	return true

func _erase_door_cells(door: Dictionary) -> void:
	for cell: Vector2i in door["cells"]:
		doors_layer.erase_cell(cell)

func _restore_door_cells(door: Dictionary) -> void:
	for cell: Vector2i in door["cells"]:
		var info: Array = _initial.get(cell, [])
		if info.is_empty():
			continue
		doors_layer.set_cell(cell, info[0], info[1], info[2])

func _reset_buttons_in_room(room: Room) -> void:
	for button in _buttons:
		if not is_instance_valid(button):
			continue
		if RoomRegistry.room_at(_rooms, button.global_position) != room:
			continue
		button.reset_state()

func _log_manifest() -> void:
	if not log_doors or _doors.is_empty():
		return
	print("[PuzzleDoorManager] 本关共 %d 扇门（按钮的 Door Cells 填下面任意一格坐标即可）：" % _doors.size())
	for door_id in _doors.size():
		var cells_text := []
		for cell: Vector2i in _doors[door_id]["cells"]:
			cells_text.append("(%d,%d)" % [cell.x, cell.y])
		var room_name := "（无）"
		var room: Room = _doors[door_id]["room"]
		if room != null:
			room_name = room.room_name
		print("  门 %d：%d 格 %s｜房间 %s" % [
			door_id, _doors[door_id]["cells"].size(), " ".join(cells_text), room_name])
