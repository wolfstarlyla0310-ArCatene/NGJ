extends Node2D

const GRACE_SECONDS := 0.5

var active: bool = false
var deaths: int = 0
var _spawn_position: Vector2 = Vector2.ZERO
var _grace_remaining := GRACE_SECONDS

@onready var player: EchoPlayer = $Player
@onready var sound_fields: Node2D = $SoundFields
@onready var breakables: Breakables = $Breakables
@onready var noise: NoiseField = $Noise

func _ready() -> void:
	process_physics_priority = 100
	_spawn_position = player.global_position
	player.wave_emitted.connect(_on_wave)
	_set_active(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo():
		restart_run()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		_set_active(not active)
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			teleport_player(_viewport_to_world(mouse.position))

func _physics_process(delta: float) -> void:
	noise.sync_visibility(_active_pulse_rects())
	if not active:
		return
	var center := player.global_position
	# 身体任意部分碰到噪音就开始 0.5 秒冷却；中心在声场内时重置冷却。
	if not noise.touches_rect(_player_rect()) or _inside_active_pulse(center):
		_grace_remaining = GRACE_SECONDS
		return
	_grace_remaining = maxf(0.0, _grace_remaining - delta)
	if _grace_remaining <= 0.0:
		deaths += 1
		restart_run()

func _active_pulse_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion():
			var side: float = child.side_length
			rects.append(Rect2(child.global_position - Vector2(side, side) * 0.5, Vector2(side, side)))
	return rects

func _inside_active_pulse(point: Vector2) -> bool:
	for child in sound_fields.get_children():
		if child is SoundField and not child.is_queued_for_deletion() and child.contains_point(point):
			return true
	return false

func _player_rect() -> Rect2:
	var shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var size: Vector2 = (shape.shape as RectangleShape2D).size
		return Rect2(shape.global_position - size * 0.5, size)
	return Rect2(player.global_position - Vector2(8, 8), Vector2(16, 16))

func _on_wave(origin: Vector2, side: float, level: int, _kind: String) -> void:
	var snapped_origin := SoundField.snap_origin_to_grid(origin, side)
	var field := SoundField.new()
	field.side_length = side
	field.level = level
	field.emitter = player
	field.color = SoundField.color_for_level(level)
	if level == 2:
		field.lifetime = INF  # 大跳常驻；reset 时按非 persistent 清除
	sound_fields.add_child(field)
	field.global_position = snapped_origin
	var half := Vector2(side, side) * 0.5
	breakables.break_in_rect(Rect2(snapped_origin - half, Vector2(side, side)), level)

func teleport_player(world_point: Vector2) -> void:
	player.reset_to(world_point)
	_grace_remaining = GRACE_SECONDS

func world_to_screen(world_point: Vector2) -> Vector2:
	return get_canvas_transform() * world_point

func _viewport_to_world(screen_point: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_point

func restart_run() -> void:
	player.reset_to(_spawn_position)
	for ring in sound_fields.get_children():
		ring.queue_free()
	noise.sync_visibility([])
	breakables.reset()
	_grace_remaining = GRACE_SECONDS
	_set_active(true)

func _set_active(value: bool) -> void:
	active = value
	player.controls_enabled = value
	if value:
		_grace_remaining = GRACE_SECONDS
