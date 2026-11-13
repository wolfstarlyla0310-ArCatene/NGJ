extends Node2D

signal player_died(reason: String)
signal section_completed

const WAVE_SCRIPT := preload("res://scripts/sound_wave.gd")

@export var player_spawn := Vector2(160, 426)
@export var eye_spawn := Vector2(160, 512)
@export var goal_x: float = 2016.0
@export var camera_lead: float = 240.0
@export var camera_height: float = 380.0

var deaths: int = 0
var active: bool = false
var completed: bool = false
var debug_view: bool = false
var last_death_reason: String = ""
var _respawn_remaining: float = -1.0
var _started: bool = false
var _time_to_ping: float = 0.0
var _time_to_scan: float = 0.0
var _walls: Array[WallPlatform] = []
var vision: ShaderMaterial = preload("res://resources/vision_material.tres")

@onready var player: EchoPlayer = $Player
@onready var eye: WallEye = $Eye
@onready var ferry: WallPlatform = $Terrain/Ferry
@onready var start_wall: WallPlatform = $Terrain/Start
@onready var camera: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD
@onready var waves: Node2D = $SoundWaves
@onready var creatures: Node2D = $Creatures
@onready var sonar: Node2D = $Sonar

func _ready() -> void:
	process_physics_priority = 50
	for child in $Terrain.get_children():
		if child is WallPlatform:
			_walls.append(child)
	eye.walls = _walls
	sonar.walls = _walls
	sonar.eye = eye
	sonar.wave_container = waves
	player.sound_emitted.connect(_on_sound_emitted)
	for creature in creatures.get_children():
		creature.sound_emitted.connect(_on_sound_emitted)
	_reset_world()
	_set_active(false)
	hud.show_message("循声，与自己同行", "身体在墙外，感知点在墙内。\n这里只有声波反弹后短暂浮现的边缘。\n身体与生物隐于黑暗，脚步会留下回声。\n\n单击画面或按 Enter 开始 · Esc 释放鼠标")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not event.is_echo():
		restart_run()
	elif event.is_action_pressed("debug_view") and not event.is_echo():
		debug_view = not debug_view
		vision.set_shader_parameter("debug_visible", debug_view)
		player.debug_visible = debug_view
		player.queue_redraw()
		for creature in creatures.get_children():
			creature.debug_visible = debug_view
			creature.queue_redraw()
		$DebugRoute.visible = debug_view
	elif event.is_action_pressed("ui_cancel"):
		if active:
			_set_active(false)
			hud.show_message("已暂停", "单击画面或按 Enter 继续。\n鼠标控制眼睛，键盘控制不可见的身体。")
	elif (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
		if not active and _respawn_remaining < 0.0:
			_started = true
			_set_active(true)
			hud.overlay.hide()

func _physics_process(delta: float) -> void:
	if _respawn_remaining >= 0:
		_respawn_remaining -= delta
		if _respawn_remaining < 0:
			_reset_world()
			_set_active(true)
			hud.overlay.hide()
	if active:
		_update_camera(delta)
		_time_to_ping -= delta
		_time_to_scan -= delta
		if _time_to_scan <= 0.0:
			_time_to_scan = 1.25
			_on_sound_emitted(eye.global_position, 0.95)
		if _time_to_ping <= 0.0:
			_time_to_ping = 1.55
			_on_sound_emitted(player.global_position + Vector2(0, 20), 0.24)
		if player.global_position.y > 1050.0:
			kill_player("身体坠入了深处")
		elif not eye_is_visible():
			kill_player("眼睛离开了视野")
		elif not completed and player.global_position.x >= goal_x and eye.global_position.x >= 1560.0 and player.is_on_floor():
			completed = true
			section_completed.emit()
	vision.set_shader_parameter("eye_position", eye.global_position)
	vision.set_shader_parameter("sight_radius", eye.sight_radius)
	hud.update_state(deaths, eye_view_margin(), completed, debug_view)

func _update_camera(delta: float, snap: bool = false) -> void:
	var target := Vector2(player.global_position.x + camera_lead, camera_height)
	camera.global_position = target if snap else camera.global_position.lerp(target, 1.0 - exp(-7.0 * delta))
	camera.force_update_scroll()

func eye_view_margin() -> float:
	var screen := get_viewport().get_canvas_transform() * eye.global_position
	var view_size := get_viewport_rect().size
	# HUD is opaque, so being behind it also means leaving the visible play area.
	return minf(minf(screen.x, view_size.x - screen.x), minf(screen.y - 100.0, view_size.y - 128.0 - screen.y)) - eye.radius

func eye_is_visible() -> bool:
	return eye_view_margin() >= 0.0

func kill_player(reason: String) -> void:
	if not active:
		return
	deaths += 1
	last_death_reason = reason
	_set_active(false)
	_respawn_remaining = 0.85
	hud.show_message(reason, "身体与眼睛必须同行。\n正在回到起点……")
	player_died.emit(reason)

func restart_run() -> void:
	_respawn_remaining = -1.0
	_reset_world()
	_started = true
	_set_active(true)
	hud.overlay.hide()

func _reset_world() -> void:
	for wall in _walls:
		wall.reset_motion()
	player.reset_to(player_spawn)
	eye.reset_to(eye_spawn, start_wall)
	for creature in creatures.get_children():
		creature.reset_motion()
	for wave in waves.get_children():
		wave.queue_free()
	completed = false
	_time_to_ping = 0.15
	_time_to_scan = 0.0
	_update_camera(0.0, true)
	vision.set_shader_parameter("eye_position", eye.global_position)
	vision.set_shader_parameter("sight_radius", eye.sight_radius)
	vision.set_shader_parameter("debug_visible", debug_view)

func _set_active(value: bool) -> void:
	active = value
	player.controls_enabled = value
	eye.input_enabled = value
	for wall in _walls:
		wall.paused = not value
	for creature in creatures.get_children():
		creature.active = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

func _on_sound_emitted(origin: Vector2, strength: float) -> void:
	var distance := eye.global_position.distance_to(origin)
	if distance > eye.hearing_radius:
		return
	emit_wave(origin, WaveTypes.WaveType.WHITE, {"strength": strength * lerpf(1.0, 0.25, distance / eye.hearing_radius)})

func emit_wave(origin: Vector2, type: WaveTypes.WaveType = WaveTypes.WaveType.WHITE, options: Dictionary = {}) -> Node2D:
	var settings := {"echo": true}
	# Force-pulse-only options have no meaning in the old reflection renderer.
	if options.has("strength"): settings["strength"] = options["strength"]
	return WaveFactory.spawn(waves, origin, type, settings)
