extends SceneTree

const PULSE_SCRIPT := preload("res://scripts/force_pulse.gd")
var level: Node2D
var failures: Array[String] = []
var landings: Array[Dictionary] = []
var forces: Array[Vector2] = []

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, text: String) -> void:
	if value:
		print("PASS  ", text)
	else:
		failures.append(text)
		push_error("FAIL  " + text)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func record_landing(drop: float, tier: int, height: float) -> void:
	landings.append({"drop": drop, "tier": tier, "height": height, "speed": -level.player.velocity.y, "y": level.player.position.y})

func record_force(force: Vector2, source: String) -> void:
	if source == "声波推力":
		forces.append(force)

func test_drop(distance: float, expected_tier: int, expected_height: float, initial_speed: float = 0.0) -> Dictionary:
	level.restart_run()
	landings.clear()
	level.player.reset_to(Vector2(1152, 524.0 - distance))
	level.player.velocity.y = initial_speed
	var timeout := 360
	while landings.is_empty() and timeout > 0:
		await physics_frame
		timeout -= 1
	if landings.is_empty():
		check(false, "Drop %.0f px produces a landing" % distance)
		return {}
	var result := landings[0]
	check(result.tier == expected_tier and is_equal_approx(result.height, expected_height), "Drop %.0f px maps to tier %d / rebound %.0f px" % [distance, expected_tier, expected_height])
	check(absf(result.drop - distance) < 0.3, "Drop %.0f px is measured from actual airborne apex" % distance)
	if expected_tier > 0:
		var apex: float = level.player.position.y
		while level.player.velocity.y < 0.0 and timeout > 0:
			await physics_frame
			timeout -= 1
			apex = minf(apex, level.player.position.y)
		var measured: float = result.y - apex
		check(absf(measured - expected_height) < 0.5, "Actual tier %d rebound reaches %.0f px (measured %.2f)" % [expected_tier, expected_height, measured])
	return result

func _run() -> void:
	level = load("res://scenes/main.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await frames(4)
	level.player.rebound_resolved.connect(record_landing)
	level.player.impulse_received.connect(record_force)
	check(level.movement_rules.tile_size == 32.0, "Grid standard is 32 pixels per tile")
	await test_drop(63, 0, 0)
	var small := await test_drop(64, 1, 32)
	await test_drop(127, 1, 32)
	var medium := await test_drop(128, 2, 64)
	var same_medium := await test_drop(200, 2, 64)
	await test_drop(255, 2, 64)
	var high := await test_drop(256, 3, 128)
	var capped := await test_drop(384, 3, 128)
	check(is_equal_approx(medium.speed, same_medium.speed), "Different falls in the same tier produce identical takeoff speed")
	check(is_equal_approx(high.speed, capped.speed), "High drops are capped to the same fixed highest rebound")
	var fast_small := await test_drop(64, 1, 32, 800)
	check(is_equal_approx(small.speed, fast_small.speed), "Tier depends on height, not impact speed")

	level.restart_run()
	landings.clear()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_3
	key.pressed = true
	root.push_input(key, true)
	var timeout := 240
	while landings.is_empty() and timeout > 0:
		await physics_frame
		timeout -= 1
	check(not landings.is_empty() and landings[0].tier == 3, "Number 3 shortcut performs the real eight-tile drop test")

	level.restart_run()
	level.player.controls_enabled = false
	level.eye.input_enabled = false
	var first_center := Vector2.ZERO
	var first_force := Vector2.ZERO
	for point in [Vector2(321, 545), Vector2(350, 574), Vector2(335, 560)]:
		level.player.reset_to(Vector2(336, 522))
		level.eye.reset_to(point, level.get_node("Terrain/Floor"))
		forces.clear()
		var pulse: Node2D = level.fire_pulse()
		check(pulse != null and pulse.position.is_equal_approx(Vector2(336, 560)), "Every click inside the same tile emits from its center")
		await frames(24)
		check(forces.size() == 1 and forces[0].x == 0.0 and forces[0].y < 0.0, "Grid-aligned floor click applies only upward force")
		if first_center == Vector2.ZERO:
			first_center = pulse.position
			first_force = forces[0]
		else:
			check(pulse.position == first_center and forces[0].is_equal_approx(first_force), "Sub-tile click positions produce exactly the same origin and impulse")
		pulse.queue_free()
	level.player.reset_to(Vector2(336, 522))
	level.eye.reset_to(Vector2(336, 590), level.get_node("Terrain/Floor"))
	forces.clear()
	level.fire_pulse()
	await frames(24)
	check(forces.size() == 1 and forces[0].is_equal_approx(first_force), "Aligned clicks use fixed strength without distance falloff")

	for origin in [Vector2(400, 560), Vector2(368, 592)]:
		level.player.reset_to(Vector2(336, 522))
		level.eye.reset_to(origin, level.get_node("Terrain/Floor"))
		forces.clear()
		level.fire_pulse()
		await frames(30)
		check(forces.is_empty() and level.player.velocity.is_zero_approx(), "Diagonal wall tile produces no force, even when vertical offset dominates")

	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		level.player.reset_to(Vector2(640, 320))
		forces.clear()
		var pulse := Node2D.new()
		pulse.set_script(PULSE_SCRIPT)
		pulse.position = level.player.position - direction * 80.0
		pulse.target = level.player
		level.pulses.add_child(pulse)
		await frames(24)
		check(forces.size() == 1 and forces[0].normalized().is_equal_approx(direction) and (forces[0].x == 0.0 or forces[0].y == 0.0), "Pulse direction is exactly cardinal " + str(direction))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("\nGrid and rebound checks: ", "ALL PASSED" if failures.is_empty() else "%d FAILED" % failures.size())
	quit(0 if failures.is_empty() else 1)
