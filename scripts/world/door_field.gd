class_name DoorField
extends SoundField
## 门的红色脉冲声场：持续存在，大小在 min/max 之间缓慢变化，透明度随之变化。
## 它是 persistent 声场，世界重置不会清理；门被吃掉时由门释放。

@export var min_side := 16.0
@export var max_side := 48.0
@export var pulse_period := 2.0
@export var alpha_min := 0.15
@export var alpha_max := 0.75

var _pulse_time := 0.0
var _pulse := 0.0

func _ready() -> void:
	persistent = true
	lethal = false
	safe_for_player = false
	level = 0
	color = Color(1.0, 0.2, 0.2, 1.0)
	side_length = min_side
	current_side = min_side
	queue_redraw()

func _physics_process(delta: float) -> void:
	_pulse_time += delta
	_pulse = 0.5 + 0.5 * sin(TAU * _pulse_time / maxf(pulse_period, 0.001))
	var side := lerpf(min_side, max_side, _pulse)
	side_length = side
	current_side = side
	queue_redraw()

func _draw() -> void:
	var alpha := lerpf(alpha_min, alpha_max, _pulse)
	_draw_pixel_square(Color(color.r, color.g, color.b, alpha))
