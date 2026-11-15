class_name SpikeMonster
extends Area2D
## 由四邻相连的 spike 格子变成的怪：不受重力、穿墙；只在出生房间内追击声源。
## 玩家移动时追玩家，动物一直追，离谁近追谁。lv1 波把它推开，lv2 波把它定住。
## 接触玩家触发死亡，接触动物把动物吃掉。

const TILE_SIZE := 16.0
const NOISE_STREAM: AudioStream = preload("res://assets/sound/noise.wav")
const MONSTER_SOUND_NAME := &"MonsterSound"

@export var move_speed := 40.0
@export var push_speed := 220.0
@export var push_duration := 0.25

@export_group("视觉声场")
## 单格怪外框边长（格）。多格怪取组最长边 + (该值 - 1) 格，即旧版逐格并集的最外缘。
@export var visual_side_cells := 3.0
## 外框淡出寿命（秒），应小于 visual_cycle_interval。
@export var visual_lifetime := 0.2
## 两次外缘闪烁之间的间隔（秒）。
@export var visual_cycle_interval := 2.0
@export var visual_color := Color(1.0, 0.2, 0.2, 1.0)
## 被玩家 lv1 波击退期间的视觉颜色（蓝色）。
@export var visual_push_color := Color(0.3, 0.65, 1.0, 1.0)
## 被玩家 lv2 波定住期间的视觉颜色（黄色）。
@export var visual_freeze_color := Color(1.0, 0.9, 0.2, 1.0)

@export_group("音频")
## 玩家与刺怪的曼哈顿距离超过这么多格时停止噪音。
@export var audible_range_cells := 8.0

var sound_fields: Node2D = null
var _state_color := Color(1.0, 0.2, 0.2, 1.0)
var _emitted_state := Color(1.0, 0.2, 0.2, 1.0)

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
var _noise_audio: AudioStreamPlayer = null
var _audio_active := true
var _player_node: Node2D = null

func setup(world_center: Vector2, offsets: Array[Vector2], bounds_size: Vector2) -> void:
	global_position = world_center
	_home = world_center
	_offsets = offsets
	_bounds_size = bounds_size
	_state_color = visual_color  # 读到场景/SpikeField 的覆盖值。
	_emitted_state = visual_color
	_cycle_elapsed = 0.0
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
	_setup_audio()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_resolve_room()
	_update_noise_audio()
	var bounds := _bounds()
	var frozen := _overlaps_level(2, bounds)
	# 视觉颜色：定住（黄）优先于击退（蓝）优先于默认红。
	if frozen:
		_state_color = visual_freeze_color
	elif _push_remaining > 0.0:
		_state_color = visual_push_color
	else:
		_state_color = visual_color
	# 击退 0.25 秒可能短于闪烁周期：状态切换时立即补闪一次，保证蓝/黄可见。
	if not _state_color.is_equal_approx(_emitted_state):
		_emitted_state = _state_color
		_cycle_elapsed = 0.0
		_spawn_visual_pulse()
	_emit_visual(delta)
	# lv2：定住，不推走。
	if frozen:
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
	_cycle_elapsed = 0.0
	_state_color = visual_color
	_emitted_state = visual_color
	_stop_noise_audio()

func home_position() -> Vector2:
	return _home

func _setup_audio() -> void:
	_noise_audio = get_node_or_null(String(MONSTER_SOUND_NAME)) as AudioStreamPlayer
	if _noise_audio != null:
		return
	_noise_audio = AudioStreamPlayer.new()
	_noise_audio.name = MONSTER_SOUND_NAME
	_noise_audio.stream = NOISE_STREAM
	_noise_audio.bus = &"Noise"
	_noise_audio.max_polyphony = 1
	add_child(_noise_audio)

## 房间裁剪会停掉 _physics_process 但不会停音频，需要显式启停。
func set_audio_active(active: bool) -> void:
	_audio_active = active
	if active:
		_update_noise_audio()
	else:
		_stop_noise_audio()

## 持续播放噪音；音量按玩家与刺怪的曼哈顿距离线性衰减，audible_range_cells 格外停止。
func _update_noise_audio() -> void:
	if _noise_audio == null or not _audio_active:
		return
	if _player_node == null or not is_instance_valid(_player_node):
		_player_node = get_tree().get_first_node_in_group("player") as Node2D
	if _player_node == null:
		_stop_noise_audio()
		return
	var range_cells := maxf(audible_range_cells, 0.001)
	var distance_px := absf(global_position.x - _player_node.global_position.x) \
		+ absf(global_position.y - _player_node.global_position.y)
	var distance_cells := distance_px / TILE_SIZE
	if distance_cells >= range_cells:
		_stop_noise_audio()
		return
	var volume_t := 1.0 - distance_cells / range_cells
	_noise_audio.volume_db = maxf(linear_to_db(volume_t), -80.0)
	if not _noise_audio.playing:
		_noise_audio.play()

func _stop_noise_audio() -> void:
	if _noise_audio != null and _noise_audio.playing:
		_noise_audio.stop()

## 每轮只在整组最外缘闪一次满尺寸外框；不再从怪物内部逐格发射。命中判定仍是每格 16×16。
func _emit_visual(delta: float) -> void:
	_cycle_elapsed += delta
	var interval := maxf(visual_cycle_interval, 0.01)
	if _cycle_elapsed >= interval:
		_cycle_elapsed = fmod(_cycle_elapsed, interval)
		_spawn_visual_pulse()

## 旧版逐格脉冲并集的最外缘：组最长边 + (visual_side_cells - 1) 格。
func visual_side_length() -> float:
	var max_dim := maxf(_bounds_size.x, _bounds_size.y)
	return max_dim + maxf(visual_side_cells - 1.0, 0.0) * TILE_SIZE

func _spawn_visual_pulse() -> void:
	var fields := _fields()
	if fields == null:
		return
	var side := visual_side_length()
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = visual_lifetime
	field.expand_duration = 0.0
	field.current_side = side
	field.level = 0
	field.lethal = false
	field.safe_for_player = false
	# 怪物外框永远完整显示：不参与同色并集合并，也不被其它声场遮掉边段。
	field.never_covered = true
	field.color = _state_color
	fields.add_child(field)
	field.global_position = global_position
	field.queue_redraw()

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
		# 被吃掉/消耗的动物会保留节点但 is_alive() == false，不能再当目标。
		if animal == null or animal.is_queued_for_deletion() or not animal.is_alive():
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
