class_name ForcePulse
extends Node2D
## Purely visual white square. It appears at full size and fades out.

@export var side_length: float = 96.0
@export var lifetime: float = 0.5
@export var line_width: float = 2.0

var age: float = 0.0

func _physics_process(delta: float) -> void:
	age += delta
	if age >= lifetime:
		queue_free()
	else:
		queue_redraw()

func contains_point(world_point: Vector2) -> bool:
	var half := side_length * 0.5
	return (
		world_point.x >= global_position.x - half and world_point.x <= global_position.x + half
		and world_point.y >= global_position.y - half and world_point.y <= global_position.y + half
	)

func _draw() -> void:
	var alpha := clampf(1.0 - age / lifetime, 0.0, 1.0)
	var half := side_length * 0.5
	draw_rect(Rect2(-half, -half, side_length, side_length), Color(1, 1, 1, alpha), false, line_width, true)
