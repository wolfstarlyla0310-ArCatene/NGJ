@tool
class_name BarrierField
extends TileMapLayer
## 声场显形屏障：平时不可见、无碰撞；被任意声场覆盖时立即显形并挡住玩家。
## 声场消失后延迟 `hide_delay` 秒再隐去。图集自带物理层，显形即拥有碰撞。

@export var sound_fields: Node2D
## 声场消失后保持显形的时间（秒）。
@export var hide_delay := 0.2

const TILE_SIZE := 16.0

## cell -> [source_id, atlas, alternative]
var _baseline: Dictionary = {}
## cell -> 剩余隐去时间
var _hide_timers: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	refresh_baseline()

## 记录当前所有屏障格，然后清空，让它们初始处于隐藏/无碰撞状态。
func refresh_baseline() -> void:
	_baseline.clear()
	for cell in get_used_cells():
		_baseline[cell] = [
			get_cell_source_id(cell),
			get_cell_atlas_coords(cell),
			get_cell_alternative_tile(cell),
		]
	clear()
	_hide_timers.clear()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or sound_fields == null:
		return
	for cell in _baseline:
		var covered := _covered_by_field(_cell_rect(cell))
		var shown := get_cell_source_id(cell) != -1
		if covered:
			_hide_timers.erase(cell)
			if not shown:
				var data: Array = _baseline[cell]
				set_cell(cell, int(data[0]), data[1], int(data[2]))
		elif shown:
			var remaining: float = float(_hide_timers.get(cell, hide_delay)) - delta
			if remaining <= 0.0:
				erase_cell(cell)
				_hide_timers.erase(cell)
			else:
				_hide_timers[cell] = remaining

func _covered_by_field(rect: Rect2) -> bool:
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() and child.get_rect().intersects(rect):
			return true
	return false

func _cell_rect(cell: Vector2i) -> Rect2:
	var center := to_global(map_to_local(cell))
	return Rect2(center - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, Vector2(TILE_SIZE, TILE_SIZE))
