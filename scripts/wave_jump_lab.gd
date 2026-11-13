extends Node2D

const PULSE_SCRIPT := preload("res://scripts/force_pulse.gd")

@export var pulse_range: float = 240.0
@export var movement_rules: MovementRules = preload("res://resources/movement_rules.tres")
@export_range(0.0, 1.0, 0.01) var pulse_cooldown: float = 0.0

var active: bool = false
var cooldown: float = 0.0
var shots: int = 0
var wave_jumps: int = 0
var _feedback: String = "把圆点移到玩家脚下的墙内，再按左键，声波会把身体推起来。"
var _feedback_time: float = 0.0
var _was_on_floor: bool = false
var _wave_pending_jump: bool = false
var _paused: bool = false
var _started: bool = false
var _last_rebound: String = "—"

@onready var player: EchoPlayer = $Player
@onready var eye: WallEye = $Eye
@onready var hud: CanvasLayer = $HUD
@onready var pulses: Node2D = $Pulses

func _ready() -> void:
	process_physics_priority = 50
	for child in $Terrain.get_children():
		if child is WallPlatform:
			eye.walls.append(child)
	var vision: ShaderMaterial = preload("res://resources/vision_material.tres")
	vision.set_shader_parameter("debug_visible", true)
	player.show_body_in_eye = true
	player.direct_jump_enabled = false
	player.collision_rebound_enabled = true
	player.movement_rules = movement_rules
	eye.movement_rules = movement_rules
	eye.show_source_tile = true
	player.impulse_received.connect(_on_impulse)
	player.wall_impact.connect(_on_wall_impact)
	player.rebound_resolved.connect(_on_rebound_resolved)
	eye.range_preview = pulse_range
	hud.chapter.text = "第三轮   32 像素一格   ·   分档反弹 / 四向发波"
	hud.metric_caption.text = "墙内 · 可发波"
	hud.controls_label.text = "A / D 横移    左键整格发波    1 / 2 / 3 落下测试    R 重来    Esc 暂停    F1 普通跳跃    F2 旧机关"
	_reset_actors()
	hud.status.text = "点击脚下同列墙格起跳，斜格不施力；A / D 调整落点。"
	hud.statistics.text = "起跳 00   /   最近落地 —"
	hud.margin_bar.value = 100.0
	hud.show_message("按格点击，按档反弹", "同一格内点击，发波位置和力度都相同。\n只推同一行或同一列的玩家，斜对角格无效。\n落下 2 / 4 / 8 格，固定反弹 1 / 2 / 4 格。\n\n单击或 Enter 开始 · 数字 1 / 2 / 3 快速测落下")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F2:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/levels/l_relay_puzzle.tscn")
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
		start_drop_test([2, 4, 8][event.physical_keycode - KEY_1])
	elif event.is_action_pressed("restart") and not event.is_echo():
		restart_run()
	elif event.is_action_pressed("debug_view") and not event.is_echo():
		player.direct_jump_enabled = not player.direct_jump_enabled
		_feedback = "普通跳跃已%s；%s" % ["开启" if player.direct_jump_enabled else "关闭", "可用空格对比手感" if player.direct_jump_enabled else "现在通过声波起跳"]
		_feedback_time = 3.0
	elif event.is_action_pressed("ui_cancel") and active:
		_set_active(false)
		_paused = true
		hud.show_message("已暂停", "单击或 Enter 继续。")
	elif event.is_action_pressed("ui_accept") and not active:
		_begin_or_resume()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# A click is authoritative even if no motion event was delivered after focus/resume.
		eye.place_cursor(event.position)
		if not active:
			_begin_or_resume()
		else:
			fire_pulse()

func _begin_or_resume() -> void:
	_started = true
	_paused = false
	_set_active(true)
	hud.overlay.hide()

func _physics_process(delta: float) -> void:
	if not active:
		return
	cooldown = maxf(0.0, cooldown - delta)
	_feedback_time = maxf(0.0, _feedback_time - delta)
	if _wave_pending_jump and _was_on_floor and not player.is_on_floor():
		wave_jumps += 1
		_wave_pending_jump = false
	_was_on_floor = player.is_on_floor()
	if player.position.y > 880.0:
		_reset_actors()
		_feedback = "掉落后已回到起点。先把圆点放在脚下，再点击发波。"
		_feedback_time = 3.0
	if _feedback_time > 0:
		hud.status.text = _feedback
	elif player.position.y < 280.0 and player.position.x > 800.0:
		hud.status.text = "已跳上高台。继续测试四向推力，或按 R 重来。"
	else:
		hud.status.text = "点击脚下同列墙格起跳，斜格不施力；A / D 调整落点。"
	hud.statistics.text = "起跳 %02d   /   最近落地 %s" % [wave_jumps, _last_rebound]
	var inside := eye.is_inside_wall()
	var aligned := inside and not movement_rules.cardinal_direction(eye.source_tile_bounds().get_center(), player.global_position, eye.source_wall().global_position).is_zero_approx()
	hud.metric_caption.text = ("同排同列 · 可施力" if aligned else "斜格 · 不施力") if inside else "墙外 · 无法发波"
	var charge := 1.0 if pulse_cooldown <= 0.0 else clampf(1.0 - cooldown / pulse_cooldown, 0.0, 1.0)
	hud.margin_bar.value = charge * 100.0 if aligned else 0.0

func fire_pulse() -> Node2D:
	if not active or cooldown > 0.0:
		return null
	if not eye.is_inside_wall():
		_feedback = "这里是墙外，移到墙体内部再点击。"
		_feedback_time = 1.6
		return null
	cooldown = maxf(0.0, pulse_cooldown)
	shots += 1
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = eye.source_tile_bounds().get_center()
	pulse.grid_origin = eye.source_wall().global_position
	pulse.movement_rules = movement_rules
	pulse.target = player
	pulse.max_radius = pulse_range
	pulse.push_strength = movement_rules.launch_speed(movement_rules.wave_jump_height_tiles * movement_rules.tile_size, player.gravity)
	pulses.add_child(pulse)
	return pulse

func start_drop_test(tiles: int) -> void:
	_reset_actors()
	player.reset_to(Vector2(1152, 544.0 - 20.0 - tiles * movement_rules.tile_size))
	_begin_or_resume()
	_feedback = "落下测试：%d 格。观察落地档位与固定反弹高度。" % tiles
	_feedback_time = 1.2

func _on_rebound_resolved(drop_pixels: float, tier: int, rebound_pixels: float) -> void:
	_last_rebound = "%d 档 / %.0f 格" % [tier, rebound_pixels / movement_rules.tile_size]
	_feedback = "落差 %.1f 格 → %d 档 → 反弹 %.0f 格" % [drop_pixels / movement_rules.tile_size, tier, rebound_pixels / movement_rules.tile_size]
	_feedback_time = 1.5

func _on_impulse(impulse: Vector2, source: String) -> void:
	var direction: String
	if absf(impulse.y) > absf(impulse.x):
		direction = "向上" if impulse.y < 0.0 else "向下"
	else:
		direction = "向左" if impulse.x < 0.0 else "向右"
	_feedback = "%s：%s。配合 A / D 调整落点。" % [source, direction]
	_feedback_time = 1.8
	if source == "声波推力" and impulse.y < -100.0 and player.is_on_floor():
		_wave_pending_jump = true

func _on_wall_impact(origin: Vector2, _normal: Vector2, _strength: float) -> void:
	var pulse := Node2D.new()
	pulse.set_script(PULSE_SCRIPT)
	pulse.position = origin
	pulse.max_radius = 70.0
	pulse.wave_speed = 300.0
	pulse.visual_only = true
	pulses.add_child(pulse)

func restart_run() -> void:
	_reset_actors()
	_begin_or_resume()

func _reset_actors() -> void:
	player.reset_to(Vector2(320, 522))
	eye.reset_to(Vector2(320, 576), $Terrain/Floor)
	cooldown = 0.0
	_wave_pending_jump = false
	_was_on_floor = false
	_last_rebound = "—"
	for pulse in pulses.get_children():
		pulse.queue_free()

func _set_active(value: bool) -> void:
	active = value
	player.controls_enabled = value
	eye.input_enabled = value
	for pulse in pulses.get_children():
		pulse.set_physics_process(value)
	# Hide the OS arrow only while drawing our own locator; the pointer is never captured or clipped.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if value else Input.MOUSE_MODE_VISIBLE
