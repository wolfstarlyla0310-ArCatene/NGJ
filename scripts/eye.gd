class_name WallEye
extends Node2D
## Free cursor for wave tests; constrained movement remains available for the earlier relay.

@export var radius: float = 12.0
@export var sensitivity: float = 1.0
@export var sight_radius: float = 520.0
@export var hearing_radius: float = 760.0
@export var dark_marker: bool = false
@export var range_preview: float = 0.0
@export var free_cursor: bool = false

var input_enabled: bool = false
var walls: Array[WallPlatform] = []
var host: WallPlatform
var _host_position := Vector2.ZERO
var _pending_motion := Vector2.ZERO
var _look := Vector2.RIGHT

func _ready() -> void:
	process_physics_priority = 10

func _unhandled_input(event: InputEvent) -> void:
	if input_enabled and event is InputEventMouseMotion:
		if free_cursor:
			place_cursor(event.position)
		else:
			_pending_motion += event.relative * sensitivity

func place_cursor(viewport_position: Vector2) -> void:
	global_position = get_viewport().get_canvas_transform().affine_inverse() * viewport_position
	host = null
	_pending_motion = Vector2.ZERO
	queue_redraw()

func _physics_process(_delta: float) -> void:
	if not input_enabled:
		_pending_motion = Vector2.ZERO
		return
	if free_cursor:
		host = null
		_pending_motion = Vector2.ZERO
		queue_redraw()
		return
	if is_instance_valid(host):
		global_position += host.global_position - _host_position
	move_within_walls(_pending_motion.limit_length(480.0))
	_pending_motion = Vector2.ZERO
	_update_host()
	queue_redraw()

func move_within_walls(motion: Vector2) -> void:
	if motion.length_squared() < 0.0001:
		return
	_look = motion.normalized()
	var steps := maxi(1, ceili(motion.length() / 3.0))
	var step := motion / float(steps)
	for _i in range(steps):
		if can_occupy(global_position + step):
			global_position += step
		else:
			if can_occupy(global_position + Vector2(step.x, 0)):
				global_position.x += step.x
			if can_occupy(global_position + Vector2(0, step.y)):
				global_position.y += step.y
	_update_host()

func can_occupy(point: Vector2) -> bool:
	# Subtract each solid from the eye's footprint. Even sub-pixel gaps remain uncovered.
	# A square footprint is intentionally conservative around the round eye.
	var uncovered: Array[Rect2] = [Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)]
	for wall in walls:
		var next: Array[Rect2] = []
		var solid := wall.bounds().grow(0.001)
		for area in uncovered:
			var overlap := area.intersection(solid)
			if not overlap.has_area():
				next.append(area)
				continue
			if overlap.position.y > area.position.y:
				next.append(Rect2(area.position, Vector2(area.size.x, overlap.position.y - area.position.y)))
			if overlap.end.y < area.end.y:
				next.append(Rect2(Vector2(area.position.x, overlap.end.y), Vector2(area.size.x, area.end.y - overlap.end.y)))
			if overlap.position.x > area.position.x:
				next.append(Rect2(Vector2(area.position.x, overlap.position.y), Vector2(overlap.position.x - area.position.x, overlap.size.y)))
			if overlap.end.x < area.end.x:
				next.append(Rect2(Vector2(overlap.end.x, overlap.position.y), Vector2(area.end.x - overlap.end.x, overlap.size.y)))
		uncovered = next
		if uncovered.is_empty():
			return true
	return false

func is_inside_wall() -> bool:
	for wall in walls:
		if wall.bounds().has_point(global_position):
			return true
	return false

func _update_host() -> void:
	# If a moving platform overlaps a seam, prefer it, so departure carries the eye safely.
	var candidate: WallPlatform = null
	for wall in walls:
		if wall.bounds().grow(0.01).has_point(global_position):
			if candidate == null or not wall.travel_offset.is_zero_approx():
				candidate = wall
	if candidate != null:
		host = candidate
	if is_instance_valid(host):
		var interior := host.bounds().grow(-radius)
		# At a dock, move completely into the destination before the platforms separate.
		if not can_occupy(global_position):
			global_position = global_position.clamp(interior.position, interior.end)
		_host_position = host.global_position

func reset_to(point: Vector2, start_wall: WallPlatform) -> void:
	global_position = point
	host = start_wall
	_host_position = host.global_position
	_pending_motion = Vector2.ZERO
	queue_redraw()

func _draw() -> void:
	# A neutral locator, with no eye/face anatomy.
	var valid_source := is_inside_wall() if free_cursor else true
	var ink := Color.BLACK if (valid_source and (dark_marker or free_cursor)) else Color.WHITE
	draw_circle(Vector2.ZERO, 2.5, ink)
	ink.a = 0.45
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 32, ink, 1.0, true)
	if free_cursor and not valid_source:
		draw_line(Vector2(-4, -4), Vector2(4, 4), Color(1, 1, 1, 0.6), 1.0, true)
	if range_preview > 0 and valid_source:
		for i in range(48):
			var angle := TAU * float(i) / 48.0
			draw_arc(Vector2.ZERO, range_preview, angle, angle + 0.05, 5, Color(1, 1, 1, 0.23), 1.0, true)
