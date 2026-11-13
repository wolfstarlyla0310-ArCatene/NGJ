extends Area2D

signal toggled(pressed: bool)

var pressed: bool = false
var latched: bool = false
var _occupants: Array[Node2D] = []

func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

func _on_entered(body: Node2D) -> void:
	if body is EchoPlayer and not _occupants.has(body):
		_occupants.append(body)
		_update_state()

func _on_exited(body: Node2D) -> void:
	_occupants.erase(body)
	_update_state()

func _update_state() -> void:
	var value := not _occupants.is_empty()
	if value != pressed:
		pressed = value
		toggled.emit(pressed)
	queue_redraw()

func clear_contacts() -> void:
	_occupants.clear()
	pressed = false
	latched = false
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-28, -3, 56, 6), Color(0.25, 0.25, 0.25))
	var down := pressed or latched
	draw_rect(Rect2(-23, -5 if down else -10, 46, 5), Color.WHITE)
	if down:
		draw_circle(Vector2(0, -17), 3.0, Color.WHITE)
