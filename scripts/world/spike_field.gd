@tool
class_name SpikeField
extends TileMapLayer
## 刺图格：编辑器里绘制 `spike_tileset.tres` 的图块；运行时按四邻分组，
## 每组变成一只会追击的刺怪（不再发射红色脉冲）。

const TILE_SIZE := 16.0
const ORTHO_CELLS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
]
const MONSTER_SCRIPT := preload("res://scripts/actors/spike_monster.gd")

## 保留旧场景接线：传给刺怪用于查找玩家声场。
@export var sound_fields: Node2D
## 保留旧场景接线（当前未使用）。
@export var breakables: Breakables
## 刺怪容器；留空时自动在父节点下找/建 `Monsters`。
@export var monsters_root: Node2D

var _monsters: Array[Node] = []

func _ready() -> void:
	# 编辑器里显示刺图块方便绘制；运行时隐藏，由刺怪代替。
	visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	_spawn_monsters()

## 把当前画着的刺格按四邻分组，每组生成一只刺怪。
func _spawn_monsters() -> void:
	var root := _resolve_monsters_root()
	if root == null:
		return
	for group: Array in _groups():
		var bounds := _group_bounds(group)
		var group_center := bounds.get_center()
		var offsets: Array[Vector2] = []
		for cell: Vector2i in group:
			offsets.append(to_global(map_to_local(cell)) - group_center)
		var monster = MONSTER_SCRIPT.new()
		monster.set("sound_fields", sound_fields)
		root.add_child(monster)
		monster.call("setup", group_center, offsets, bounds.size)
		_monsters.append(monster)

func _groups() -> Array:
	var all_cells := {}
	for cell in get_used_cells():
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
	return groups

func _group_bounds(group: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for cell: Vector2i in group:
		var center := to_global(map_to_local(cell))
		var rect := Rect2(center - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, Vector2(TILE_SIZE, TILE_SIZE))
		bounds = rect if first else bounds.merge(rect)
		first = false
	return bounds

func _resolve_monsters_root() -> Node2D:
	if monsters_root != null and is_instance_valid(monsters_root):
		return monsters_root
	var parent := get_parent()
	if parent == null:
		return null
	var existing := parent.get_node_or_null("Monsters") as Node2D
	if existing != null:
		return existing
	var created := Node2D.new()
	created.name = "Monsters"
	created.z_index = 3
	parent.add_child(created)
	return created

## R / 死亡重置时把所有刺怪送回出生位置。
func reset_monsters() -> void:
	for monster in _monsters:
		if is_instance_valid(monster):
			monster.call("reset_home")
