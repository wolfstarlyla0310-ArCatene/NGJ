class_name Breakables
extends Node2D
## Painted tile layers become solid cells at runtime; same-level waves erase them.

const TILE_SIZE := 32
const DEMO_LV1: Array[Vector2i] = [Vector2i(17, 16), Vector2i(18, 16)]
const DEMO_LV2: Array[Vector2i] = [Vector2i(15, 13)]

@onready var lv1: TileMapLayer = $Lv1
@onready var lv2: TileMapLayer = $Lv2

var _baseline: Dictionary = {1: {}, 2: {}}
var _bodies: Dictionary = {1: {}, 2: {}}

func _ready() -> void:
	if lv1.get_used_cells().is_empty() and lv2.get_used_cells().is_empty():
		for cell in DEMO_LV1:
			lv1.set_cell(cell, 0, Vector2i(0, 0))
		for cell in DEMO_LV2:
			lv2.set_cell(cell, 0, Vector2i(0, 0))
	refresh()

func refresh() -> void:
	_clear_bodies()
	_baseline = {1: {}, 2: {}}
	for wave_level in [1, 2]:
		var layer := _layer(wave_level)
		var snapshot: Dictionary = {}
		for cell in layer.get_used_cells():
			snapshot[cell] = {
				"source": layer.get_cell_source_id(cell),
				"atlas": layer.get_cell_atlas_coords(cell),
				"alternative": layer.get_cell_alternative_tile(cell),
			}
		_baseline[wave_level] = snapshot
	_spawn_all_bodies()

func break_in_rect(area: Rect2, wave_level: int) -> void:
	if wave_level < 1 or wave_level > 2:
		return
	var layer := _layer(wave_level)
	var bodies: Dictionary = _bodies[wave_level]
	for cell in layer.get_used_cells():
		var body: StaticBody2D = bodies.get(cell)
		if not is_instance_valid(body):
			continue
		var cell_rect := Rect2(body.global_position - Vector2(TILE_SIZE, TILE_SIZE) * 0.5, Vector2(TILE_SIZE, TILE_SIZE))
		if not area.intersects(cell_rect, true):
			continue
		layer.erase_cell(cell)
		body.collision_layer = 0
		body.queue_free()
		bodies.erase(cell)

func reset() -> void:
	_clear_bodies()
	for wave_level in [1, 2]:
		var layer := _layer(wave_level)
		layer.clear()
		var snapshot: Dictionary = _baseline[wave_level]
		for cell in snapshot:
			var data: Dictionary = snapshot[cell]
			layer.set_cell(cell, int(data["source"]), data["atlas"], int(data["alternative"]))
	_spawn_all_bodies()

func clear_all() -> void:
	_clear_bodies()
	lv1.clear()
	lv2.clear()
	_baseline = {1: {}, 2: {}}

func paint_cell(wave_level: int, cell: Vector2i) -> void:
	_layer(wave_level).set_cell(cell, 0, Vector2i(0, 0))

func has_cell(wave_level: int, cell: Vector2i) -> bool:
	if wave_level < 1 or wave_level > 2:
		return false
	return _layer(wave_level).get_used_cells().has(cell)

func _layer(wave_level: int) -> TileMapLayer:
	return lv1 if wave_level == 1 else lv2

func _clear_bodies() -> void:
	for wave_level in [1, 2]:
		for body in _bodies[wave_level].values():
			if is_instance_valid(body):
				body.collision_layer = 0
				body.queue_free()
	_bodies = {1: {}, 2: {}}

func _spawn_all_bodies() -> void:
	for wave_level in [1, 2]:
		var layer := _layer(wave_level)
		var bodies: Dictionary = _bodies[wave_level]
		for cell in layer.get_used_cells():
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(TILE_SIZE, TILE_SIZE)
			shape.shape = rectangle
			body.add_child(shape)
			add_child(body)
			body.global_position = layer.to_global(layer.map_to_local(cell))
			bodies[cell] = body
