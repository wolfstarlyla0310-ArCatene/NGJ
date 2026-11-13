extends SceneTree

var failures: int = 0
var level: Node2D

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value: print("PASS  ", message)
	else:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func _run() -> void:
	level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(4)
	level.restart_run()
	var floor_wall: WallPlatform = level.get_node("Terrain/Floor")
	floor_wall.red_cells = [Vector2i(8, 0)]
	floor_wall.blue_cells = [Vector2i(9, 0)]
	for type in WaveTypes.WaveType.values():
		var cell := Vector2i(7 + type, 0)
		var origin := floor_wall.global_position + Vector2(cell) * 32.0 + Vector2(16, 16)
		level.eye.reset_to(origin, floor_wall)
		var before: int = level.pulses.get_child_count()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = root.get_canvas_transform() * origin
		root.push_input(click, true)
		check(level.pulses.get_child_count() == before + 1, "Mouse click emits type %d" % type)
		var pulse = level.pulses.get_child(-1)
		check(pulse.wave_type == type and pulse.global_position.is_equal_approx(origin), "Tile data determines type and keeps cell center")
		check(pulse.wave_speed == 760.0 and pulse.max_radius == 240.0 and not pulse.visual_only, "Propagation and push settings unchanged")
		var contact := Vector2(origin.x, floor_wall.global_position.y)
		level._on_wall_impact(contact, Vector2.UP, 200.0)
		var impact = level.pulses.get_child(-1)
		check(impact.wave_type == type and impact.global_position == contact and impact.visual_only and impact.wave_speed == 300.0, "Boundary impact preserves position and visual-only behavior for type %d" % type)
	floor_wall.red_cells = []
	floor_wall.blue_cells = []
	for type in WaveTypes.WaveType.values():
		floor_wall.wave_type = type
		level.start_drop_test(2)
		await frames(55)
		var found := false
		for pulse in level.pulses.get_children():
			if pulse.visual_only and pulse.wave_type == type: found = true
		check(found, "Real player landing emits matching impact type %d" % type)
	floor_wall.wave_type = WaveTypes.WaveType.WHITE
	var transformed := Node2D.new()
	transformed.position = Vector2(31, -17)
	transformed.rotation = 0.3
	transformed.scale = Vector2(1.3, 1.3)
	level.add_child(transformed)
	var exact := Vector2(421, 203)
	var offset_wave = WaveFactory.spawn(transformed, exact, WaveTypes.WaveType.BLUE, {"snap_to_grid": false})
	check(offset_wave.global_position.distance_to(exact) < 0.001, "Factory converts global coordinates under transformed parent")
	var source_scene := load("res://scenes/actors/SoundSource.tscn") as PackedScene
	var red = source_scene.instantiate()
	red.position = Vector2(400, 200)
	red.wave_type = WaveTypes.WaveType.RED
	red.emission_interval = 0.04
	transformed.add_child(red)
	var blue = source_scene.instantiate()
	blue.position = Vector2(600, 200)
	blue.wave_type = WaveTypes.WaveType.BLUE
	blue.emission_interval = 0.09
	level.add_child(blue)
	# Clear old pulses before counting independent timer emissions.
	for pulse in level.pulses.get_children(): pulse.queue_free()
	await create_timer(0.23).timeout
	var reds := 0
	var blues := 0
	for pulse in level.pulses.get_children():
		if pulse.wave_type == WaveTypes.WaveType.RED:
			reds += 1
			check(pulse.global_position.distance_to(red.global_position) < 0.001, "Source keeps exact global position without grid snapping")
		if pulse.wave_type == WaveTypes.WaveType.BLUE: blues += 1
	check(reds >= 4 and blues >= 2 and reds > blues, "Independent source timers and types")
	red.stop()
	blue.enabled = false
	var count: int = level.pulses.get_child_count()
	await create_timer(0.11).timeout
	check(level.pulses.get_child_count() == count, "Stopped and disabled sources emit no new pulses")
	blue.enabled = true
	blue.wave_type = WaveTypes.WaveType.RED
	blue.emission_interval = 0.02
	await create_timer(0.05).timeout
	check(level.pulses.get_child_count() > count and level.pulses.get_child(-1).wave_type == WaveTypes.WaveType.RED, "Runtime Inspector changes update type and interval")
	blue.process_mode = Node.PROCESS_MODE_DISABLED
	count = level.pulses.get_child_count()
	await create_timer(0.05).timeout
	check(level.pulses.get_child_count() == count, "Process-mode Disabled also disables timer")
	red.queue_free()
	blue.queue_free()
	await create_timer(0.9).timeout
	check(level.pulses.get_child_count() == 0, "Existing pulses finish normally after sources exit")
	var manual = source_scene.instantiate()
	manual.start_emitting = false
	manual.emission_interval = 0.0
	level.add_child(manual)
	check(manual.emission_interval > 0.0 and manual.get_node("Timer").is_stopped(), "Positive interval and opt-in start")
	check(manual.wave_type == WaveTypes.WaveType.WHITE, "Source defaults to white")
	manual.queue_free()
	var legacy: Node2D = load("res://scenes/levels/first_crossing.tscn").instantiate()
	root.add_child(legacy)
	var echo = legacy.emit_wave(legacy.eye.global_position, WaveTypes.WaveType.BLUE)
	check(echo.wave_type == WaveTypes.WaveType.BLUE and echo.lifetime == 2.4, "Legacy echoes use shared factory with original lifetime")
	legacy.queue_free()
	print("Color wave checks: ", "ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
