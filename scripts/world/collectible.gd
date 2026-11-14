class_name Collectible
extends Area2D
## 收集品：没有物理阻挡，玩家接触后立刻被收集并消失；贴图缓慢旋转。

signal collected(collectible: Collectible)

## 贴图旋转速度（弧度/秒）。
@export var spin_speed := 0.8

@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D

func _ready() -> void:
	add_to_group("collectible")
	collision_layer = 0
	collision_mask = 2      # 只检测玩家层
	monitorable = false
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _sprite != null:
		_sprite.rotation += spin_speed * delta

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer:
		collected.emit(self)
		queue_free()
