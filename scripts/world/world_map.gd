extends Node2D
## 正式大地图根：房间几何、相机切关、存档点绑定、单房间 R、噪音死亡。

signal room_reset(room: Room)
signal checkpoint_changed(room: Room, anchor: Vector2)

const GRACE_SECONDS := 0.1
const RESET_ACTION := &"restart"

@onready var player: EchoPlayer = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var breakables: Breakables = $Breakables
@onready var noise: NoiseField = $Noise
@onready var sound_fields: Node2D = $SoundFields
@onready var rooms_root: Node2D = $Rooms
@onready var room_camera: RoomCameraController = $RoomCamera

var deaths := 0

var _checkpoint_position := Vector2.ZERO
var _checkpoint_room: Room = null
var _active_checkpoint: Checkpoint = null
var _checkpoints: Array[Checkpoint] = []
var _grace_remaining := GRACE_SECONDS

func _ready() -> void:
	process_physics_priority = 100
	player.wave_emitted.connect(_on_wave)
	player.controls_enabled = true
	_collect_checkpoints()
	room_camera.room_entered.connect(_on_room_entered)

	var start_room := _room_of(player.global_position)
	if start_room == null:
		start_room = _first_room()
	_bind_room_checkpoint(start_room, player.global_position)

func _physics_process(delta: float) -> void:
	if _touching_lethal_field():
		_die()
		return
	noise.sync_visibility(_active_sound_field_rects())
	var center := player.global_position
	if not noise.has_point(center) or _inside_active_sound_field(center):
		_grace_remaining = GRACE_SECONDS
		return
	_grace_remaining = maxf(0.0, _grace_remaining - delta)
	if _grace_remaining <= 0.0:
		_die()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(RESET_ACTION) and not event.is_echo():
		reset_to_checkpoint()

func _on_wave(origin: Vector2, side: float, level: int, _kind: String) -> void:
	var field := SoundField.new()
	field.side_length = side
	sound_fields.add_child(field)
	field.global_position = origin
	var half := Vector2(side, side) * 0.5
	breakables.break_in_rect(Rect2(origin - half, Vector2(side, side)), level)

## —— 房间 ——

func get_rooms() -> Array[Room]:
	var result: Array[Room] = []
	if rooms_root == null:
		return result
	for child in rooms_root.get_children():
		var room := child as Room
		if room != null:
			result.append(room)
	return result

func room_at(world_point: Vector2) -> Room:
	return RoomRegistry.room_at(get_rooms(), world_point)

func get_player_position() -> Vector2:
	return player.global_position

func get_room_focus_position() -> Vector2:
	return player.global_position

func get_checkpoint_room() -> Room:
	return _checkpoint_room

func get_checkpoint_anchor() -> Vector2:
	return _checkpoint_position

## —— 存档点 ——

func _collect_checkpoints() -> void:
	_checkpoints.clear()
	_walk_checkpoints(self)

func _walk_checkpoints(node: Node) -> void:
	for child in node.get_children():
		if child.has_signal(&"touched") and child.has_method(&"set_active"):
			var checkpoint := child as Checkpoint
			if checkpoint != null:
				_checkpoints.append(checkpoint)
				if not checkpoint.touched.is_connected(_on_checkpoint_touched):
					checkpoint.touched.connect(_on_checkpoint_touched)
		_walk_checkpoints(child)

func _on_room_entered(room: Room) -> void:
	if room == null or not is_instance_valid(room):
		return
	_bind_room_checkpoint(room, player.global_position)

func _on_checkpoint_touched(checkpoint: Checkpoint) -> void:
	if checkpoint == null or not is_instance_valid(checkpoint):
		return
	var room := _room_of(checkpoint.global_position)
	if room == null:
		return
	_set_checkpoint(room, checkpoint.respawn_position(), checkpoint)

func _bind_room_checkpoint(room: Room, fallback_position: Vector2) -> void:
	if room == null:
		return
	var checkpoint := _checkpoint_in_room(room)
	var anchor := fallback_position
	if checkpoint != null:
		anchor = checkpoint.respawn_position()
	_set_checkpoint(room, anchor, checkpoint)

func _set_checkpoint(room: Room, anchor: Vector2, checkpoint: Checkpoint) -> void:
	if room == null:
		return
	if room == _checkpoint_room and anchor.is_equal_approx(_checkpoint_position) and checkpoint == _active_checkpoint:
		return
	_checkpoint_room = room
	_checkpoint_position = anchor
	if _active_checkpoint != null and is_instance_valid(_active_checkpoint) and _active_checkpoint != checkpoint:
		_active_checkpoint.set_active(false)
	_active_checkpoint = checkpoint
	if _active_checkpoint != null and is_instance_valid(_active_checkpoint):
		_active_checkpoint.set_active(true)
	checkpoint_changed.emit(room, anchor)

func _checkpoint_in_room(room: Room) -> Checkpoint:
	for checkpoint in _checkpoints:
		if is_instance_valid(checkpoint) and room.contains_world_point(checkpoint.global_position):
			return checkpoint
	return null

## —— 单房间 R / 噪音死亡 ——

func reset_to_checkpoint() -> void:
	var room := _room_of(_checkpoint_position)
	if room == null:
		room = _room_of(player.global_position)
	if room == null:
		room = _first_room()
	if room != null:
		breakables.restore_rect(room.get_rect())
	for field in sound_fields.get_children():
		field.queue_free()
	noise.sync_visibility([])
	player.reset_to(_checkpoint_position)
	_grace_remaining = GRACE_SECONDS
	if room != null:
		room_reset.emit(room)

## —— 声场 ——

func _active_sound_field_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() and child.safe_for_player:
			rects.append(child.get_rect())
	return rects

func _inside_active_sound_field(point: Vector2) -> bool:
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() \
				and child.safe_for_player and child.contains_point(point):
			return true
	return false

func _touching_lethal_field() -> bool:
	var player_rect := _player_rect()
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() \
				and child.lethal and child.get_rect().intersects(player_rect):
			return true
	return false

func _player_rect() -> Rect2:
	var shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var size: Vector2 = (shape.shape as RectangleShape2D).size
		return Rect2(player.global_position - size * 0.5, size)
	return Rect2(player.global_position - Vector2(8, 8), Vector2(16, 16))

## 玩家死亡：先记下死亡位置，重置到存档点，再在原死亡位置放一个红色死亡声场（纯视觉）。
func _die() -> void:
	var death_position := player.global_position
	deaths += 1
	reset_to_checkpoint()
	_spawn_death_field(death_position)

func _spawn_death_field(world_position: Vector2) -> void:
	var field := SoundField.new()
	field.side_length = 80.0
	field.lifetime = 0.5
	field.color = Color(1.0, 0.2, 0.2, 1.0)
	field.lethal = false
	field.safe_for_player = false
	sound_fields.add_child(field)
	field.global_position = world_position

## —— 工具 ——

func _room_of(world_point: Vector2) -> Room:
	return room_at(world_point)

func _first_room() -> Room:
	var rooms := get_rooms()
	return rooms[0] if not rooms.is_empty() else null
