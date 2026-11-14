class_name NoiseField
extends TileMapLayer
## Painted red cells define the noise area. A cell is hidden only when a single active
## sound field fully encloses it; partial overlap leaves it visible. Hidden cells are
## still lethal.

const DEFAULT_TILE_SIZE := Vector2(16.0, 16.0)

var _painted: Dictionary = {}  # cell -> {source, atlas, alternative}
var _hidden: Dictionary = {}

func _ready() -> void:
	refresh()

func refresh() -> void:
	_restore_all()
	_painted.clear()
	for cell in get_used_cells():
		_painted[cell] = {
			"source": get_cell_source_id(cell),
			"atlas": get_cell_atlas_coords(cell),
			"alternative": get_cell_alternative_tile(cell),
		}

func has_point(world_point: Vector2) -> bool:
	return _painted.has(local_to_map(to_local(world_point)))

## 玩家身体矩形是否接触任意噪音格；隐藏的格子仍然致命。
func touches_rect(world_rect: Rect2) -> bool:
	var top_left := local_to_map(to_local(world_rect.position))
	var bottom_right := local_to_map(to_local(world_rect.end - Vector2(0.01, 0.01)))
	for x in range(mini(top_left.x, bottom_right.x), maxi(top_left.x, bottom_right.x) + 1):
		for y in range(mini(top_left.y, bottom_right.y), maxi(top_left.y, bottom_right.y) + 1):
			if _painted.has(Vector2i(x, y)):
				return true
	return false

func sync_visibility(pulse_rects: Array[Rect2]) -> void:
	# 只遍历每个声场矩形覆盖到的格子，避免每物理帧扫描整张噪音图。
	var covered: Dictionary = {}
	for area in pulse_rects:
		var a := local_to_map(to_local(area.position))
		var b := local_to_map(to_local(area.end))
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
				var cell := Vector2i(x, y)
				# 只有被单个声场完整包住（含边线）的已绘制格子才隐藏。
				if _painted.has(cell) and area.encloses(_cell_rect(cell)):
					covered[cell] = true
	for cell in covered:
		if not _hidden.has(cell):
			erase_cell(cell)
			_hidden[cell] = true
	for cell in _hidden.keys():
		if not covered.has(cell):
			var data: Dictionary = _painted[cell]
			set_cell(cell, int(data["source"]), data["atlas"], int(data["alternative"]))
			_hidden.erase(cell)

func _cell_rect(cell: Vector2i) -> Rect2:
	var size := DEFAULT_TILE_SIZE
	if tile_set != null:
		size = Vector2(tile_set.tile_size)
	var center := to_global(map_to_local(cell))
	return Rect2(center - size * 0.5, size)

func is_cell_hidden(cell: Vector2i) -> bool:
	return _hidden.has(cell)

func paint_cells(cells: Array[Vector2i]) -> void:
	_restore_all()
	for cell in cells:
		set_cell(cell, 0, Vector2i(0, 0))
	refresh()

func clear_all() -> void:
	clear()
	_painted.clear()
	_hidden.clear()

func _restore_all() -> void:
	for cell in _hidden:
		var data: Dictionary = _painted[cell]
		set_cell(cell, int(data["source"]), data["atlas"], int(data["alternative"]))
	_hidden.clear()
