
@tool
class_name SpikeField
extends TileMapLayer

## 刺图格：编辑器里绘制 spike_tileset.tres 的图块。
## 运行时按四邻分组，每组生成一只会追击的刺怪。
## 所有刺怪共用一个音效，音量由最近刺怪的距离决定。

const TILE_SIZE := 16.0

const ORTHO_CELLS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(0, 1),
	Vector2i(-1, 0),
	Vector2i(1, 0)
]

const MONSTER_SCRIPT := preload(
	"res://scripts/actors/spike_monster.gd"
)


# ==============================
# 原有场景引用
# ==============================

## 保留旧场景接线：传给刺怪用于查找玩家声场。
@export var sound_fields: Node2D

## 保留旧场景接线（当前未使用）。
@export var breakables: Breakables

## 刺怪容器；留空时自动在父节点下寻找或创建 Monsters。
@export var monsters_root: Node2D


# ==============================
# 刺怪音效
# ==============================

@export_group("刺怪音效")

## 玩家节点，在 Inspector 中拖入 Player。
@export var player: EchoPlayer

## 最大声音传播距离，单位像素。
## 96 像素 = 6 格。
@export_range(16.0, 512.0, 16.0)
var monster_sound_distance: float = 96.0

## 音量渐变速度，越大变化越快。
@export_range(0.1, 20.0, 0.1)
var monster_sound_fade_speed: float = 3.0

## 场景中唯一的怪物音效播放器。
## 音频文件通过 Inspector 的 Stream 属性挂载。
@onready var monster_audio: AudioStreamPlayer = (
	get_node_or_null("MonsterSound") as AudioStreamPlayer
)

var _monster_sound_gain: float = 0.0
var _monster_base_volume_db: float = 0.0


# ==============================
# 刺怪视觉
# ==============================

@export_group("刺怪视觉")

## 两轮红色短声场之间的间隔。
@export var monster_visual_cycle_interval := 2.0

## 单轮连发之间的间隔。
@export var monster_visual_burst_interval := 0.1

## 每轮连发数量。
@export var monster_visual_burst_count := 3

## 红色短声场边长（格）。
@export var monster_visual_side_cells := 3.0

## 单个红色短声场寿命。
@export var monster_visual_lifetime := 0.2

@export var monster_visual_color := Color(
	1.0, 0.2, 0.2, 1.0
)


# ==============================
# 刺怪管理
# ==============================

var _monsters: Array[Node] = []


func _ready() -> void:
	# 编辑器中显示刺图块，运行时由刺怪代替。
	visible = Engine.is_editor_hint()

	if Engine.is_editor_hint():
		return

	_spawn_monsters()

	# 初始化唯一的怪物音效播放器。
	if monster_audio != null:
		_monster_base_volume_db = monster_audio.volume_db
		monster_audio.stop()
		monster_audio.volume_db = -80.0
	else:
		push_warning(
			"Spikes 缺少 MonsterSound (AudioStreamPlayer) 子节点"
		)


# ==============================
# 最近刺怪距离音效
# ==============================

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if monster_audio == null or monster_audio.stream == null:
		return

	var target_gain: float = _calculate_monster_sound_gain()

	# 平滑调整音量，避免距离变化时声音突然跳变。
	_monster_sound_gain = move_toward(
		_monster_sound_gain,
		target_gain,
		monster_sound_fade_speed * delta
	)

	# 距离过远时停止播放。
	if _monster_sound_gain <= 0.001:
		if monster_audio.playing:
			monster_audio.stop()
		return

	# 线性音量转换为分贝。
	monster_audio.volume_db = (
		_monster_base_volume_db
		+ linear_to_db(maxf(_monster_sound_gain, 0.001))
	)

	# 始终只有一个播放器发声。
	if not monster_audio.playing:
		monster_audio.play()


func _calculate_monster_sound_gain() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0

	if monster_sound_distance <= 0.0:
		return 0.0

	var nearest_distance: float = INF

	for monster in _monsters:
		if not is_instance_valid(monster):
			continue

		if not monster is Node2D:
			continue

		var monster_node := monster as Node2D

		# 怪物已经退出场景时不参与计算。
		if not monster_node.is_inside_tree():
			continue

		# 隐藏的怪物不参与声音计算。
		# 不能用 is_visible_in_tree()：
		# SpikeField 本身会在运行时隐藏 TileMap。
		if not monster_node.visible:
			continue

		var distance: float = (
			player.global_position.distance_to(
				monster_node.global_position
			)
		)

		nearest_distance = minf(
			nearest_distance,
			distance
		)

		if nearest_distance <= 0.0:
			break

	if nearest_distance >= monster_sound_distance:
		return 0.0

	return clampf(
		1.0 - nearest_distance / monster_sound_distance,
		0.0,
		1.0
	)


# ==============================
# 自动生成刺怪
# ==============================

## 当前刺格按四邻分组，每组生成一只刺怪。
func _spawn_monsters() -> void:
	var root := _resolve_monsters_root()

	if root == null:
		return

	for group: Array in _groups():
		var bounds := _group_bounds(group)
		var group_center := bounds.get_center()

		var offsets: Array[Vector2] = []

		for cell: Vector2i in group:
			offsets.append(
				to_global(map_to_local(cell)) - group_center
			)

		var monster = MONSTER_SCRIPT.new()

		# 保留原有怪物行为与视觉参数。
		monster.set(
			"sound_fields",
			sound_fields
		)

		monster.set(
			"visual_cycle_interval",
			monster_visual_cycle_interval
		)

		monster.set(
			"visual_burst_interval",
			monster_visual_burst_interval
		)

		monster.set(
			"visual_burst_count",
			monster_visual_burst_count
		)

		monster.set(
			"visual_side_cells",
			monster_visual_side_cells
		)

		monster.set(
			"visual_lifetime",
			monster_visual_lifetime
		)

		monster.set(
			"visual_color",
			monster_visual_color
		)

		root.add_child(monster)

		monster.call(
			"setup",
			group_center,
			offsets,
			bounds.size
		)

		_monsters.append(monster)


# ==============================
# 四邻分组
# ==============================

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

				if not all_cells.has(next):
					continue

				if visited.has(next):
					continue

				visited[next] = true
				queue.append(next)

		groups.append(group)

	return groups


# ==============================
# 计算刺怪生成范围
# ==============================

func _group_bounds(group: Array) -> Rect2:
	var bounds := Rect2()
	var first := true

	for cell: Vector2i in group:
		var center := to_global(map_to_local(cell))

		var rect := Rect2(
			center - Vector2(TILE_SIZE, TILE_SIZE) * 0.5,
			Vector2(TILE_SIZE, TILE_SIZE)
		)

		bounds = rect if first else bounds.merge(rect)
		first = false

	return bounds


# ==============================
# 查找或创建 Monsters 容器
# ==============================

func _resolve_monsters_root() -> Node2D:
	if monsters_root != null and is_instance_valid(monsters_root):
		return monsters_root

	var parent := get_parent()

	if parent == null:
		return null

	var existing := parent.get_node_or_null(
		"Monsters"
	) as Node2D

	if existing != null:
		return existing

	var created := Node2D.new()

	created.name = "Monsters"
	created.z_index = 3

	parent.add_child(created)

	return created


# ==============================
# 怪物重置
# ==============================

## R / 死亡重置时将刺怪送回出生位置。
func reset_monsters() -> void:
	for monster in _monsters:
		if is_instance_valid(monster):
			monster.call("reset_home")
