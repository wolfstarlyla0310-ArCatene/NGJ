@tool
class_name BarrierField
extends TileMapLayer
## 声场显形屏障：平时以 20% 透明度显示、无碰撞；被任意声场覆盖时立即完整显形并挡住玩家。
## 声场消失后延迟 `hide_delay` 秒再回到 20% 透明状态。图集自带物理层，显形即拥有碰撞。

@export var sound_fields: Node2D
## 声场消失后保持完整显形的时间（秒）；比旧版多 1 秒。
@export var hide_delay := 1.2

const TILE_SIZE := 16.0
const GHOST_ALPHA := 0.2

## cell -> [source_id, atlas, alternative]
var _baseline: Dictionary = {}
## cell -> 剩余隐去时间
var _hide_timers: Dictionary = {}
## 始终显示基线屏障格的 20% 透明度背景层；完整屏障层叠在它上面。
var _ghost: TileMapLayer = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	refresh_baseline()

func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
		_ghost = null

## 记录当前所有屏障格，然后清空主层（无碰撞），并同步 20% 透明背景层。
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
	_sync_ghost()

## 创建/刷新 20% 透明背景层（位于主屏障层下方）。
func _sync_ghost() -> void:
	if Engine.is_editor_hint():
		return
	var created := false
	if _ghost == null or not is_instance_valid(_ghost):
		_ghost = TileMapLayer.new()
		_ghost.name = "Ghost"
		_ghost.tile_set = tile_set
		_ghost.collision_enabled = false
		_ghost.z_index = z_index
		_ghost.modulate = Color(1.0, 1.0, 1.0, GHOST_ALPHA)
		created = true
	_ghost.clear()
	for cell in _baseline:
		var data: Array = _baseline[cell]
		_ghost.set_cell(cell, int(data[0]), data[1], int(data[2]))
	if created:
		# 场景加载期间父节点可能正在 setup children，延迟插入。
		call_deferred("_add_ghost_deferred")

func _add_ghost_deferred() -> void:
	if _ghost == null or not is_instance_valid(_ghost) or _ghost.get_parent() != null:
		return
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(_ghost)
	parent.move_child(_ghost, get_index())

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
