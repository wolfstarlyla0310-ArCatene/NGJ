extends Node
class_name RoomCameraController
## 房间切换与相机取景：判断玩家在哪个房间，房间一变就把相机 Tween 过去，并按房间大小自动缩放。
## 相机在房间内固定取景、不跟随玩家（position_smoothing 必须保持关闭）。
## 不认识 WorldMap 具体类型，只调鸭子接口（get_room_focus_position / room_at / get_checkpoint_room）并订阅 room_reset。
## 本脚本只写 global_position 与 zoom。

## 玩家（主控猫）真的跨进了某个房间 —— 本脚本是全项目唯一一处「跨房间」判定，故广播出去。
## 与 room_exited 成对：跨房间时先发 exited(旧房间)、紧接着发 entered(新房间)。
signal room_entered(room: Room)
## 玩家离开了某个房间。见 `room_entered`。
signal room_exited(room: Room)

## 大地图取景相机（场景里名为 Camera 的 Camera2D）。
@export var camera: Camera2D
## 大地图根：需提供 get_room_focus_position() / room_at() / get_checkpoint_room()，并带 room_reset 信号。
## 只提供 get_player_position() 也能跑（旧场景），此时取景焦点退化成「主控的那只猫」。
@export var world: Node
## 切换房间时相机滑动与缩放的时长（秒）。≤ 0 表示瞬时；相邻房间相距约一屏宽，0.5 左右跟得上。
@export var transition_duration := 0.5
## 滑动用的缓动曲线。TRANS_CUBIC 比 SINE 起步更缓、中段更匀，观感更顺。
@export var transition_trans: Tween.TransitionType = Tween.TRANS_CUBIC
## 滑动用的缓动方式。EASE_IN_OUT = 两头慢、中间快，不会「一上来就猛冲」。
@export var transition_ease: Tween.EaseType = Tween.EASE_IN_OUT
## 边缘余量（像素）：玩家要「深入」新房间这么多像素才真的切，防止贴着门槛来回抖动。
@export var switch_margin := 4.0
## 自动缩放的四周留白比例（0 = 房间铺满屏幕；0.08 ≈ 每边留 4%）。
@export_range(0.0, 0.4, 0.01) var fit_margin := 0.08
## 自动缩放的下限（越小看得越广）；只用于极端窗口保护，平时不会碰到。
@export var min_zoom := 1.0
## 自动缩放的上限（越大放得越大）；只用于极小房间保护，平时不会碰到。
@export var max_zoom := 8.0
## 窗口尺寸变化后重新适配当前房间的时长（秒）；≤ 0 表示瞬时。
@export var resize_duration := 0.2

# 当前取景的房间
var _active_room: Room = null
# 是否正在滑向某个房间（滑动期间不叠加第二次切换）
var _switching := false
# 滑动期间玩家又跨进了别的房间 —— 等这一段滑完立刻接上（高速连穿两间时不丢帧）
var _pending_room: Room = null
# 正在跑的相机 Tween
var _tween: Tween = null
# 相机是否已到位。用标志位而不是 await tween.finished（被 kill 的 Tween 不发 finished，await 会永久挂起）。
var _arrived := true


func _ready() -> void:
	if camera != null:
		camera.make_current()
		# 窗口 / 分辨率变化时按新视口重新算缩放
		var viewport := camera.get_viewport()
		if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
			viewport.size_changed.connect(_on_viewport_size_changed)
	if world != null and world.has_signal(&"room_reset"):
		world.room_reset.connect(_on_room_reset)
	# 开局取景延后一帧：WorldMap 在自己的 _ready 里才接管主控猫，当帧可能问不出玩家位置。
	call_deferred("_initial_snap")


func _process(_delta: float) -> void:
	if world == null:
		return

	# 留意「玩家现在在哪个房间」——滑动期间也要记，才能接上高速连穿的下一间
	var candidate: Room = null
	var point: Variant = _player_position()
	if point is Vector2:
		candidate = _room_at(point)

	if _switching:
		if candidate != null and candidate != _active_room:
			_pending_room = candidate            # 排进队列，不与当前这段滑动叠加
		if _arrived:
			_switching = false
			_consume_pending()
		return

	# 没有玩家 → 保持当前取景静默降级；主控恢复后下一帧自然会被重新判定。
	if candidate == null or candidate == _active_room:
		return                                   # 走在没有房间覆盖的空隙里 / 房间没变
	if not _is_deep_enough(candidate, point):
		return                                   # 玩家还蹭在门槛上，等走进来一点再切
	_switch_to(candidate)


## ——— 对外接口 ———

## 当前取景的房间（还没取景时为 null）。
func get_active_room() -> Room:
	return _active_room


## 是否正在切房间。
func is_switching() -> bool:
	return _switching


## 瞬时把相机放到某个房间（开局取景 / R 重置后），不走 Tween。
## 若此刻有一段滑动在跑会被中止（R 重置应回到存档点，不该被上一次动画带走）。
## 刻意不发 room_entered / room_exited：开局那一下若发信号会改写「存档点 = 初始 cat 位置」的语义。
## 已知取舍：开局站在起始房间里时不会给该房间的 fish 自动绑定，要走出去再回来才绑。
func snap_to(room: Room) -> void:
	if room == null or camera == null:
		return
	_kill_tween()
	_switching = false
	_pending_room = null
	_active_room = room
	camera.global_position = room.get_camera_target()
	camera.zoom = Vector2.ONE * _fit_zoom(room)
	# 相机自身的变换要立即生效，否则本帧渲染会沿用旧变换（一帧残影）
	camera.reset_smoothing()


## 用 Tween 把相机滑到某个房间。duration < 0 时用 transition_duration。
func tween_to(room: Room, duration: float = -1.0) -> void:
	if room == null or camera == null:
		return
	var seconds := transition_duration if duration < 0.0 else duration
	var target := room.get_camera_target()
	var target_zoom := Vector2.ONE * _fit_zoom(room)
	_kill_tween()
	if seconds <= 0.0:
		camera.global_position = target
		camera.zoom = target_zoom
		return
	_arrived = false
	_tween = create_tween()
	# 曲线与缓动走导出项（检查器里可调），不在代码里写死
	_tween.set_trans(transition_trans).set_ease(transition_ease)
	_tween.tween_property(camera, "global_position", target, seconds)
	# 位置与缩放必须挂在同一条 Tween 上，_kill_tween() 才能一次全部中止
	_tween.parallel().tween_property(camera, "zoom", target_zoom, seconds)
	_tween.finished.connect(_on_tween_finished)


## ——— 内部 ———

## 开始切到某个房间。跨房间的信号在这里发（全项目唯一一处）：
## 先发 room_exited(旧房间)、紧接着发 room_entered(新房间)，连穿也照常各发一对。
func _switch_to(room: Room) -> void:
	if room == null or not is_instance_valid(room):
		return
	var previous := _active_room
	_switching = true
	_active_room = room
	_pending_room = null
	if previous != null and is_instance_valid(previous) and previous != room:
		room_exited.emit(previous)
	room_entered.emit(room)
	tween_to(room)


## 滑动收尾后，把排队中的下一间接上（没有就什么都不做）。
func _consume_pending() -> void:
	var next := _pending_room
	_pending_room = null
	if next != null and is_instance_valid(next) and next != _active_room:
		_switch_to(next)


## 让整间房完整入屏的目标 zoom：取视口与房间宽高比的较小值，再留 fit_margin 边距。
## 视口运行时查询（aspect=expand 会随窗口变），不写死设计分辨率。
func _fit_zoom(room: Room) -> float:
	if room == null or camera == null:
		return 1.0
	var viewport_size := camera.get_viewport_rect().size
	var room_size := room.get_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or room_size.x <= 0.0 or room_size.y <= 0.0:
		return camera.zoom.x
	var fit := minf(viewport_size.x / room_size.x, viewport_size.y / room_size.y)
	return clampf(fit * (1.0 - fit_margin), min_zoom, max_zoom)


## 玩家是否已「深入」候选房间 switch_margin 像素（滞回，防止贴边抖动）。
func _is_deep_enough(room: Room, point: Vector2) -> bool:
	if switch_margin <= 0.0:
		return true
	var inner := room.get_rect().grow(-switch_margin)
	# 房间比余量还小：别把它判成「永远进不去」
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return true
	return BoundsDrag.in_rect(inner, point)


## 相机 Tween 跑完。
func _on_tween_finished() -> void:
	_arrived = true


## 中止当前相机 Tween（若有），并把「等待到位」一并解除。
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_arrived = true


## 窗口尺寸变了 → 按新视口重新适配当前房间；正在切房间时先让那一段滑完。
func _on_viewport_size_changed() -> void:
	if _active_room == null or _switching or not is_instance_valid(_active_room):
		return
	tween_to(_active_room, resize_duration)


## R 键重置了某个房间 → 相机瞬时切到该房间取景。
func _on_room_reset(room: Room) -> void:
	snap_to(room)


## 开局取景：优先玩家所在房间，其次存档点房间，最后第一间。
func _initial_snap() -> void:
	var room: Room = null
	var point: Variant = _player_position()
	if point is Vector2:
		room = _room_at(point)
	if room == null:
		room = _checkpoint_room()
	if room == null and world != null and world.has_method("get_rooms"):
		var rooms: Array = world.get_rooms()
		if not rooms.is_empty():
			room = rooms[0] as Room
	if room != null:
		snap_to(room)


## 取景焦点（玩家）现在的世界坐标；问不出来时返回 null。
func _player_position() -> Variant:
	if world == null:
		return null
	if world.has_method(&"get_room_focus_position"):
		return world.get_room_focus_position()
	if world.has_method(&"get_player_position"):
		return world.get_player_position()
	return null


## 世界坐标落在哪个房间（委托地图根，规则本体在 RoomRegistry）。
func _room_at(point: Vector2) -> Room:
	if world != null and world.has_method("room_at"):
		return world.room_at(point) as Room
	return null


## 当前存档点房间（可能为 null）。
func _checkpoint_room() -> Room:
	if world != null and world.has_method("get_checkpoint_room"):
		return world.get_checkpoint_room() as Room
	return null
