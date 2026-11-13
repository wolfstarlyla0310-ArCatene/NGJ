@tool
class_name WallPlatform
extends AnimatableBody2D
## Solid tile block: TileMapLayer supplies visuals; one rectangle supplies collision.

const TILE_SIZE: float = 32.0

@export var tiles_wide: int = 8:
	set(value):
		tiles_wide = maxi(value, 1)
		if is_node_ready():
			_rebuild()
@export var tiles_high: int = 4:
	set(value):
		tiles_high = maxi(value, 1)
		if is_node_ready():
			_rebuild()

@onready var tiles: TileMapLayer = $Tiles
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	tiles.clear()
	for x in range(tiles_wide):
		for y in range(tiles_high):
			var atlas_x: int = 0 if y == 0 else (2 if y == tiles_high - 1 else 1)
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(atlas_x, 0))
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(tiles_wide, tiles_high) * TILE_SIZE
	collision.shape = rectangle
	collision.position = rectangle.size * 0.5

func bounds() -> Rect2:
	return Rect2(global_position, Vector2(tiles_wide, tiles_high) * TILE_SIZE)
