@tool
extends Node2D
## Independent periodic pulses. Disable with Enabled or Node process_mode = Disabled.

@export var wave_type: WaveTypes.WaveType = WaveTypes.WaveType.WHITE:
	set(value):
		wave_type = value
		queue_redraw()
@export_range(0.001, 3600.0, 0.001, "or_greater", "suffix:s") var emission_interval: float = 1.0:
	set(value):
		emission_interval = maxf(0.001, value)
		if is_node_ready():
			$Timer.wait_time = emission_interval
			if not Engine.is_editor_hint() and not $Timer.is_stopped(): $Timer.start()
@export var start_emitting: bool = true
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready() and not Engine.is_editor_hint():
			if enabled and _emitting: $Timer.start()
			else: $Timer.stop()
var _emitting: bool = false

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint(): return
	$Timer.wait_time = emission_interval
	$Timer.timeout.connect(_emit_pulse)
	if start_emitting: start()

func start() -> void:
	_emitting = true
	if is_node_ready() and enabled and not Engine.is_editor_hint(): $Timer.start()

func stop() -> void:
	_emitting = false
	if is_node_ready(): $Timer.stop()

func _exit_tree() -> void:
	$Timer.stop()

func _emit_pulse() -> void:
	if not enabled or not _emitting or not can_process(): return
	var host := get_parent()
	while host != null:
		if host.has_method("emit_wave"):
			host.emit_wave(global_position, wave_type, {"snap_to_grid": false})
			return
		host = host.get_parent()
	# Standalone scenes also work; emitted pulses outlive the source.
	var container := get_tree().current_scene as Node2D
	if container == null: container = get_parent() as Node2D
	if container != null:
		WaveFactory.spawn(container, global_position, wave_type, {"snap_to_grid": false})

func _draw() -> void:
	var color := WaveTypes.color_for(wave_type)
	draw_circle(Vector2.ZERO, 7.0, color)
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 40, color, 2.0, true)
