class_name SpikeMonster
extends Area2D
## 由四邻相连的 spike 格子变成的怪：不受重力、穿墙；只在出生房间内追击声源。
## 玩家移动时追玩家，动物一直追，离谁近追谁。lv1 波把它推开，lv2 波把它定住。
## 接触玩家触发死亡，接触动物把动物吃掉。

const TILE_SIZE := 16.0

@export var move_speed := 55.0
@export var push_speed := 220.0
@export var push_duration := 0.25

@export_group("视觉声场")
## 每轮连发的红色短声场边长（格）。
@export var visual_side_cells := 3.0
## 单个视觉声场寿命（秒）。
@export var visual_lifetime := 0.2
## 每轮连发数量。
@export var visual_burst_count := 3
## 连发间隔（秒）。
@export var visual_burst_interval := 0.1
## 两轮之间的间隔（秒）。
@export var visual_cycle_interval := 1.0
@export var visual_color := Color(1.0, 0.2, 0.2, 1.0)

var sound_fields: Node2D = null

var _offsets: Array[Vector2] = []
var _bounds_size := Vector2(TILE_SIZE, TILE_SIZE)
var _home := Vector2.ZERO
var _velocity := Vector2.ZERO
var _push_remaining := 0.0
var _last_lv1: SoundField = null
var _world: Node = null
var _rooms: Array = []
var _room: Room = null
var _room_resolved := false
var _cycle_elapsed := 0.0
var _burst_left := 0
var _burst_timer := 0.0

func setup(world_center: Vector2, offsets: Array[Vector2], bounds_size: Vector2) -> void:
	global_position = world_center
	_home = world_center
	_offsets = offsets
	_bounds_size = bounds_size
	collision_layer = 0
	collision_mask = 6  # 玩家层 2 + 动物层 4
	monitorable = false
	add_to_group("spike_monster")
	body_entered.connect(_on_body_entered)
	for offset in _offsets:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE_SIZE, TILE_SIZE)
		shape.shape = rect
		shape.position = offset
		add_child(shape)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_emit_visual(delta)
	_resolve_room()
	var bounds := _bounds()
	# lv2：定住，不推走。
	if _overlaps_level(2, bounds):
		_velocity = Vector2.ZERO
		_push_remaining = 0.0
		return
	# lv1：被波推走。
	_try_lv1_push(bounds)
	if _push_remaining > 0.0:
		_push_remaining = maxf(0.0, _push_remaining - delta)
		_advance(_velocity, delta)
		return
	var target := _pick_target()
	if target != null:
		_velocity = (target.global_position - global_position).normalized() * move_speed
	else:
		_velocity = Vector2.ZERO
	_advance(_velocity, delta)

func reset_home() -> void:
	global_position = _home
	_velocity = Vector2.ZERO
	_push_remaining = 0.0
	_last_lv1 = null

func home_position() -> Vector2:
	return _home

## 沿用旧 spike 的“间歇三连红色短声场”作为纯视觉；命中判定仍是每格 16×16。
func _emit_visual(delta: float) -> void:
	if _burst_left > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_spawn_visual_burst()
			_burst_left -= 1
			_burst_timer = visual_burst_interval
	_cycle_elapsed += delta
	if _cycle_elapsed >= visual_cycle_interval and _burst_left == 0:
		_cycle_elapsed = 0.0
		_burst_left = visual_burst_count
		_burst_timer = 0.0

func _spawn_visual_burst() -> void:
	var fields := _fields()
	if fields == null:
		return
	var side := visual_side_cells * TILE_SIZE
	for offset in _offsets:
		var field := SoundField.new()
		field.side_length = side
		field.lifetime = visual_lifetime
		field.level = 0
		field.lethal = false
		field.safe_for_player = false
		field.color = visual_color
		fields.add_child(field)
		field.global_position = global_position + offset

func _resolve_room() -> void:
	if _room_resolved:
		return
	_world = get_tree().get_first_node_in_group("world_map")
	if _world == null:
		return
	if _world.has_method("get_rooms"):
		_rooms = _world.call("get_rooms")
	if not _rooms.is_empty():
		_room = RoomRegistry.room_at(_rooms, _home)
	_room_resolved = true

func _fields() -> Node2D:
	if sound_fields == null or not is_instance_valid(sound_fields):
		sound_fields = get_tree().get_first_node_in_group("sound_fields") as Node2D
	return sound_fields

## 刺怪只响应玩家发出的声场；动物现在的蓝色场不会推/冻它。
func _is_player_field(field: SoundField) -> bool:
	if _world == null:
		_resolve_room()
	if _world == null:
		return false
	var player: EchoPlayer = _world.get("player") as EchoPlayer
	return player != null and field.emitter == player

func _overlaps_level(field_level: int, bounds: Rect2) -> bool:
	var fields := _fields()
	if fields == null:
		return false
	for child in fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion():
			continue
		var field := child as SoundField
		if not _is_player_field(field):
			continue
		if field.level == field_level and field.get_rect().intersects(bounds):
			return true
	return false

func _try_lv1_push(bounds: Rect2) -> void:
	if _last_lv1 != null and (not is_instance_valid(_last_lv1) or _last_lv1.is_queued_for_deletion()):
		_last_lv1 = null
	var fields := _fields()
	if fields == null:
		return
	for child in fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion():
			continue
		var field := child as SoundField
		if not _is_player_field(field):
			continue
		if field.level != 1 or field == _last_lv1:
			continue
		if not field.get_rect().intersects(bounds):
			continue
		_last_lv1 = field
		var away := global_position - field.global_position
		if away.length_squared() < 0.01:
			away = Vector2.RIGHT
		_velocity = away.normalized() * push_speed
		_push_remaining = push_duration
		return

func _pick_target() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	if _world == null:
		_resolve_room()
	if _world != null and is_instance_valid(_world):
		var player := _world.get("player") as EchoPlayer
		if player != null and is_instance_valid(player) and _in_same_room(player):
			var dead: bool = _world.has_method("is_dead") and bool(_world.call("is_dead"))
			# 玩家只有移动（发出走路声场）时才会被追。
			if not dead and absf(player.velocity.x) > 1.0:
				var d := global_position.distance_squared_to(player.global_position)
				if d < best_dist:
					best_dist = d
					best = player
	for child in get_tree().get_nodes_in_group("animal"):
		var animal := child as Animal
		if animal == null or animal.is_queued_for_deletion():
			continue
		if not _in_same_room(animal):
			continue
		var d2 := global_position.distance_squared_to(animal.global_position)
		if d2 < best_dist:
			best_dist = d2
			best = animal
	return best

func _in_same_room(node: Node2D) -> bool:
	if _room == null:
		return true
	return RoomRegistry.room_at(_rooms, node.global_position) == _room

func _advance(motion: Vector2, delta: float) -> void:
	global_position += motion * delta
	_clamp_to_room()

func _clamp_to_room() -> void:
	if _room == null:
		return
	var rect := _room.get_rect()
	var half := _bounds_size * 0.5
	var min_x := rect.position.x + half.x
	var max_x := rect.end.x - half.x
	var min_y := rect.position.y + half.y
	var max_y := rect.end.y - half.y
	var center := rect.get_center()
	var x := center.x
	var y := center.y
	if min_x <= max_x:
		x = clampf(global_position.x, min_x, max_x)
	if min_y <= max_y:
		y = clampf(global_position.y, min_y, max_y)
	global_position = Vector2(x, y)

func _bounds() -> Rect2:
	return Rect2(global_position - _bounds_size * 0.5, _bounds_size)

func _on_body_entered(body: Node2D) -> void:
	if body is EchoPlayer:
		var world := get_tree().get_first_node_in_group("world_map")
		if world != null and world.has_method("_die"):
			world.call("_die")
	elif body is Animal:
		if body.has_method("consume"):
			body.call("consume")
