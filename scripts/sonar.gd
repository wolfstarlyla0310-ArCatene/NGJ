extends Node2D
## Expanding pulses reveal ONLY short-lived exterior edge fragments at their time of arrival.

@export var wave_speed: float = 520.0
@export var echo_linger: float = 0.85
@export var segment_length: float = 10.0

var walls: Array[WallPlatform] = []
var eye: WallEye
var wave_container: Node2D

func _process(_delta: float) -> void:
	queue_redraw()

func echo_at(point: Vector2, type: int = -1) -> float:
	if eye == null or wave_container == null:
		return 0.0
	var ear_distance := point.distance_to(eye.global_position)
	if ear_distance > eye.sight_radius:
		return 0.0
	var intensity: float = 0.0
	for wave in wave_container.get_children():
		if wave.is_queued_for_deletion() or (type >= 0 and wave.wave_type != type):
			continue
		var arrival: float = point.distance_to(wave.global_position) / wave_speed
		var elapsed: float = wave.age - arrival
		if elapsed >= 0.0 and elapsed < echo_linger:
			var fade := 1.0 - elapsed / echo_linger
			intensity = maxf(intensity, wave.strength * fade * fade)
	return intensity * (1.0 - smoothstep(eye.sight_radius - 80.0, eye.sight_radius, ear_distance))

func _draw() -> void:
	if eye == null:
		return
	for wall in walls:
		var rect := wall.bounds()
		var a := rect.position
		var b := Vector2(rect.end.x, rect.position.y)
		var c := rect.end
		var d := Vector2(rect.position.x, rect.end.y)
		_draw_reflected_edge(a, b, Vector2.UP, wall)
		_draw_reflected_edge(b, c, Vector2.RIGHT, wall)
		_draw_reflected_edge(c, d, Vector2.DOWN, wall)
		_draw_reflected_edge(d, a, Vector2.LEFT, wall)

func _draw_reflected_edge(a: Vector2, b: Vector2, normal: Vector2, owner_wall: WallPlatform) -> void:
	var count := maxi(1, ceili(a.distance_to(b) / segment_length))
	for i in range(count):
		var start := a.lerp(b, float(i) / count)
		var end := a.lerp(b, float(i + 1) / count)
		var middle := (start + end) * 0.5
		if middle.distance_to(eye.global_position) > eye.sight_radius:
			continue
		var inside_neighbor := false
		for wall in walls:
			if wall != owner_wall and wall.bounds().has_point(middle + normal):
				inside_neighbor = true
				break
		if inside_neighbor:
			continue
		for type in WaveTypes.WaveType.values():
			var alpha := echo_at(middle, type)
			if alpha > 0.015:
				draw_line(to_local(start), to_local(end), Color(WaveTypes.color_for(type), alpha), 1.7, true)
