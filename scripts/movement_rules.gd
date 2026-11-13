class_name MovementRules
extends Resource
## Shared grid, fixed click strength, and designer-editable landing rebound tiers.

@export var tile_size: float = 32.0
@export var fall_thresholds_tiles := PackedFloat32Array([2.0, 4.0, 8.0])
@export var rebound_heights_tiles := PackedFloat32Array([1.0, 2.0, 4.0])
@export var wave_jump_height_tiles: float = 5.0
@export var contact_tolerance_pixels: float = 0.25

func cell_at(point: Vector2, origin: Vector2 = Vector2.ZERO) -> Vector2i:
	return Vector2i(floori((point.x - origin.x) / tile_size), floori((point.y - origin.y) / tile_size))

func cell_center(cell: Vector2i, origin: Vector2 = Vector2.ZERO) -> Vector2:
	return origin + (Vector2(cell) + Vector2.ONE * 0.5) * tile_size

func cardinal_direction(source: Vector2, target: Vector2, origin: Vector2 = Vector2.ZERO) -> Vector2:
	var difference := cell_at(target, origin) - cell_at(source, origin)
	if difference.x == 0 and difference.y != 0:
		return Vector2(0, signi(difference.y))
	if difference.y == 0 and difference.x != 0:
		return Vector2(signi(difference.x), 0)
	return Vector2.ZERO

func rebound_tier(drop_pixels: float) -> int:
	var count := mini(fall_thresholds_tiles.size(), rebound_heights_tiles.size())
	for i in range(count - 1, -1, -1):
		if drop_pixels + contact_tolerance_pixels >= fall_thresholds_tiles[i] * tile_size:
			return i + 1
	return 0

func rebound_height_pixels(tier: int) -> float:
	if tier <= 0 or tier > rebound_heights_tiles.size():
		return 0.0
	return rebound_heights_tiles[tier - 1] * tile_size

func launch_speed(height_pixels: float, gravity: float) -> float:
	if height_pixels <= 0.0:
		return 0.0
	# Semi-implicit Euler applies gravity before movement; compensate half a physics step.
	return sqrt(2.0 * gravity * height_pixels) + gravity / (2.0 * Engine.physics_ticks_per_second)
