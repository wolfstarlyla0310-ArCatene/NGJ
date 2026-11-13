extends Node2D

signal rung

@export var activation_radius: float = 30.0
var eye: WallEye
var enabled: bool = false
var activated: bool = false
var _vibration: float = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if enabled and not activated and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		try_ring()

func try_ring() -> bool:
	if not enabled or activated or eye == null or eye.global_position.distance_to(global_position) > activation_radius:
		return false
	activated = true
	_vibration = 1.0
	rung.emit()
	return true

func _process(delta: float) -> void:
	_vibration = maxf(0.0, _vibration - delta)
	rotation = sin(Time.get_ticks_msec() * 0.05) * _vibration * 0.18
	queue_redraw()

func reset_bell() -> void:
	activated = false
	_vibration = 0.0
	rotation = 0.0
	queue_redraw()

func _draw() -> void:
	var ink := Color.BLACK
	draw_arc(Vector2(0, -3), 13.0, PI, TAU, 28, ink, 2.0, true)
	draw_line(Vector2(-13, -3), Vector2(-17, 14), ink, 2.0, true)
	draw_line(Vector2(13, -3), Vector2(17, 14), ink, 2.0, true)
	draw_line(Vector2(-17, 14), Vector2(17, 14), ink, 2.0, true)
	draw_circle(Vector2(0, 20), 3.0, ink)
	draw_circle(Vector2(0, -21), 2.5, ink)
	if not activated:
		draw_arc(Vector2.ZERO, activation_radius, 0.0, TAU, 48, Color(0, 0, 0, 0.2), 1.0, true)
