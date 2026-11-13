class_name NoiseField
extends TileMapLayer
## Painted red cells define the noise area. Cells covered by an active white frame are hidden.

const DEMO_MIN := Vector2i(20, 12)
const DEMO_SIZE := Vector2i(2, 5)

var _painted: Dictionary = {}  # cell -> {source, atlas, alternative}
var _hidden: Dictionary = {}

func _ready() -> void:
	if get_used_cells().is_empty():
		for x in range(DEMO_MIN.x, DEMO_MIN.x + DEMO_SIZE.x):
			for y in range(DEMO_MIN.y, DEMO_MIN.y + DEMO_SIZE.y):
				set_cell(Vector2i(x, y), 0, Vector2i(0, 0))
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

func sync_visibility(pulse_rects: Array[Rect2]) -> void:
	for cell in _painted:
		var center := to_global(map_to_local(cell))
		var cell_rect := Rect2(center - Vector2(16, 16), Vector2(32, 32))
		var covered := false
		for area in pulse_rects:
			if area.intersects(cell_rect, true):
				covered = true
				break
		if covered and not _hidden.has(cell):
			erase_cell(cell)
			_hidden[cell] = true
		elif not covered and _hidden.has(cell):
			var data: Dictionary = _painted[cell]
			set_cell(cell, int(data["source"]), data["atlas"], int(data["alternative"]))
			_hidden.erase(cell)

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
