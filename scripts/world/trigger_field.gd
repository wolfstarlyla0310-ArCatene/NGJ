@tool
class_name TriggerField
extends TileMapLayer
## 无碰撞触发方块：直接用 TileMapLayer 绘制即可。
## 玩家站在触发格上时，每 `cooldown` 秒发出一次白色 3 格声场。

@export var player: EchoPlayer
@export var sound_fields: Node2D
## 触发声场边长（16px 格 × 3 = 48）。
@export var field_side_length := 48.0
@export var field_lifetime := 0.5
## 触发冷却（秒）。
@export var cooldown := 0.5
@export var field_color := Color(1.0, 1.0, 1.0, 1.0)

var _cooldown_remaining := 0.0

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or player == null or sound_fields == null:
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	var cell := local_to_map(to_local(player.global_position))
	if get_cell_source_id(cell) == -1:
		return
	if _cooldown_remaining > 0.0:
		return
	_emit_field(to_global(map_to_local(cell)))
	_cooldown_remaining = cooldown

func _emit_field(world_position: Vector2) -> void:
	var field := SoundField.new()
	field.side_length = field_side_length
	field.lifetime = field_lifetime
	field.color = field_color
	field.lethal = false
	field.safe_for_player = true
	sound_fields.add_child(field)
	field.global_position = SoundField.snap_origin_to_grid(world_position, field_side_length)
