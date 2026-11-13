@tool
class_name WallPlatform
extends AnimatableBody2D
## All solids share this scene. TileMapLayer supplies visuals; one rectangle supplies collision.

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
@export var travel_offset := Vector2.ZERO
@export var travel_speed: float = 150.0
@export var dock_wait: float = 1.8

var paused: bool = false
var origin := Vector2.ZERO
var last_displacement := Vector2.ZERO
var _target_is_far: bool = true
var _wait_remaining: float = 0.0

@onready var tiles: TileMapLayer = $Tiles
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	origin = position
	_wait_remaining = dock_wait
	process_physics_priority = -100
	add_to_group("walls")

func _rebuild() -> void:
	# Show editable tiles in the editor; gameplay keeps the shared, hidden-fill material.
	var vision_material: ShaderMaterial = preload("res://resources/vision_material.tres")
	if Engine.is_editor_hint():
		vision_material = vision_material.duplicate()
		vision_material.set_shader_parameter("debug_visible", true)
	tiles.material = vision_material
	tiles.clear()
	for x in range(tiles_wide):
		for y in range(tiles_high):
			var atlas_x: int = 0 if y == 0 else (2 if y == tiles_high - 1 else 1)
			tiles.set_cell(Vector2i(x, y), 0, Vector2i(atlas_x, 0))
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(tiles_wide, tiles_high) * 32.0
	collision.shape = rectangle
	collision.position = rectangle.size * 0.5

func _physics_process(delta: float) -> void:
	last_displacement = Vector2.ZERO
	if paused or travel_offset.is_zero_approx():
		return
	if _wait_remaining > 0.0:
		_wait_remaining -= delta
		return
	var target: Vector2 = origin + travel_offset if _target_is_far else origin
	var previous := position
	position = position.move_toward(target, travel_speed * delta)
	last_displacement = position - previous
	if position.is_equal_approx(target):
		_target_is_far = not _target_is_far
		_wait_remaining = dock_wait

func bounds() -> Rect2:
	return Rect2(global_position, Vector2(tiles_wide, tiles_high) * 32.0)

func reset_motion() -> void:
	position = origin
	last_displacement = Vector2.ZERO
	_target_is_far = true
	_wait_remaining = dock_wait
	reset_physics_interpolation()
