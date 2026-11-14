@tool
class_name SpikeField
extends TileMapLayer
## 刺图格：图块本身透明（无贴图），按周期从每个刺格发射 3 个红色致命短声场。
## 直接用 TileMapLayer 画笔绘制 `spike_tileset.tres` 的 0:0 透明格即可。

@export var sound_fields: Node2D
@export var breakables: Breakables
## 刺声场边长（16px 格 × 3 = 48）。
@export var field_side_length := 48.0
## 单个刺声场存在时间（秒）。
@export var field_lifetime := 0.2
## 每轮连发数量。
@export var burst_count := 3
## 连发间隔（秒）。
@export var burst_interval := 0.1
## 两轮之间的间隔（秒）。
@export var cycle_interval := 1.0
@export var field_color := Color(1.0, 0.2, 0.2, 1.0)
## 刺声场震碎的玻璃等级；0 = 不震碎玻璃（lv0）。
@export var glass_level := 0

const TILE_SIZE := 16.0

var _cycle_elapsed := 0.0
var _burst_left := 0
var _burst_timer := 0.0
## 初始刺格快照：cell -> [source_id, atlas, alternative]；用于随房间重置恢复。
var _baseline: Dictionary = {}

func _ready() -> void:
	# 编辑器里显示红色刺图块方便绘制；运行时图格本身不可见，只留下发出的声场。
	visible = Engine.is_editor_hint()
	if Engine.is_editor_hint():
		return
	refresh_baseline()

## 重新记录当前所有刺格（测试/运行时动态绘制后调用）。
func refresh_baseline() -> void:
	_baseline.clear()
	for cell in get_used_cells():
		_baseline[cell] = [
			get_cell_source_id(cell),
			get_cell_atlas_coords(cell),
			get_cell_alternative_tile(cell),
		]

## 擦除与 area 相交的刺格；擦除后它们不再参与后续连发。
func destroy_in_rect(area: Rect2) -> void:
	for cell in get_used_cells():
		if _cell_rect(cell).intersects(area):
			erase_cell(cell)

## 把 area 内的刺格恢复到初始快照（随存档点房间重置）。
func restore_rect(area: Rect2) -> void:
	for cell in get_used_cells():
		if _cell_rect(cell).intersects(area):
			erase_cell(cell)
	for cell in _baseline:
		if _cell_rect(cell).intersects(area):
			var data: Array = _baseline[cell]
			set_cell(cell, int(data[0]), data[1], int(data[2]))

func _cell_rect(cell: Vector2i) -> Rect2:
	var center := to_global(map_to_local(cell))
	return Rect2(center - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, Vector2(TILE_SIZE, TILE_SIZE))

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_emit_burst_wave()
			_burst_left -= 1
			_burst_timer = burst_interval
	_cycle_elapsed += delta
	if _cycle_elapsed >= cycle_interval and _burst_left == 0:
		_cycle_elapsed = 0.0
		_burst_left = burst_count
		_burst_timer = 0.0

## 对当前画着的每个刺格各发射一个短声场。
func _emit_burst_wave() -> void:
	if sound_fields == null or not is_instance_valid(sound_fields):
		return
	for cell in get_used_cells():
		_spawn_field(to_global(map_to_local(cell)))

func _spawn_field(world_position: Vector2) -> void:
	var field := SoundField.new()
	field.side_length = field_side_length
	field.lifetime = field_lifetime
	field.color = field_color
	field.lethal = true
	field.safe_for_player = false
	sound_fields.add_child(field)
	field.global_position = world_position
	if breakables != null and is_instance_valid(breakables):
		var half := Vector2(field_side_length, field_side_length) * 0.5
		breakables.break_in_rect(Rect2(world_position - half, Vector2(field_side_length, field_side_length)), glass_level)
