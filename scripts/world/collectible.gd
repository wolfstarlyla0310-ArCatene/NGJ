class_name Collectible
extends Area2D
## 收集品：没有物理阻挡，玩家接触后立刻被收集并消失；贴图缓慢旋转。

signal collected(collectible: Collectible)

## 贴图旋转速度（弧度/秒）。
@export var spin_speed := 0.8

@export_group("脉冲")
## 纯视觉脉冲边长（格）；2 格 = 32px。
@export_range(0.5, 8.0, 0.5) var pulse_side_cells := 2.0
## 两次脉冲的间隔（秒）。
@export var pulse_interval := 1.2
## 单个脉冲的寿命（秒）。
@export var pulse_lifetime := 0.6
## 脉冲从中心扩散到目标边长的时间（秒）。
@export var pulse_expand_duration := 0.45
## 脉冲颜色；默认半透明白。
@export var pulse_color := Color(1.0, 1.0, 1.0, 0.4)

var _pulse_elapsed := 0.0

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	add_to_group("collectible")
	collision_layer = 0
	collision_mask = 2      # 只检测玩家层
	monitorable = false
	body_entered.connect(_on_body_entered)
	_spawn_pulse()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _sprite != null:
		_sprite.rotation += spin_speed * delta

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or is_queued_for_deletion():
		return
	_pulse_elapsed += delta
	if _pulse_elapsed < maxf(pulse_interval, 0.001):
		return
	_pulse_elapsed = fmod(_pulse_elapsed, maxf(pulse_interval, 0.001))
	_spawn_pulse()

## 纯视觉脉冲：挂在收集品下面，不进 SoundFields 容器，也不参与任何判定。
func _spawn_pulse() -> void:
	var pulse := SoundField.new()
	pulse.side_length = pulse_side_cells * SoundField.TILE_SIZE
	pulse.lifetime = pulse_lifetime
	pulse.expand_duration = pulse_expand_duration
	pulse.color = pulse_color
	pulse.level = 0
	pulse.lethal = false
	pulse.safe_for_player = false
	pulse.emitter = null
	add_child(pulse)
	pulse.position = Vector2.ZERO

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer:
		collected.emit(self)
		body.play_pickup_sound()
		queue_free()
