class_name ForcePulse
extends Node2D
## Grid-centered pulse: fixed strength, cardinal alignment only, one hit per player.

signal hit_player(impulse: Vector2)

var target: EchoPlayer
var max_radius: float = 240.0
var wave_speed: float = 760.0
var push_strength: float = 0.0
var grid_origin := Vector2.ZERO
var movement_rules: MovementRules = preload("res://resources/movement_rules.tres")
var age: float = 0.0
var radius: float = 0.0
var has_hit: bool = false
var visual_only: bool = false
var lifetime: float = 0.65

func _ready() -> void:
	process_physics_priority = -10
	lifetime = max_radius / wave_speed + 0.28
	if not visual_only:
		global_position = movement_rules.cell_center(movement_rules.cell_at(global_position, grid_origin), grid_origin)
		if push_strength <= 0.0:
			var gravity: float = target.gravity if is_instance_valid(target) else 1500.0
			push_strength = movement_rules.launch_speed(movement_rules.wave_jump_height_tiles * movement_rules.tile_size, gravity)

func _physics_process(delta: float) -> void:
	age += delta
	var previous_radius := radius
	radius = minf(max_radius, age * wave_speed)
	if not visual_only and not has_hit and is_instance_valid(target) and age * wave_speed <= max_radius + 18.0:
		var offset := target.global_position - global_position
		var distance := offset.length()
		if distance <= max_radius and distance <= radius + 14.0 and distance >= previous_radius - 14.0:
			has_hit = true
			var direction := movement_rules.cardinal_direction(global_position, target.global_position, grid_origin)
			if not direction.is_zero_approx():
				var impulse := direction * push_strength
				target.add_impulse(impulse)
				hit_player.emit(impulse)
	if age > lifetime:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	var alpha := clampf((lifetime - age) / 0.28, 0.0, 1.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 100, Color(0, 0, 0, alpha * 0.8), 4.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 100, Color(1, 1, 1, alpha), 1.5, true)
	if radius > 18.0:
		draw_arc(Vector2.ZERO, radius - 12.0, 0.0, TAU, 100, Color(1, 1, 1, alpha * 0.25), 1.0, true)
