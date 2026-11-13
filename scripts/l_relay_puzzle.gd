extends Node2D
## Whitebox mechanism prototype. All geometry is visible; there is no view-distance death.

enum Phase { READY, APPROACH, BOARD, TRAVEL, CLIMB, CONNECT, COMPLETE, FAILED }

@export var ferry_speed: float = 104.0
@export var boarding_time: float = 1.4
@export var climb_time: float = 4.0
@export var upper_drop_delay: float = 2.2
@export var upper_drop_speed: float = 72.0

var phase: Phase = Phase.READY
var active: bool = false
var attempts: int = 0
var elapsed: float = 0.0
var phase_time: float = 0.0
var board_entered: bool = false
var upper_entered: bool = false
var fail_reason: String = ""
var _gate_one_open: bool = false
var _gate_two_open: bool = false
var _paused: bool = false
var _walls: Array[WallPlatform] = []
var vision: ShaderMaterial = preload("res://resources/vision_material.tres")

@onready var player: EchoPlayer = $Player
@onready var eye: WallEye = $Eye
@onready var ferry: WallPlatform = $Terrain/Ferry
@onready var upper: WallPlatform = $Terrain/UpperDrop
@onready var gate_one: WallPlatform = $Terrain/GateOne
@onready var gate_two: WallPlatform = $Terrain/GateTwo
@onready var plate_one: Area2D = $PlateOne
@onready var plate_two: Area2D = $PlateTwo
@onready var bell: Node2D = $Bell
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	process_physics_priority = -50
	for child in $Terrain.get_children():
		if child is WallPlatform:
			_walls.append(child)
	bell.eye = eye
	bell.rung.connect(_on_bell_rung)
	player.show_body_in_eye = true
	vision.set_shader_parameter("debug_visible", true)
	hud.chapter.text = "02   L 形接驳机关   ·   无视野限制"
	hud.metric_caption.text = "机关进度"
	hud.controls_label.text = "A / D 或 ← / → 移动    空格跳跃    鼠标移动圆点    左键敲铃    R 重来    Esc 暂停"
	_reset_world()
	hud.show_message("身体踩板，圆点接驳", "① 踩住右侧 1 号压力板，圆点从底部进入右墙。\n② 圆点靠近铃铛并点击，随后搭乘向左的平台。\n③ 圆点向上接入下落平台，身体踩住 2 号板连通出口。\n\n单击或 Enter 开始 · 本版不限制视野")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/levels/wave_jump_lab.tscn")
	elif event.is_action_pressed("restart") and not event.is_echo():
		restart_run()
	elif event.is_action_pressed("ui_cancel") and phase != Phase.READY and phase != Phase.COMPLETE and phase != Phase.FAILED:
		if active:
			_set_active(false)
			_paused = true
			hud.show_message("已暂停", "单击或 Enter 继续。\n圆点只能在已接通的墙体与平台内部移动。")
	elif (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
		if phase == Phase.READY:
			phase = Phase.APPROACH
			_set_active(true)
			hud.overlay.hide()
		elif _paused:
			_paused = false
			_set_active(true)
			hud.overlay.hide()
		elif phase == Phase.COMPLETE or phase == Phase.FAILED:
			restart_run()

func _physics_process(delta: float) -> void:
	if not active:
		return
	phase_time += delta
	_set_gate_one(plate_one.pressed or phase >= Phase.BOARD)
	var upper_landed := upper.position.y >= 223.99
	_set_gate_two(plate_two.pressed and upper_landed and phase >= Phase.BOARD)
	if phase >= Phase.BOARD and phase <= Phase.CONNECT:
		elapsed += delta
		if elapsed >= upper_drop_delay:
			upper.position.y = move_toward(upper.position.y, 224.0, upper_drop_speed * delta)
		if eye.host == ferry:
			board_entered = true
		if eye.host == upper:
			upper_entered = true
			_set_phase(Phase.CONNECT)
	match phase:
		Phase.BOARD:
			if phase_time >= boarding_time:
				_set_phase(Phase.TRAVEL)
		Phase.TRAVEL:
			ferry.position.x = move_toward(ferry.position.x, 576.0, ferry_speed * delta)
			if ferry.position.x <= 576.01:
				_set_phase(Phase.CLIMB)
		Phase.CLIMB:
			if phase_time > climb_time and not upper_entered:
				_fail("没有及时向上接入平台")
	if player.global_position.y > 900:
		_fail("身体掉出了地图")
	elif eye.host == gate_one and not _gate_one_open and phase == Phase.APPROACH:
		_fail("入口断开：先让身体踩住 1 号压力板")
	elif upper_entered and eye.host == gate_two and not _gate_two_open:
		_fail("连接中断：身体需要踩住 2 号压力板")
	elif upper_entered and eye.global_position.x < 220.0 and eye.global_position.y < 290.0 and _gate_two_open:
		_set_phase(Phase.COMPLETE)
		_set_active(false)
		hud.show_message("接驳完成", "身体与圆点配合，已经接通了另一端。\n\n按 R、单击或 Enter 重新测试。")
	_update_hud()

func _set_phase(value: Phase) -> void:
	if value == phase:
		return
	phase = value
	phase_time = 0.0

func _on_bell_rung() -> void:
	if phase != Phase.APPROACH:
		return
	_set_phase(Phase.BOARD)
	elapsed = 0.0
	plate_one.latched = true
	plate_one.queue_redraw()
	_set_gate_one(true)

func _set_gate_one(open: bool) -> void:
	if _gate_one_open == open:
		return
	_gate_one_open = open
	gate_one.visible = open
	gate_one.collision.set_deferred("disabled", not open)
	_sync_walls()

func _set_gate_two(open: bool) -> void:
	if _gate_two_open == open:
		return
	_gate_two_open = open
	gate_two.visible = open
	gate_two.collision.set_deferred("disabled", not open)
	_sync_walls()

func _sync_walls() -> void:
	eye.walls.clear()
	for wall in _walls:
		if wall == gate_one and not _gate_one_open:
			continue
		if wall == gate_two and not _gate_two_open:
			continue
		eye.walls.append(wall)

func _update_hud() -> void:
	hud.statistics.text = "1 号板 %s   /   2 号板 %s" % ["●" if plate_one.pressed or plate_one.latched else "○", "●" if plate_two.pressed else "○"]
	hud.margin_bar.value = minf(float(phase) / float(Phase.COMPLETE), 1.0) * 100.0
	match phase:
		Phase.READY:
			hud.status.text = "先让身体踩住 1 号板，再让圆点进入右墙敲响铃铛。"
		Phase.APPROACH:
			hud.status.text = "踩住 1 号压力板 → 圆点沿底部进入右墙 → 靠近铃铛后按左键。"
		Phase.BOARD:
			hud.status.text = "铃铛已触发：%.1f 秒后平台向左移动。圆点立刻向左上平台！" % maxf(0.0, boarding_time - phase_time)
		Phase.TRAVEL:
			hud.status.text = "圆点随平台向左；身体赶往 2 号压力板。上方平台正在落下。"
		Phase.CLIMB:
			hud.status.text = "圆点向上接入下落的平台！剩余 %.1f 秒；身体踩住 2 号压力板。" % maxf(0.0, climb_time - phase_time)
		Phase.CONNECT:
			hud.status.text = "保持踩住 2 号压力板，让圆点向左通过上方连桥，进入出口。"

func _fail(reason: String) -> void:
	if phase == Phase.FAILED:
		return
	fail_reason = reason
	_set_phase(Phase.FAILED)
	_set_active(false)
	hud.show_message(reason, "按 R、单击或 Enter 从起点重试。")

func restart_run() -> void:
	attempts += 1
	_reset_world()
	phase = Phase.APPROACH
	_set_active(true)
	hud.overlay.hide()
	_update_hud()

func _reset_world() -> void:
	_set_active(false)
	phase = Phase.READY
	phase_time = 0.0
	elapsed = 0.0
	board_entered = false
	upper_entered = false
	fail_reason = ""
	_paused = false
	for wall in _walls:
		wall.reset_motion()
	plate_one.clear_contacts()
	plate_two.clear_contacts()
	bell.reset_bell()
	_gate_one_open = true
	_gate_two_open = true
	_set_gate_one(false)
	_set_gate_two(false)
	_sync_walls()
	player.reset_to(Vector2(656, 490))
	eye.reset_to(Vector2(288, 544), $Terrain/Floor)
	_update_hud()

func _set_active(value: bool) -> void:
	active = value
	player.controls_enabled = value
	eye.input_enabled = value
	bell.enabled = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE
	for wall in _walls:
		wall.paused = true
