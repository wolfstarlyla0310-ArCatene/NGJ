@tool
class_name Door
extends Area2D
## 一次性门陷阱（32×32）：吃掉接触门体的发声活物；它的红色脉冲声场接触白色声场时，
## 吃掉该白色声场的主人。吃掉后门隐藏、脉冲消失；按 R / 死亡重置存档点房间时恢复。

const SIZE := 32.0
const DOOR_COLOR := Color(0.35, 0.05, 0.08, 1.0)
const MOUTH_COLOR := Color(0.03, 0.0, 0.0, 1.0)
const WHITE_TOLERANCE := 0.9

var _consumed := false
var _aura: DoorField = null
var _sound_fields: Node2D = null

func _ready() -> void:
	add_to_group("door")
	queue_redraw()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	_spawn_aura()

func _exit_tree() -> void:
	if is_instance_valid(_aura):
		_aura.queue_free()
		_aura = null

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _consumed or not is_instance_valid(_aura):
		return
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return
	var aura_rect := _aura.get_rect()
	for child in _sound_fields.get_children():
		if not child is SoundField or child == _aura or child.is_queued_for_deletion():
			continue
		var field := child as SoundField
		if field.emitter == null or not is_instance_valid(field.emitter):
			continue
		if field.color.r < WHITE_TOLERANCE or field.color.g < WHITE_TOLERANCE or field.color.b < WHITE_TOLERANCE:
			continue
		if aura_rect.intersects(field.get_rect()):
			_eat(field.emitter)
			return

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer or body is Animal:
		_eat(body)

func _eat(creature: Node) -> void:
	if _consumed or creature == null or not is_instance_valid(creature):
		return
	if creature is EchoPlayer:
		_consume()
		var world := get_tree().get_first_node_in_group("world_map")
		if world != null and world.has_method("_die"):
			world.call("_die")
	elif creature is Animal:
		if creature.has_method("consume"):
			creature.call("consume")
		_consume()

func _consume() -> void:
	if _consumed:
		return
	_consumed = true
	visible = false
	set_deferred("monitoring", false)
	if is_instance_valid(_aura):
		_aura.queue_free()
		_aura = null
	queue_redraw()

## 世界按房间重置时调用。
func restore() -> void:
	if not _consumed:
		return
	_consumed = false
	visible = true
	set_deferred("monitoring", true)
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		_sound_fields = get_tree().get_first_node_in_group("sound_fields")
	_spawn_aura()
	queue_redraw()

func _spawn_aura() -> void:
	if _consumed or _sound_fields == null or not is_instance_valid(_sound_fields):
		return
	if is_instance_valid(_aura):
		return
	_aura = DoorField.new()
	_sound_fields.add_child(_aura)
	_aura.global_position = global_position

func _draw() -> void:
	if _consumed and not Engine.is_editor_hint():
		return
	draw_rect(Rect2(-SIZE * 0.5, -SIZE * 0.5, SIZE, SIZE), DOOR_COLOR, true)
	draw_rect(Rect2(-12, -10, 24, 8), MOUTH_COLOR, true)
