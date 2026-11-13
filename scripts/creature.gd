extends Node2D
## Deliberately has no sprite: motion is perceived through sound waves only.

signal sound_emitted(origin: Vector2, strength: float)

@export var patrol_width: float = 160.0
@export var speed: float = 48.0
@export var step_interval: float = 0.7

var active: bool = false
var debug_visible: bool = false
var _origin := Vector2.ZERO
var _direction: float = 1.0
var _sound_timer: float = 0.2

func _ready() -> void:
	_origin = position

func _physics_process(delta: float) -> void:
	if not active:
		return
	position.x += speed * _direction * delta
	if position.x >= _origin.x + patrol_width:
		position.x = _origin.x + patrol_width
		_direction = -1.0
	elif position.x <= _origin.x:
		position.x = _origin.x
		_direction = 1.0
	_sound_timer -= delta
	if _sound_timer <= 0:
		_sound_timer = step_interval
		sound_emitted.emit(global_position, 0.82)
	queue_redraw()

func reset_motion() -> void:
	position = _origin
	_direction = 1.0
	_sound_timer = 0.2

func _draw() -> void:
	if debug_visible:
		draw_circle(Vector2(0, -10), 10.0, Color.WHITE)
