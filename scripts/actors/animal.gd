@tool
class_name Animal
extends CharacterBody2D
## 受重力影响的动物：附近出现 lv1 声场时向背离声源的方向水平移动，
## 移动时像玩家一样每 16px 发出一个 1×1 格白色声场。

const TILE_SIZE := 16.0

@export var move_speed := 90.0
@export var gravity := 1500.0
@export var detection_margin := 16.0
@export var wave_side := 16.0
@export var wave_interval_pixels := 16.0
## 动物声场持续时间（秒）；比玩家声场更久。
@export var wave_lifetime := 1.0
## 动物声场从中心扩散到目标边长的时间（秒）；比玩家声场更慢。
@export var wave_expand_duration := 0.5
## 静止时每隔这么久发一次 2 格 lv0 声场（秒）。
@export var idle_wave_interval := 1.6
@export var idle_wave_side_cells := 1.4

var _sound_fields: Node2D = null
var _wave_distance := 0.0
var _idle_wave_timer := 0.0

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	_sound_fields = get_tree().get_first_node_in_group("sound_fields")

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var source := _nearest_lv1_source()
	if source != null:
		var dir := signf(global_position.x - source.global_position.x)
		if dir == 0.0:
			dir = 1.0
		velocity.x = dir * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 8.0 * delta)
	velocity.y = minf(velocity.y + gravity * delta, 1000.0)

	var pre_x := global_position.x
	move_and_slide()
	_wave_distance += absf(global_position.x - pre_x)
	while _wave_distance >= wave_interval_pixels:
		_wave_distance -= wave_interval_pixels
		_spawn_wave(wave_side)

	var idle := source == null and is_on_floor() and absf(velocity.x) < 1.0
	if idle:
		_idle_wave_timer += delta
		if _idle_wave_timer >= idle_wave_interval:
			_idle_wave_timer = 0.0
			_spawn_wave(idle_wave_side_cells * TILE_SIZE)
	else:
		_idle_wave_timer = 0.0

func _nearest_lv1_source() -> SoundField:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return null
	var body_rect := Rect2(global_position - Vector2(8, 8), Vector2(16, 16)).grow(detection_margin)
	var best: SoundField = null
	var best_distance := INF
	for child in _sound_fields.get_children():
		if not child is SoundField or child.is_queued_for_deletion() or child.level != 1:
			continue
		var field := child as SoundField
		if not field.get_rect().intersects(body_rect):
			continue
		var distance := global_position.distance_squared_to(field.global_position)
		if distance < best_distance:
			best_distance = distance
			best = field
	return best

func _spawn_wave(side: float) -> void:
	if _sound_fields == null or not is_instance_valid(_sound_fields):
		return
	var field := SoundField.new()
	field.side_length = side
	field.lifetime = wave_lifetime
	field.expand_duration = wave_expand_duration
	field.level = 0
	field.emitter = self
	field.safe_for_player = true
	_sound_fields.add_child(field)
	field.global_position = global_position

func _draw() -> void:
	draw_rect(Rect2(-7, -6, 14, 12), Color.WHITE)
	draw_rect(Rect2(-4, -3, 2, 2), Color.BLACK)
	draw_rect(Rect2(2, -3, 2, 2), Color.BLACK)
