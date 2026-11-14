extends Node2D
## 正式大地图根：房间几何、相机切关、存档点绑定、单房间 R、噪音死亡。

signal room_reset(room: Room)
signal checkpoint_changed(room: Room, anchor: Vector2)

const GRACE_SECONDS := 0.5
const RESET_ACTION := &"restart"

## 可选：游戏开始时从哪个房间开始。留空则使用玩家在场景里的初始房间。
## 设置后玩家会被放到该房间的 Checkpoint（没有则房间中心），并绑定该存档点。
@export var start_room: Room

@onready var player: EchoPlayer = $Player
@onready var terrain: TileMapLayer = $Terrain
@onready var breakables: Breakables = $Breakables
@onready var noise: NoiseField = $Noise
@onready var spikes: SpikeField = $Spikes
@onready var sound_fields: Node2D = $SoundFields
@onready var rooms_root: Node2D = $Rooms
@onready var room_camera: RoomCameraController = $RoomCamera
@onready var puzzle_door_manager: PuzzleDoorManager = get_node_or_null("DoorManager") as PuzzleDoorManager

var deaths := 0

var _checkpoint_position := Vector2.ZERO
var _checkpoint_room: Room = null
var _active_checkpoint: Checkpoint = null
var _checkpoints: Array[Checkpoint] = []
var _grace_remaining := GRACE_SECONDS
## 当前按房间裁剪所依据的玩家房间；房间不变时不做任何遍历。
var _culled_room: Room = null

func _ready() -> void:
	process_physics_priority = 100
	add_to_group("world_map")
	player.wave_emitted.connect(_on_wave)
	player.controls_enabled = true
	_collect_checkpoints()

	var explicit_start := _is_explicit_start_room()
	var spawn_room: Room = start_room if explicit_start else _room_of(player.global_position)
	if spawn_room == null:
		spawn_room = _first_room()
	# 存档点必须实际接触才更新；开局只记录出生点/起始锚点作为回退。
	if explicit_start and spawn_room != null:
		var anchor := _spawn_anchor(spawn_room)
		player.reset_to(anchor)
		_set_checkpoint(spawn_room, anchor, null)
	else:
		_set_checkpoint(spawn_room, player.global_position, null)
	if puzzle_door_manager != null:
		puzzle_door_manager.setup(get_rooms())
	_update_room_culling(true)

func _is_explicit_start_room() -> bool:
	return start_room != null and is_instance_valid(start_room) \
		and rooms_root != null and rooms_root.is_ancestor_of(start_room)

func _spawn_anchor(room: Room) -> Vector2:
	var checkpoint := _checkpoint_in_room(room)
	if checkpoint != null:
		return checkpoint.respawn_position()
	return room.get_rect().get_center()

func _physics_process(delta: float) -> void:
	_update_room_culling()
	var player_rect := _player_rect()
	if _touching_lethal_field(player_rect) or spikes.touches_rect(player_rect):
		_die()
		return
	noise.sync_visibility(_active_sound_field_rects())
	var center := player.global_position
	# 身体任意部分碰到噪音就开始 0.5 秒冷却；中心在安全声场内时重置冷却。
	if not noise.touches_rect(player_rect) or _inside_active_sound_field(center):
		_grace_remaining = GRACE_SECONDS
		return
	_grace_remaining = maxf(0.0, _grace_remaining - delta)
	if _grace_remaining <= 0.0:
		_die()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(RESET_ACTION) and not event.is_echo():
		reset_to_checkpoint()

func _on_wave(origin: Vector2, side: float, level: int, _kind: String) -> void:
	var snapped_origin := SoundField.snap_origin_to_grid(origin, side)
	var field := SoundField.new()
	field.side_length = side
	field.level = level
	field.emitter = player
	field.color = SoundField.color_for_level(level)
	if level == 2:
		field.lifetime = SoundField.LV2_LIFETIME  # lv2 持续 2 秒
	sound_fields.add_child(field)
	field.global_position = snapped_origin
	var half := Vector2(side, side) * 0.5
	var area := Rect2(snapped_origin - half, Vector2(side, side))
	breakables.break_in_rect(area, level)
	if level == 2:
		spikes.destroy_in_rect(area)

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

func _on_checkpoint_touched(checkpoint: Checkpoint) -> void:
	if checkpoint == null or not is_instance_valid(checkpoint):
		return
	var room := _room_of(checkpoint.global_position)
	if room == null:
		return
	_set_checkpoint(room, checkpoint.respawn_position(), checkpoint)

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
		spikes.restore_rect(room.get_rect())
	for field in sound_fields.get_children():
		if field is SoundField and not field.persistent:
			field.queue_free()
	noise.sync_visibility([])
	player.reset_to(_checkpoint_position)
	_culled_room = null
	_update_room_culling(true)
	_grace_remaining = GRACE_SECONDS
	if room != null:
		for door in get_tree().get_nodes_in_group("door"):
			if door is Node2D and room.contains_world_point((door as Node2D).global_position) \
					and door.has_method("restore"):
				door.call("restore")
		if puzzle_door_manager != null:
			puzzle_door_manager.reset_room(room)
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

func _touching_lethal_field(player_rect: Rect2) -> bool:
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() \
				and child.lethal and child.get_rect().intersects(player_rect):
			return true
	return false

func _player_rect() -> Rect2:
	var shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var size: Vector2 = (shape.shape as RectangleShape2D).size
		return Rect2(shape.global_position - size * 0.5, size)
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

## —— 房间裁剪：只让玩家房间 + 上下左右相邻房间里的物体参与处理/渲染 ——

func _update_room_culling(force := false) -> void:
	var here := _room_of(player.global_position)
	if here == null:
		# 站在房间缝隙里：保持上一次的 active 集合，避免边界闪烁。
		return
	if not force and here == _culled_room:
		return
	_culled_room = here
	var active_rooms := RoomRegistry.orthogonal_neighbors(get_rooms(), here)
	active_rooms.append(here)
	var managed: Array[Node] = []
	for container_name in ["Objects", "Animals", "Buttons"]:
		var container := get_node_or_null(container_name)
		if container != null:
			_collect_managed_nodes(container, managed)
	for node in managed:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var node_2d := node as Node2D
		if node_2d == null:
			continue
		var node_room := _room_of(node_2d.global_position)
		var active := node_room == null or active_rooms.has(node_room)
		node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if node is CanvasItem:
			(node as CanvasItem).visible = active
		if node is Checkpoint:
			(node as Checkpoint).set_deferred("monitoring", active)

func _collect_managed_nodes(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Checkpoint or child is Animal or child is DoorButton:
			out.append(child)
		_collect_managed_nodes(child, out)

func _first_room() -> Room:
	var rooms := get_rooms()
	return rooms[0] if not rooms.is_empty() else null
