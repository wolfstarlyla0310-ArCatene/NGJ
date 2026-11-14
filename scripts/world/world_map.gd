extends Node2D
## 正式大地图根：房间几何、相机切关、存档点绑定、单房间 R、噪音死亡。

signal room_reset(room: Room)
signal checkpoint_changed(room: Room, anchor: Vector2)

const RESET_ACTION := &"restart"

## 玩家接触噪音格且不在安全声场内时，多久后死亡（秒）。检查器可调。
@export var noise_grace_seconds := 0.3

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
var _grace_remaining := 0.0
## 当前按房间裁剪所依据的玩家房间；房间不变时不做任何遍历。
var _culled_room: Room = null
## 死亡后停在原地，等玩家按 R 才重置。
var _dead := false

func _ready() -> void:
	process_physics_priority = 100
	_grace_remaining = noise_grace_seconds
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
	# 死亡后停在原地，等待 R 键重置；不再重复判定危险。
	if _dead:
		return
	var player_rect := _player_rect()
	if _touching_lethal_field(player_rect):
		_die()
		return
	noise.sync_visibility(_active_sound_field_rects())
	var center := player.global_position
	# 身体任意部分碰到噪音就开始冷却；中心在安全声场内时重置冷却。
	if not noise.touches_rect(player_rect) or _inside_active_sound_field(center):
		_grace_remaining = noise_grace_seconds
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
	_dead = false
	player.controls_enabled = true
	player.visible = true
	var room := _room_of(_checkpoint_position)
	if room == null:
		room = _room_of(player.global_position)
	if room == null:
		room = _first_room()
	if room != null:
		breakables.restore_rect(room.get_rect())
	spikes.reset_monsters()
	for field in sound_fields.get_children():
		if field is SoundField and not field.persistent:
			field.queue_free()
	noise.sync_visibility([])
	player.reset_to(_checkpoint_position)
	_culled_room = null
	_update_room_culling(true)
	for animal in get_tree().get_nodes_in_group("animal"):
		if animal.has_method("reset_home"):
			animal.call("reset_home")
	_grace_remaining = noise_grace_seconds
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
	if _dead:
		return
	_dead = true
	deaths += 1
	player.controls_enabled = false
	player.velocity = Vector2.ZERO
	player.visible = false
	_spawn_death_field(player.global_position)

func is_dead() -> bool:
	return _dead

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
	var previous := _culled_room
	_culled_room = here
	_rebase_animals_in_room(here)
	if previous != null and not force:
		_refresh_rooms_left(previous, here)
	var active_rooms := _active_rooms(here)
	var managed: Array[Node] = []
	for container_name in ["Objects", "Animals", "Buttons", "Collectibles", "Monsters"]:
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
			var alive := not (node is Animal) or (node as Animal).is_alive()
			(node as CanvasItem).visible = active and alive
		if node is Checkpoint:
			(node as Checkpoint).set_deferred("monitoring", active)
		if node.is_in_group("collectible") or node.is_in_group("spike_monster"):
			var area := node as Area2D
			if area != null:
				area.set_deferred("monitoring", active)

func _collect_managed_nodes(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Checkpoint or child is Animal or child is DoorButton \
				or child.is_in_group("collectible") or child.is_in_group("spike_monster"):
			out.append(child)
		_collect_managed_nodes(child, out)

## 玩家进入某房间时：已经在该房间里的动物，把刷新点改到这个房间。
## 用于“把 Room11 的动物赶进 Room12 后，刷新时动物留在 Room12”。
func _rebase_animals_in_room(room: Room) -> void:
	if room == null:
		return
	for node in get_tree().get_nodes_in_group("animal"):
		var animal := node as Animal
		if animal == null or not is_instance_valid(animal):
			continue
		if _room_of(animal.global_position) != room:
			continue
		if _room_of(animal.home_position()) != room:
			animal.rebase_home()

## 某个房间 + 联动房间一起加载/刷新。
func _active_rooms(room: Room) -> Array[Room]:
	var rooms: Array[Room] = []
	if room == null:
		return rooms
	rooms.append(room)
	var linked := _linked_room_for(room)
	if linked != null:
		rooms.append(linked)
	return rooms

func _same_room_set(a: Array[Room], b: Array[Room]) -> bool:
	if a.size() != b.size():
		return false
	for room in a:
		if not b.has(room):
			return false
	return true

## 玩家跨出上一个房间（组）时，把上一个加载组整个刷新。
## 联动组内部移动（prev_set == new_set）不刷新。
func _refresh_rooms_left(previous: Room, here: Room) -> void:
	var prev_set := _active_rooms(previous)
	var new_set := _active_rooms(here)
	if _same_room_set(prev_set, new_set):
		return
	for room in prev_set:
		_refresh_room(room)

func _refresh_room(room: Room) -> void:
	if room == null:
		return
	breakables.restore_rect(room.get_rect())
	for door in get_tree().get_nodes_in_group("door"):
		if door is Node2D and room.contains_world_point((door as Node2D).global_position) \
				and door.has_method("restore"):
			door.call("restore")
	if puzzle_door_manager != null:
		puzzle_door_manager.reset_room(room)
	_reset_animals_in_room(room)
	_reset_monsters_in_room(room)

func _reset_animals_in_room(room: Room) -> void:
	for node in get_tree().get_nodes_in_group("animal"):
		var animal := node as Animal
		if animal == null or not is_instance_valid(animal):
			continue
		# 只刷新“还留在这个房间”的动物；被驱赶去别的房间的留给新房间 rebase。
		if _room_of(animal.home_position()) == room \
				and _room_of(animal.global_position) == room:
			animal.reset_home()

func _reset_monsters_in_room(room: Room) -> void:
	for node in get_tree().get_nodes_in_group("spike_monster"):
		if not is_instance_valid(node) or not node.has_method("home_position"):
			continue
		if _room_of(node.call("home_position")) == room:
			node.call("reset_home")

## Room4 与 Room5 联动，两个房间一起加载。
func _linked_room_for(room: Room) -> Room:
	if room == null:
		return null
	var pair := ""
	match room.name:
		&"Room4":
			pair = "Room5"
		&"Room5":
			pair = "Room4"
		&"Room6":
			pair = "Room8"
		&"Room8":
			pair = "Room6"
	if pair.is_empty():
		return null
	return get_node_or_null("Rooms/" + pair) as Room

func _first_room() -> Room:
	var rooms := get_rooms()
	return rooms[0] if not rooms.is_empty() else null
